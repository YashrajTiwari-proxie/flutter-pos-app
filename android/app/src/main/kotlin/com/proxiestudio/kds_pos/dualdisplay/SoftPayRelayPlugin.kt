@file:OptIn(io.softpay.client.meta.DelicateSoftpayApi::class)

package com.proxiestudio.kds_pos.dualdisplay

import android.content.Context
import com.proxiestudio.kds_pos.softpay.SoftPayClientProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.softpay.client.component1
import io.softpay.client.component2
import io.softpay.client.readiness
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Stands in for [com.proxiestudio.kds_pos.softpay.SoftPayPlugin] on the cashier engine when a
 * customer display is attached: implements the identical `.../softpay` method channel and
 * `.../softpay/status` event channel contract that `softpay_service.dart` already speaks, so
 * `EmployeeTerminalScreen` needs no changes either way. `charge`/`cancelCharge` are forwarded
 * through [DisplayBridge] to the real `SoftPayPlugin` running on the customer-display engine,
 * so the SoftPay AppSwitch UI hands off from that screen instead of this one. `readiness` is
 * answered locally since it's a read-only status check with no display hand-off involved, and
 * the underlying Softpay `Client` is a process-wide singleton shared with the customer engine
 * (see the comment on `SoftPayClientProvider.getClient`).
 */
class SoftPayRelayPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL = "com.proxiestudio.kds_pos/softpay"
        private const val EVENT_CHANNEL = "com.proxiestudio.kds_pos/softpay/status"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var appContext: Context

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        DisplayBridge.attachStatusSink(null)
        scope.cancel()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        DisplayBridge.attachStatusSink(events)
    }

    override fun onCancel(arguments: Any?) {
        DisplayBridge.attachStatusSink(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readiness" -> handleReadiness(result)
            "charge" -> handleCharge(call, result)
            "cancelCharge" -> DisplayBridge.cancelCharge(result)
            else -> result.notImplemented()
        }
    }

    private fun handleReadiness(result: MethodChannel.Result) {
        val softpayClient = SoftPayClientProvider.getClient(appContext)
        scope.launch {
            val (readiness, failure) = softpayClient.clientManager.readiness()
            withContext(Dispatchers.Main) {
                if (readiness == null) {
                    result.error("NOT_CONNECTED", failure?.message ?: "Could not connect to a Softpay app on this device", null)
                } else {
                    result.success(
                        mapOf(
                            "ready" to readiness.ready,
                            "authenticated" to readiness.authenticated,
                            "configured" to readiness.configured,
                            "quarantined" to readiness.quarantined,
                            "locked" to readiness.locked,
                        ),
                    )
                }
            }
        }
    }

    private fun handleCharge(call: MethodCall, result: MethodChannel.Result) {
        val amountMinor = (call.argument<Number>("amountMinor"))?.toLong()
        val currency = call.argument<String>("currency")
        if (amountMinor == null || amountMinor <= 0 || currency == null) {
            result.error("INVALID_ARGS", "amountMinor (> 0) and currency are required", null)
            return
        }
        DisplayBridge.startCharge(amountMinor, currency, result)
    }
}
