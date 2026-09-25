import 'package:dio/dio.dart';
import '../config/app_config.dart';
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

/// API local del dispositivo (solo loopback HTTP) + fallback nativo.
class DeviceApiService {
  late final Dio _dio;

  DeviceApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.localDeviceApiUrl,
        connectTimeout: AppConfig.localDeviceTimeout,
        receiveTimeout: AppConfig.localDeviceTimeout,
      ),
    );
  }

  /// Lee una tarjeta NFC M1
  Future<NfcM1Response?> readNfcM1() async {
    try {
      final response = await _dio.get('/nfc/m1');

      if (response.statusCode == 200) {
        appLogger.d('NFC M1 leído exitosamente');
        return NfcM1Response.fromJson(response.data);
      }
      appLogger.w('Respuesta inesperada al leer NFC M1: ${response.statusCode}');
      return null;
    } on DioException catch (e) {
      appLogger.w('Error al leer NFC M1: ${e.message}');
      return null;
    } catch (e) {
      appLogger.e('Error inesperado al leer NFC M1', e);
      return null;
    }
  }

  /// Obtiene el Android ID (API local o nativo)
  Future<String?> getAndroidId() async {
    try {
      final response = await _dio.get('/device/android-id');

      if (response.statusCode == 200) {
        final data = AndroidIdResponse.fromJson(response.data);
        appLogger.d('Android ID obtenido del API local');
        return data.androidId;
      }
    } on DioException catch (e) {
      appLogger.w('API local android-id no disponible: ${e.message}');
    } catch (e) {
      appLogger.e('Error inesperado al obtener Android ID local', e);
    }
    return DeviceService.getDeviceId();
  }

  /// Obtiene el número de serie del validador (API local o Android ID).
  Future<String?> getValidadorSerie() async {
    try {
      final response = await _dio.get('/device/validador-serie');

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final serie =
            data['numeroSerieValidador'] as String? ?? data['serie'] as String?;
        if (serie != null && serie.isNotEmpty) {
          appLogger.d('Serie validador (API local): $serie');
          return serie;
        }
      }
    } on DioException catch (e) {
      appLogger.w('API local validador-serie no disponible: ${e.message}');
    } catch (e) {
      appLogger.e('Error inesperado al obtener serie del validador', e);
    }
    return getAndroidId();
  }
}

/// Instancia global del servicio
final deviceApiService = DeviceApiService();
