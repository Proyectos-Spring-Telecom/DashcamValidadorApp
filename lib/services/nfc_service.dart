import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:network_info_plus/network_info_plus.dart';
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

/// Servicio para lectura de tarjetas NFC M1 usando el servidor HTTP local
class NfcService {
  static final Dio _dio = Dio();
  
  /// Obtiene la IP local del dispositivo
  static Future<String?> _getLocalIp() async {
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (e) {
      return null;
    }
  }
  
  /// Lee una tarjeta NFC M1 del servidor HTTP local
  static Future<NfcM1Response> readM1Card() async {
    try {
      // En Android, intentar primero lectura NFC nativa.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final nativeResponse = await _readM1FromAndroidNfc();
        if (nativeResponse != null && nativeResponse.isSuccess) {
          return nativeResponse;
        }
      }

      // Intentar con la IP local primero
      final localIp = await _getLocalIp();
      if (localIp != null) {
        final response = await _readM1FromServer(localIp);
        if (response != null && response.isSuccess) {
          return response;
        }
      }
      
      // Fallback: intentar con localhost
      final responseLocal = await _readM1FromServer('127.0.0.1');
      if (responseLocal != null && responseLocal.isSuccess) {
        return responseLocal;
      }
      
      // Si no se puede conectar al servidor, devolver error
      return NfcM1Response(result: -1);
    } catch (e) {
      return NfcM1Response(result: -1);
    }
  }

  /// Intenta leer UID vía API HTTP del dispositivo (sin abrir sesión NFC nativa).
  static Future<NfcM1Response?> _readM1FromAnyServer() async {
    final localIp = await _getLocalIp();
    if (localIp != null) {
      final r = await _readM1FromServer(localIp);
      if (r != null && r.isSuccess) return r;
    }
    return await _readM1FromServer('127.0.0.1');
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
  
  /// Lee tarjeta M1 del servidor HTTP local específico
  static Future<NfcM1Response?> _readM1FromServer(String ip) async {
    final url = 'http://$ip:${AppConfig.localDeviceApiPort}/nfc/m1';
    try {
      appLogger.d('GET $url');
      final response = await _dio.get(
        url,
        options: Options(
          sendTimeout: AppConfig.nfcReadTimeout,
          receiveTimeout: AppConfig.nfcReadTimeout,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final parsed = NfcM1Response.fromJson(data);
        appLogger.d(
          '← $ip result=${parsed.result} uid=${parsed.cardUid ?? "(vacío)"}',
        );
        return parsed;
      }
      appLogger.d('← $ip HTTP ${response.statusCode}');
    } catch (e) {
      appLogger.d('✗ $ip error: $e');
      return null;
    }
    return null;
  }

  /// Espera hasta [timeout] a que se acerque una tarjeta y devuelve el UID (hex).
  ///
  /// - NFC nativo del teléfono (Android), si está habilitado.
  /// - Lector externo vía HTTP local `GET /nfc/m1` (puerto [AppConfig.localDeviceApiPort]).
  static Future<String?> readCardUidWithTimeout({Duration? timeout}) async {
    final limit = timeout ?? AppConfig.nfcCardReadTimeout;
    final deadline = DateTime.now().add(limit);
    var poll = 0;
    String? lastUid;
    var stableReads = 0;

    final nativeEnabled = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        await NfcManager.instance.checkAvailability() ==
            NfcAvailability.enabled;

    appLogger.d(
      'Espera tarjeta (${limit.inSeconds}s) | nativo=$nativeEnabled',
    );

    if (nativeEnabled) {
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
    } else {
      appLogger.d(
        'Modo: lector HTTP :${AppConfig.localDeviceApiPort}/nfc/m1',
      );
    }

    while (DateTime.now().isBefore(deadline)) {
      poll++;
      final response = await _readM1FromAnyServer();
      if (response != null &&
          response.isSuccess &&
          response.cardUid != null &&
          response.cardUid!.isNotEmpty) {
        final uid = response.cardUid!;
        if (uid == lastUid) {
          stableReads++;
        } else {
          lastUid = uid;
          stableReads = 1;
        }
        if (stableReads >= 2) {
          appLogger.d(
            '✓ UID lector HTTP (poll #$poll, estable): $uid',
          );
          return uid;
        }
        appLogger.d('UID candidato (poll #$poll): $uid — confirmando…');
      } else {
        lastUid = null;
        stableReads = 0;
        if (response != null && response.hasError) {
          if (response.isRetryable) {
            appLogger.d('Poll #$poll: ${response.errorMessage}');
          } else {
            appLogger.w('Poll #$poll: ${response.errorMessage}');
          }
        } else if (response == null) {
          appLogger.d('Poll #$poll: lector no respondió');
        }
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    appLogger.d('Timeout: no se leyó tarjeta en ${limit.inSeconds}s');
    return null;
  }

  /// Indica si el lector HTTP local (`/nfc/m1`) responde.
  static Future<bool> isExternalReaderAvailable() => isNfcServerAvailable();

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
      
      // Si no es el último intento, esperar antes del siguiente
      if (i < maxRetries - 1) {
        await Future.delayed(delayBetweenRetries);
      }
    }
    
    // Devolver el último resultado si todos los intentos fallaron
    return await readM1Card();
  }
  
  /// Verifica si el servidor NFC está disponible
  static Future<bool> isNfcServerAvailable() async {
    try {
      final localIp = await _getLocalIp();
      if (localIp != null) {
        final available = await _checkServerAvailability(localIp);
        if (available) return true;
      }
      
      // Fallback: verificar localhost
      return await _checkServerAvailability('127.0.0.1');
    } catch (e) {
      return false;
    }
  }
  
  /// Verifica disponibilidad del servidor en una IP específica
  static Future<bool> _checkServerAvailability(String ip) async {
    try {
      final response = await _dio.get(
        'http://$ip:${AppConfig.localDeviceApiPort}/nfc/m1',
        options: Options(
          sendTimeout: AppConfig.nfcReadTimeout,
          receiveTimeout: AppConfig.nfcReadTimeout,
        ),
      );
      
      // Si responde (aunque sea con error), el servidor está disponible
      return response.statusCode != null;
    } catch (e) {
      return false;
    }
  }
  
  /// Obtiene información del servidor NFC para debug
  static Future<Map<String, dynamic>> getServerInfo() async {
    try {
      final localIp = await _getLocalIp();
      final isAvailable = await isNfcServerAvailable();
      
      return {
        'localIp': localIp ?? 'unknown',
        'serverPort': AppConfig.localDeviceApiPort,
        'serverUrl': localIp != null ? 'http://$localIp:${AppConfig.localDeviceApiPort}' : 'unknown',
        'isAvailable': isAvailable,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
    }
  }
}
