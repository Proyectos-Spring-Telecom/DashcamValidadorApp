import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Capacidades de hardware del dispositivo (consulta nativa en Android).
class DeviceCapabilities {
  static const _channel = MethodChannel('com.example.dashcam/device');

  /// Indica si el dispositivo tiene alguna cámara usable.
  /// En Android consulta [PackageManager.FEATURE_CAMERA_ANY].
  static Future<bool> hasCamera() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final has = await _channel.invokeMethod<bool>('hasCamera');
        return has ?? false;
      } catch (_) {
        return false;
      }
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return true;
    }
    return false;
  }
}
