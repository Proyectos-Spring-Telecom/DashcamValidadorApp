import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';

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

/// Servicio para consumir los endpoints HTTP locales del dispositivo
/// Maneja NFC y Android ID - el GPS se maneja nativamente
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
  /// Retorna null si hay error o no hay tarjeta
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

  /// Obtiene el Android ID del dispositivo
  /// Retorna null si hay error
  Future<String?> getAndroidId() async {
    try {
      final response = await _dio.get('/device/android-id');
      
      if (response.statusCode == 200) {
        final data = AndroidIdResponse.fromJson(response.data);
        appLogger.d('Android ID obtenido exitosamente');
        return data.androidId;
      }
      appLogger.w('Respuesta inesperada al obtener Android ID: ${response.statusCode}');
      return null;
    } on DioException catch (e) {
      appLogger.w('Error al obtener Android ID: ${e.message}');
      return null;
    } catch (e) {
      appLogger.e('Error inesperado al obtener Android ID', e);
      return null;
    }
  }

  /// Obtiene el número de serie del validador del endpoint local
  /// Retorna null si hay error
  Future<String?> getValidadorSerie() async {
    try {
      final response = await _dio.get('/device/validador-serie');
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final serie = data['numeroSerieValidador'] as String? ?? data['serie'] as String?;
        if (serie != null && serie.isNotEmpty) {
          appLogger.d('Número de serie del validador obtenido exitosamente: $serie');
          return serie;
        }
      }
      appLogger.w('Respuesta inesperada al obtener número de serie del validador: ${response.statusCode}');
      return null;
    } on DioException catch (e) {
      appLogger.w('Error al obtener número de serie del validador: ${e.message}');
      // Fallback: intentar obtener Android ID como validador serie
      return await getAndroidId();
    } catch (e) {
      appLogger.e('Error inesperado al obtener número de serie del validador', e);
      // Fallback: intentar obtener Android ID como validador serie
      return await getAndroidId();
    }
  }
}

/// Instancia global del servicio
final deviceApiService = DeviceApiService();
