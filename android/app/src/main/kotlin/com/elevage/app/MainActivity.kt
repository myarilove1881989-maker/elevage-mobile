package com.elevage.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val identity = DeviceIdentity(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "elevage/device_identity")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "identity" -> result.success(identity.identity())
                        "sign" -> {
                            val bytes = call.argument<ByteArray>("message")
                                ?: throw IllegalArgumentException("DEVICE_MESSAGE_REQUIRED")
                            result.success(identity.sign(bytes))
                        }
                        else -> result.notImplemented()
                    }
                } catch (exception: Exception) {
                    // No message bytes, credentials or underlying exception in logs.
                    result.error("DEVICE_SECURITY_UNAVAILABLE", "Identité de tablette indisponible.", null)
                }
            }
    }
}
