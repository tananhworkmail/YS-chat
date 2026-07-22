package com.tythac.ys_mobile

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.tythac.ys_mobile/device",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isEmulator" -> result.success(isAndroidEmulator())
                else -> result.notImplemented()
            }
        }
    }

    private fun isAndroidEmulator(): Boolean {
        val fingerprint = Build.FINGERPRINT.lowercase()
        val manufacturer = Build.MANUFACTURER.lowercase()
        val model = Build.MODEL.lowercase()
        val brand = Build.BRAND.lowercase()
        val device = Build.DEVICE.lowercase()
        val product = Build.PRODUCT.lowercase()
        val hardware = Build.HARDWARE.lowercase()

        return fingerprint.startsWith("generic") ||
            fingerprint.contains("vbox") ||
            fingerprint.contains("test-keys") ||
            manufacturer.contains("genymotion") ||
            manufacturer.contains("xuanzhi") ||
            manufacturer.contains("ldplayer") ||
            model.contains("emulator") ||
            model.contains("android sdk built for") ||
            model.contains("ldplayer") ||
            (brand.startsWith("generic") && device.startsWith("generic")) ||
            product.contains("sdk") ||
            product.contains("vbox") ||
            product.contains("ldplayer") ||
            hardware.contains("goldfish") ||
            hardware.contains("ranchu") ||
            hardware.contains("vbox")
    }
}
