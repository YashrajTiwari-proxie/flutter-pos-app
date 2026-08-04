package com.proxiestudio.kds_pos.dualdisplay

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

enum class DisplayBridgeRole { MAIN, CUSTOMER }

/**
 * Thin per-engine adapter over [DisplayBridge]. `MAIN` runs on the cashier engine and pushes
 * cart snapshots down to the customer engine, plus exposes a manual `activateSecondaryDisplay`
 * trigger (see [DualDisplayLauncher]). `CUSTOMER` runs on the customer-display engine: it
 * receives cart/charge/cancel events from the cashier side and reports payment status/results
 * back up.
 */
class DisplayBridgePlugin(private val role: DisplayBridgeRole) :
    FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private lateinit var appContext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        when (role) {
            DisplayBridgeRole.MAIN -> {
                methodChannel = MethodChannel(binding.binaryMessenger, "com.proxiestudio.kds_pos/orderdisplay")
                methodChannel?.setMethodCallHandler(this)
            }
            DisplayBridgeRole.CUSTOMER -> {
                methodChannel = MethodChannel(binding.binaryMessenger, "com.proxiestudio.kds_pos/bridge/customer")
                methodChannel?.setMethodCallHandler(this)

                eventChannel = EventChannel(binding.binaryMessenger, "com.proxiestudio.kds_pos/bridge/customer/events")
                eventChannel?.setStreamHandler(this)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        if (role == DisplayBridgeRole.CUSTOMER) {
            DisplayBridge.attachCustomerSink(null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (role == DisplayBridgeRole.CUSTOMER) {
            DisplayBridge.attachCustomerSink(events)
        }
    }

    override fun onCancel(arguments: Any?) {
        if (role == DisplayBridgeRole.CUSTOMER) {
            DisplayBridge.attachCustomerSink(null)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (role) {
            DisplayBridgeRole.MAIN -> handleMainCall(call, result)
            DisplayBridgeRole.CUSTOMER -> handleCustomerCall(call, result)
        }
    }

    private fun handleMainCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pushCart" -> {
                @Suppress("UNCHECKED_CAST")
                val cart = call.arguments as? Map<String, Any?> ?: emptyMap()
                DisplayBridge.pushCart(cart)
                result.success(null)
            }
            "activateSecondaryDisplay" -> {
                result.success(DualDisplayLauncher.activate(appContext))
            }
            else -> result.notImplemented()
        }
    }

    private fun handleCustomerCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "reportStatus" -> {
                DisplayBridge.reportStatus(call.argument<String>("stage") ?: "processing", call.argument<String>("detail"))
                result.success(null)
            }
            "reportResult" -> {
                @Suppress("UNCHECKED_CAST")
                val transaction = call.arguments as? Map<String, Any?> ?: emptyMap()
                DisplayBridge.reportResult(transaction)
                result.success(null)
            }
            "reportError" -> {
                val code = call.argument<String>("code") ?: "UNKNOWN"
                val message = call.argument<String>("message")
                val detailedCode = call.argument<Number>("detailedCode")?.toInt()
                DisplayBridge.reportError(code, message, detailedCode)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
