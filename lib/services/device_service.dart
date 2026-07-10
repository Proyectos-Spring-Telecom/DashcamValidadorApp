import 'package:dio/dio.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';

/// Servicio para obtener información única del dispositivo usando el servidor HTTP local
class DeviceService {
  static final Dio _dio = Dio();
  static const _storage = FlutterSecureStorage();
  static const String _keyDeviceId = 'device_id';
  
  /// Obtiene la IP local del dispositivo
  static Future<String?> _getLocalIp() async {
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (e) {
      return null;
    }
  }
  
  /// Obtiene un ID único del dispositivo usando el servidor HTTP local
  /// Si no puede obtenerlo del servidor, usa un ID persistente almacenado
  static Future<String> getDeviceId() async {
    try {
      // Intentar obtener Android ID del servidor local
      final localIp = await _getLocalIp();
      if (localIp != null) {
        final androidId = await _getAndroidIdFromServer(localIp);
        if (androidId != null && androidId.isNotEmpty) {
          // Guardar el ID obtenido para uso futuro
          await _storage.write(key: _keyDeviceId, value: androidId);
          appLogger.i('Device ID obtenido del servidor: $androidId');
          return androidId;
        }
      }

      // Fallback: intentar con localhost
      final androidIdLocal = await _getAndroidIdFromServer('127.0.0.1');
      if (androidIdLocal != null && androidIdLocal.isNotEmpty) {
        await _storage.write(key: _keyDeviceId, value: androidIdLocal);
        appLogger.i('Device ID obtenido de localhost: $androidIdLocal');
        return androidIdLocal;
      }

      // Fallback: intentar recuperar ID guardado previamente
      final storedId = await _storage.read(key: _keyDeviceId);
      if (storedId != null && storedId.isNotEmpty) {
        appLogger.w('Usando Device ID almacenado: $storedId');
        return storedId;
      }

      // Fallback final: generar y guardar un ID único persistente
      final fallbackId = 'device_${DateTime.now().millisecondsSinceEpoch}';
      await _storage.write(key: _keyDeviceId, value: fallbackId);
      appLogger.w('Generando Device ID de fallback: $fallbackId');
      return fallbackId;
    } catch (e) {
      appLogger.e('Error al obtener Device ID', e);
      // Último recurso: intentar recuperar ID guardado
      try {
        final storedId = await _storage.read(key: _keyDeviceId);
        if (storedId != null && storedId.isNotEmpty) {
          return storedId;
        }
      } catch (_) {
        // Ignorar error al leer almacenamiento
      }
      // Generar ID temporal como último recurso
      return 'error_${DateTime.now().millisecondsSinceEpoch}';
    }
  }
  
  /// Obtiene el Android ID del servidor HTTP local
  static Future<String?> _getAndroidIdFromServer(String ip) async {
    try {
      final response = await _dio.get(
        'http://$ip:${AppConfig.localDeviceApiPort}/device/android-id',
        options: Options(
          sendTimeout: AppConfig.localDeviceTimeout,
          receiveTimeout: AppConfig.localDeviceTimeout,
        ),
      );
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        return data['androidId'] as String?;
      }
    } catch (e) {
      // Error al conectar con el servidor local
      return null;
    }
    return null;
  }
  
  /// Obtiene información detallada del dispositivo para logging/debug
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final localIp = await _getLocalIp();
      final androidId = await getDeviceId();
      
      return {
        'platform': 'android',
        'localIp': localIp ?? 'unknown',
        'androidId': androidId,
        'serverPort': AppConfig.localDeviceApiPort,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
    } catch (e) {
      return {
        'platform': 'error',
        'error': e.toString(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
    }
  }
}
