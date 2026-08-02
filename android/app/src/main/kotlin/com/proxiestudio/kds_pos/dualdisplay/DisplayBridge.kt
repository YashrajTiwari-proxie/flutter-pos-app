package com.proxiestudio.kds_pos.dualdisplay

import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Process-wide relay between the main-screen engine and the customer-display engine.
 * Both engines run in the same Android process and dispatch platform-channel calls on the
 * main thread, so plain `@Volatile` fields are enough here - there's no real concurrency
 * hazard to lock against, just cross-engine bookkeeping.
 */
object DisplayBridge {

    @Volatile private var latestCart: Map<String, Any?>? = null

    private var customerSink: EventChannel.EventSink? = null
    private var statusSink: EventChannel.EventSink? = null
    private var pendingChargeResult: MethodChannel.Result? = null

    // ---- sink lifecycle (called from each side's EventChannel.StreamHandler) ----

    fun attachCustomerSink(sink: EventChannel.EventSink?) {
        customerSink = sink
        if (sink != null) {
            latestCart?.let { sink.success(mapOf("type" to "cart", "cart" to it)) }
        }
    }

    fun attachStatusSink(sink: EventChannel.EventSink?) {
        statusSink = sink
    }

    fun isCustomerAttached(): Boolean = customerSink != null

    // ---- main engine -> here -> customer engine ----

    fun pushCart(cart: Map<String, Any?>) {
        latestCart = cart
        customerSink?.success(mapOf("type" to "cart", "cart" to cart))
    }

    fun startCharge(amountMinor: Long, currency: String, result: MethodChannel.Result) {
        if (customerSink == null) {
            result.error("NO_CUSTOMER_DISPLAY", "Customer display is not attached", null)
            return
        }
        if (pendingChargeResult != null) {
            result.error("BUSY", "A charge is already in progress", null)
            return
        }
        pendingChargeResult = result
        customerSink?.success(mapOf("type" to "startCharge", "amountMinor" to amountMinor, "currency" to currency))
    }

    fun cancelCharge(result: MethodChannel.Result) {
        if (customerSink == null || pendingChargeResult == null) {
            result.success(false)
            return
        }
        customerSink?.success(mapOf("type" to "cancelCharge"))
        result.success(true)
    }

    // ---- customer engine -> here -> main engine ----

    fun reportStatus(stage: String, detail: String?) {
        statusSink?.success(mapOf("stage" to stage, "detail" to detail))
    }

    fun reportResult(transaction: Map<String, Any?>) {
        pendingChargeResult?.success(transaction)
        pendingChargeResult = null
    }

    fun reportError(code: String, message: String?, detailedCode: Int?) {
        pendingChargeResult?.error(code, message, mapOf("detailedCode" to detailedCode))
        pendingChargeResult = null
    }
}
