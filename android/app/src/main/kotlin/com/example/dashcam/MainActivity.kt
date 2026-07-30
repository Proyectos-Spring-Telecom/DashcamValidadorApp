package com.example.dashcam

import android.content.Context
import android.hardware.camera2.CameraManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.dashcam/device",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasCamera" -> result.success(deviceHasWorkingCamera())
                "getAndroidId" -> result.success(
                    Settings.Secure.getString(
                        contentResolver,
                        Settings.Secure.ANDROID_ID,
                    ),
                )
                else -> result.notImplemented()
            }
        }
    }

    /** Comprueba que exista al menos una cámara accesible (no solo declarada en el manifest). */
    private fun deviceHasWorkingCamera(): Boolean {
        return try {
            val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val ids = manager.cameraIdList
            if (ids.isEmpty()) return false
            for (id in ids) {
                try {
                    manager.getCameraCharacteristics(id)
                    return true
                } catch (_: Exception) {
                    // Probar siguiente id
                }
            }
            false
        } catch (_: Exception) {
            false
        }
    }
}
