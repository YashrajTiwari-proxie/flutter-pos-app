@file:OptIn(io.softpay.client.meta.DelicateSoftpayApi::class)

package com.proxiestudio.kds_pos.softpay

import com.proxiestudio.kds_pos.dualdisplay.DisplayBridge
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.softpay.client.Client
import io.softpay.client.Failure
import io.softpay.client.FailureException
import io.softpay.client.Manager
import io.softpay.client.Request
import io.softpay.client.component1
import io.softpay.client.component2
import io.softpay.client.domain.Transaction
import io.softpay.client.domain.amountOf
import io.softpay.client.readiness
import io.softpay.client.transaction.PaymentTransaction
import io.softpay.client.transaction.RefundTransaction
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Bridges the Flutter Employee Terminal *and* customer-display screens to the SoftPay AppSwitch
 * SDK - one instance is attached to each engine (see `MainActivity` and
 * `CustomerDisplayPresentation`), both talking to the same process-wide [SoftPayClientProvider]
 * client.
 *
 * On the cashier (main) engine ([allowRelay] = true, the default), `charge`/`cancelCharge`
 * decide *per call* whether to relay through [DisplayBridge] to the customer-display engine (so
 * the AppSwitch hand-off lands there) or process directly here - checked live via
 * [DisplayBridge.isCustomerAttached], not decided once at engine-configuration time. That
 * distinction matters: a presentation-capable secondary display can take a moment (or, per
 * Sunmi's `DisplayManager` behaviour, flicker) after the engine is first configured, so a
 * one-time decision at startup can go stale and lock in the wrong mode for the rest of the
 * session, throwing "customer display not attached" errors even once the display genuinely
 * isn't in relay mode.
 *
 * On the customer-display engine, [allowRelay] must be false: that engine is what
 * `DisplayBridge.isCustomerAttached()` reports as attached, so without this it would see itself
 * as "a customer display is attached" and try to relay a charge to itself.
 *
 * `refund` is always handled directly, on whichever engine calls it - it's a back-office action,
 * not part of the customer-facing checkout hand-off, so it never relays.
 */
class SoftPayPlugin(private val allowRelay: Boolean = true) :
    FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL = "com.proxiestudio.kds_pos/softpay"
        private const val EVENT_CHANNEL = "com.proxiestudio.kds_pos/softpay/status"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var currentJob: Job? = null
    private var client: Client? = null

    // Whether the in-flight charge was relayed to the customer-display engine, so
    // cancelCharge routes to the same place even if attachment state changes mid-charge.
    @Volatile private var chargeIsRelayed = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)

        client = SoftPayClientProvider.getClient(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        if (allowRelay) DisplayBridge.attachStatusSink(null)
        currentJob?.cancel()
        scope.cancel()
    }

    // Only the main engine's instance (allowRelay) wires its status sink into DisplayBridge, so
    // DisplayBridge.reportStatus - fed by the customer engine's own explicit
    // CustomerDisplayBridge.reportStatus() call - reaches the cashier screen's status stream.
    // The customer engine's own instance must NOT touch DisplayBridge's (process-wide, shared)
    // status sink here, or its listen/cancel cycle would stomp on the main engine's registration.
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        if (allowRelay) DisplayBridge.attachStatusSink(events)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        if (allowRelay) DisplayBridge.attachStatusSink(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readiness" -> handleReadiness(result)
            "charge" -> handleCharge(call, result)
            "refund" -> handleRefund(call, result)
            "cancelCharge" -> handleCancelCharge(result)
            else -> result.notImplemented()
        }
    }

    private fun handleReadiness(result: MethodChannel.Result) {
        val softpayClient = client
        if (softpayClient == null) {
            result.error("NO_CLIENT", "Softpay client not initialised", null)
            return
        }
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

        if (allowRelay && DisplayBridge.isCustomerAttached()) {
            chargeIsRelayed = true
            DisplayBridge.startCharge(amountMinor, currency, result)
            return
        }
        chargeIsRelayed = false

        val softpayClient = client
        if (softpayClient == null) {
            result.error("NO_CLIENT", "Softpay client not initialised", null)
            return
        }
        if (currentJob?.isActive == true) {
            result.error("BUSY", "A charge is already in progress", null)
            return
        }

        val amount = amountOf(amountMinor, currency)

        currentJob = scope.launch {
            emitStatus(stage = "connecting", detail = null)
            try {
                val transaction = requestPayment(softpayClient, amount)
                emitStatus(stage = "approved", detail = null)
                withContext(Dispatchers.Main) { result.success(transactionToMap(transaction)) }
            } catch (e: CancellationException) {
                emitStatus(stage = "cancelled", detail = null)
                withContext(Dispatchers.Main) { result.error("CANCELLED", "Charge was cancelled", null) }
            } catch (e: FailureException) {
                emitStatus(stage = "declined", detail = e.failure.failureMessage ?: e.failure.message)
                withContext(Dispatchers.Main) {
                    result.error(
                        e.failure.code.toString(),
                        e.failure.failureMessage ?: e.failure.message,
                        mapOf("detailedCode" to e.failure.detailedCode),
                    )
                }
            }
        }
    }

    // Bridges the callback-based PaymentTransaction action to a single suspend call, while
    // still streaming coarse `onProcessing` updates out over the event channel.
    private suspend fun requestPayment(client: Client, amount: io.softpay.client.domain.Amount): Transaction =
        suspendCancellableCoroutine { continuation ->
            val payment = object : PaymentTransaction {
                override val amount = amount
                override val processingUpdates = true

                override fun onProcessing(request: Request, update: String) {
                    emitStatus(stage = "processing", detail = update)
                }

                override fun onSuccess(request: Request, result: Transaction) {
                    if (continuation.isActive) continuation.resume(result)
                }

                override fun onFailure(manager: Manager<*>, request: Request?, failure: Failure) {
                    if (continuation.isActive) continuation.resumeWithException(failure.asFailureException(request))
                }
            }

            client.transactionManager.requestFor(payment) { request ->
                continuation.invokeOnCancellation {
                    request.abort(detailedCode = 0, reason = "pos_app_cancelled", quick = true) { _, _, _, _ -> }
                }
                request.process()
            }
        }

    // A refund is its own Transaction (Privileges.REFUND / REFUND_LATE_AMOUNT on the Softpay
    // merchant account) that always requires a card tap - the SDK does not offer a "linked"
    // refund by request id. `posReferenceNumber` is passed through only so the refund receipt
    // can be reconciled against the original order on our side.
    private fun handleRefund(call: MethodCall, result: MethodChannel.Result) {
        val softpayClient = client
        if (softpayClient == null) {
            result.error("NO_CLIENT", "Softpay client not initialised", null)
            return
        }
        if (currentJob?.isActive == true) {
            result.error("BUSY", "A charge or refund is already in progress", null)
            return
        }

        val amountMinor = (call.argument<Number>("amountMinor"))?.toLong()
        val currency = call.argument<String>("currency")
        val posReferenceNumber = call.argument<String>("posReferenceNumber")
        if (amountMinor == null || amountMinor <= 0 || currency == null) {
            result.error("INVALID_ARGS", "amountMinor (> 0) and currency are required", null)
            return
        }

        val amount = amountOf(amountMinor, currency)

        currentJob = scope.launch {
            emitStatus(stage = "connecting", detail = null)
            try {
                val transaction = requestRefund(softpayClient, amount, posReferenceNumber)
                emitStatus(stage = "approved", detail = null)
                withContext(Dispatchers.Main) { result.success(transactionToMap(transaction)) }
            } catch (e: CancellationException) {
                emitStatus(stage = "cancelled", detail = null)
                withContext(Dispatchers.Main) { result.error("CANCELLED", "Refund was cancelled", null) }
            } catch (e: FailureException) {
                emitStatus(stage = "declined", detail = e.failure.failureMessage ?: e.failure.message)
                withContext(Dispatchers.Main) {
                    result.error(
                        e.failure.code.toString(),
                        e.failure.failureMessage ?: e.failure.message,
                        mapOf("detailedCode" to e.failure.detailedCode),
                    )
                }
            }
        }
    }

    private suspend fun requestRefund(
        client: Client,
        amount: io.softpay.client.domain.Amount,
        posReferenceNumber: String?,
    ): Transaction =
        suspendCancellableCoroutine { continuation ->
            val refund = object : RefundTransaction {
                override val amount = amount
                override val posReferenceNumber = posReferenceNumber
                override val processingUpdates = true

                override fun onProcessing(request: Request, update: String) {
                    emitStatus(stage = "processing", detail = update)
                }

                override fun onSuccess(request: Request, result: Transaction) {
                    if (continuation.isActive) continuation.resume(result)
                }

                override fun onFailure(manager: Manager<*>, request: Request?, failure: Failure) {
                    if (continuation.isActive) continuation.resumeWithException(failure.asFailureException(request))
                }
            }

            client.transactionManager.requestFor(refund) { request ->
                continuation.invokeOnCancellation {
                    request.abort(detailedCode = 0, reason = "pos_app_cancelled", quick = true) { _, _, _, _ -> }
                }
                request.process()
            }
        }

    private fun handleCancelCharge(result: MethodChannel.Result) {
        if (chargeIsRelayed) {
            DisplayBridge.cancelCharge(result)
            return
        }
        val job = currentJob
        if (job == null || !job.isActive) {
            result.success(false)
            return
        }
        job.cancel()
        result.success(true)
    }

    private fun emitStatus(stage: String, detail: String?) {
        scope.launch(Dispatchers.Main) {
            eventSink?.success(mapOf("stage" to stage, "detail" to detail))
        }
    }

    private fun transactionToMap(transaction: Transaction): Map<String, Any?> =
        mapOf(
            "requestId" to transaction.requestId?.toString(),
            "amountMinor" to transaction.amount.minor,
            "currency" to transaction.amount.currency.toString(),
            "state" to transaction.state.toString(),
            "cardScheme" to transaction.scheme?.toString(),
            "partialPan" to transaction.partialPan,
            "auditNumber" to transaction.auditNumber?.toString(),
            "type" to transaction.type.name,
            "cvm" to transaction.cvm?.name,
            "terminalId" to transaction.terminalId,
            "batchNumber" to transaction.batchNumber,
            "tipMinor" to transaction.tip?.amount?.minor,
            "surchargeMinor" to transaction.surcharge,
            "transactionDate" to transaction.date,
        )
}
