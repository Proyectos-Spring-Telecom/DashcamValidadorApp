import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/logger.dart';

/// Servicio para obtener información única del dispositivo.
/// Usa Android ID nativo (sin HTTP en claro).
class DeviceService {
  static const _storage = FlutterSecureStorage();
  static const String _keyDeviceId = 'device_id';
  static const _channel = MethodChannel('com.example.dashcam/device');

  /// Obtiene un ID único del dispositivo vía Settings.Secure.ANDROID_ID.
  /// Si no puede obtenerlo nativamente, usa un ID persistente almacenado.
  static Future<String> getDeviceId() async {
    try {
      final nativeId = await _getNativeAndroidId();
      if (nativeId != null && nativeId.isNotEmpty) {
        await _storage.write(key: _keyDeviceId, value: nativeId);
        appLogger.i('Device ID obtenido nativamente: $nativeId');
        return nativeId;
      }

      final storedId = await _storage.read(key: _keyDeviceId);
      if (storedId != null && storedId.isNotEmpty) {
        appLogger.w('Usando Device ID almacenado: $storedId');
        return storedId;
      }

      final fallbackId = 'device_${DateTime.now().millisecondsSinceEpoch}';
      await _storage.write(key: _keyDeviceId, value: fallbackId);
      appLogger.w('Generando Device ID de fallback: $fallbackId');
      return fallbackId;
    } catch (e) {
      appLogger.e('Error al obtener Device ID', e);
      try {
        final storedId = await _storage.read(key: _keyDeviceId);
        if (storedId != null && storedId.isNotEmpty) {
          return storedId;
        }
      } catch (_) {}
      return 'error_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  static Future<String?> _getNativeAndroidId() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final id = await _channel.invokeMethod<String>('getAndroidId');
      if (id != null && id.isNotEmpty) return id;
    } catch (e) {
      appLogger.w('No se pudo leer Android ID nativo: $e');
    }
    return null;
  }

  /// Obtiene información detallada del dispositivo para logging/debug
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final androidId = await getDeviceId();

      return {
        'platform': defaultTargetPlatform.name,
        'androidId': androidId,
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
