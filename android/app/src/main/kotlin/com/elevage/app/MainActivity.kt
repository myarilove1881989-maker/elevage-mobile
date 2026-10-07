package com.elevage.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper

class MainActivity : FlutterActivity() {
    private var connectivity: ConnectivityManager? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private fun stopNetworkObserver() {
        callback?.let { connectivity?.unregisterNetworkCallback(it) }
        callback = null
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val identity = DeviceIdentity(applicationContext)
        connectivity = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "elevage/network_state")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    stopNetworkObserver()
                    val observer = object : ConnectivityManager.NetworkCallback() {
                        private fun emit(available: Boolean) {
                            mainHandler.post { if (callback === this) events.success(available) }
                        }
                        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                            emit(caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED))
                        }
                        override fun onLost(network: Network) { emit(false) }
                    }
                    callback = observer
                    connectivity!!.registerDefaultNetworkCallback(observer)
                    val caps = connectivity!!.getNetworkCapabilities(connectivity!!.activeNetwork)
                    events.success(caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                        caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED))
                }
                override fun onCancel(arguments: Any?) { stopNetworkObserver() }
            })
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

    override fun onDestroy() {
        stopNetworkObserver()
        super.onDestroy()
    }
}
