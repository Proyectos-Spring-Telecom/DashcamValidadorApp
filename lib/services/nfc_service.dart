import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';
import '../utils/nfc_result_codes.dart';

/// Modelo para la respuesta de lectura NFC M1
class NfcM1Response {
  final int result;
  final String? cardUid;

  NfcM1Response({
    required this.result,
    this.cardUid,
  });

  factory NfcM1Response.fromJson(Map<String, dynamic> json) {
    return NfcM1Response(
      result: _parseResult(json['result']),
      cardUid: json['cardUid']?.toString(),
    );
  }

  static int _parseResult(dynamic value) {
    if (value == null) return -1;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? -1;
    return -1;
  }

  /// Verifica si la lectura fue exitosa
  bool get isSuccess => result == 0;

  /// Verifica si hay error
  bool get hasError => result != 0;

  /// Indica si conviene reintentar la lectura (sin tarjeta / fallo momentáneo).
  bool get isRetryable => NfcResultCodes.isRetryable(result);

  /// Obtiene mensaje de error basado en el código de resultado
  String get errorMessage => NfcResultCodes.message(result);
}

/// Lectura de tarjetas NFC M1 solo por NFC nativo (sin HTTP en claro).
class NfcService {
  /// Lee una tarjeta NFC M1 con NFC nativo de Android.
  static Future<NfcM1Response> readM1Card() async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final nativeResponse = await _readM1FromAndroidNfc();
        if (nativeResponse != null) {
          return nativeResponse;
        }
      }
      return NfcM1Response(result: -1);
    } catch (e) {
      return NfcM1Response(result: -1);
    }
  }

  /// Lee NFC en Android con una sola sesión de [timeout].
  ///
  /// Usa [NfcReaderFlagAndroid.skipNdefCheck] para que tarjetas MIFARE u otras
  /// sin NDEF no disparen el mensaje del sistema "No supported application for this NFC tag".
  /// Retorna null solo ante error de plataforma; [-1] si caduca sin tarjeta.
  static Future<NfcM1Response?> _readM1FromAndroidNfc({
    Duration? timeout,
  }) async {
    final sessionTimeout = timeout ?? AppConfig.nfcCardReadTimeout;
    try {
      final availability = await NfcManager.instance.checkAvailability();
      if (availability != NfcAvailability.enabled) {
        appLogger.w('NFC no disponible en este dispositivo');
        appLogger.d('NFC nativo: no disponible ($availability)');
        return null;
      }

      appLogger.d('NFC nativo: sesión reader mode iniciada');

      NfcM1Response? parsed;
      var completed = false;

      await NfcManagerAndroid.instance.enableReaderMode(
        flags: {
          NfcReaderFlagAndroid.nfcA,
          NfcReaderFlagAndroid.nfcB,
          NfcReaderFlagAndroid.nfcV,
          NfcReaderFlagAndroid.nfcF,
          NfcReaderFlagAndroid.nfcBarcode,
          NfcReaderFlagAndroid.skipNdefCheck,
        },
        onTagDiscovered: (tag) async {
          if (completed) return;
          final tagAndroid = NfcTagAndroid.from(tag);
          final uid = tagAndroid != null && tagAndroid.id.isNotEmpty
              ? tagAndroid.id
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join()
                  .toUpperCase()
              : null;
          if (uid != null && uid.isNotEmpty) {
            parsed = NfcM1Response(result: 0, cardUid: uid);
            appLogger.d('Tag detectado UID=$uid');
          } else {
            parsed = NfcM1Response(result: -1);
            appLogger.d('Tag detectado pero sin UID');
          }
          completed = true;
          try {
            await NfcManagerAndroid.instance.disableReaderMode();
          } catch (_) {}
        },
      );

      final deadline = DateTime.now().add(sessionTimeout);
      while (!completed && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 120));
      }

      if (!completed) {
        completed = true;
        try {
          await NfcManagerAndroid.instance.disableReaderMode();
        } catch (_) {}
        return NfcM1Response(result: -1);
      }

      return parsed ?? NfcM1Response(result: -1);
    } catch (e) {
      appLogger.w('Error lectura NFC nativa Android: $e');
      appLogger.d('Error NFC nativo: $e');
      try {
        await NfcManagerAndroid.instance.disableReaderMode();
      } catch (_) {}
      return null;
    }
  }

  /// Espera hasta [timeout] a que se acerque una tarjeta y devuelve el UID (hex).
  static Future<String?> readCardUidWithTimeout({Duration? timeout}) async {
    final limit = timeout ?? AppConfig.nfcCardReadTimeout;

    final nativeEnabled = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        await NfcManager.instance.checkAvailability() ==
            NfcAvailability.enabled;

    appLogger.d(
      'Espera tarjeta (${limit.inSeconds}s) | nativo=$nativeEnabled',
    );

    if (!nativeEnabled) {
      appLogger.w('NFC nativo no disponible; cleartext HTTP deshabilitado');
      return null;
    }

    appLogger.d('Modo: NFC nativo del teléfono');
    final r = await _readM1FromAndroidNfc(timeout: limit);
    if (r != null &&
        r.isSuccess &&
        r.cardUid != null &&
        r.cardUid!.isNotEmpty) {
      appLogger.d('✓ UID nativo: ${r.cardUid}');
      return r.cardUid;
    }
    appLogger.d(
      'NFC nativo sin tarjeta (result=${r?.result ?? "null"})',
    );
    return null;
  }

  /// Lector HTTP externo deshabilitado (cleartext apagado).
  static Future<bool> isExternalReaderAvailable() async => false;

  /// NFC nativo habilitado en este dispositivo.
  static Future<bool> isNativeNfcEnabled() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    return await NfcManager.instance.checkAvailability() ==
        NfcAvailability.enabled;
  }

  /// Lee tarjeta M1 con reintentos
  static Future<NfcM1Response> readM1CardWithRetries({
    int maxRetries = 3,
    Duration delayBetweenRetries = const Duration(milliseconds: 500),
  }) async {
    for (int i = 0; i < maxRetries; i++) {
      final response = await readM1Card();

      if (response.isSuccess) {
        return response;
      }

      if (i < maxRetries - 1) {
        await Future.delayed(delayBetweenRetries);
      }
    }

    return await readM1Card();
  }

  /// Servidor HTTP local NFC deshabilitado (cleartext apagado).
  static Future<bool> isNfcServerAvailable() async => false;

  /// Información de capacidades NFC para debug
  static Future<Map<String, dynamic>> getServerInfo() async {
    final native = await isNativeNfcEnabled();
    return {
      'nativeNfc': native,
      'httpReaderEnabled': false,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }
}
