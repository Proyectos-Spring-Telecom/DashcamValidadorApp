import '../utils/logger.dart';
import 'device_service.dart';

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
      result: json['result'] as int,
      cardUid: json['cardUid'] as String?,
    );
  }

  bool get isSuccess => result == 0;
}

/// Modelo para la respuesta de Android ID
class AndroidIdResponse {
  final String androidId;

  AndroidIdResponse({required this.androidId});

  factory AndroidIdResponse.fromJson(Map<String, dynamic> json) {
    return AndroidIdResponse(
      androidId: json['androidId'] as String,
    );
  }
}

/// Identidad del dispositivo vía APIs nativas (sin HTTP en claro).
class DeviceApiService {
  /// Obtiene el Android ID del dispositivo
  Future<String?> getAndroidId() async {
    try {
      final id = await DeviceService.getDeviceId();
      if (id.isNotEmpty && !id.startsWith('error_')) {
        appLogger.d('Android ID obtenido exitosamente');
        return id;
      }
      return null;
    } catch (e) {
      appLogger.e('Error inesperado al obtener Android ID', e);
      return null;
    }
  }

  /// Obtiene el número de serie del validador (Android ID nativo).
  Future<String?> getValidadorSerie() async {
    return getAndroidId();
  }
}

/// Instancia global del servicio
final deviceApiService = DeviceApiService();
