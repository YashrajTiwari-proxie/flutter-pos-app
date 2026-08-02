package com.proxiestudio.kds_pos.dualdisplay

import android.app.Presentation
import android.content.Context
import android.os.Bundle
import android.view.Display
import com.proxiestudio.kds_pos.softpay.SoftPayPlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Hosts the customer-facing order display + SoftPay charge flow on the Sunmi D3 mini's
 * secondary screen via Android's [Presentation] API - the officially sanctioned way to show
 * content on a secondary/presentation display. A plain `startActivity(..., ActivityOptions
 * .setLaunchDisplayId(...))` (the previous approach) requires cross-display activity-launch
 * permissions that OEMs commonly withhold for a private customer-facing panel, and crashed on
 * the real device; `Presentation` doesn't need that permission - it's designed for exactly
 * this case, and is what Sunmi's own docs point at too.
 *
 * Runs its own [FlutterEngine] on a separate Dart entrypoint (`customerDisplayMain`),
 * independent from the cashier engine hosted by `MainActivity`, rendered via a raw
 * [FlutterView] attached directly to that engine - no Activity involved on this side at all.
 */
class CustomerDisplayPresentation(outerContext: Context, display: Display) : Presentation(outerContext, display) {

    private var engine: FlutterEngine? = null
    private var flutterView: FlutterView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) {
            loader.startInitialization(context.applicationContext)
        }
        loader.ensureInitializationComplete(context.applicationContext, null)

        val engine = FlutterEngine(context)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "package:kds_pos/Feactures/POS/CustomerTerminal/customer_display_main.dart",
                "customerDisplayMain",
            ),
        )
        engine.plugins.add(SoftPayPlugin())
        engine.plugins.add(DisplayBridgePlugin(DisplayBridgeRole.CUSTOMER))
        engine.lifecycleChannel.appIsResumed()
        this.engine = engine

        val view = FlutterView(context, RenderMode.texture)
        view.attachToFlutterEngine(engine)
        flutterView = view
        setContentView(view)
    }

    override fun onDisplayRemoved() {
        dismiss()
    }

    override fun dismiss() {
        engine?.lifecycleChannel?.appIsDetached()
        flutterView?.detachFromFlutterEngine()
        engine?.destroy()
        engine = null
        flutterView = null
        super.dismiss()
    }
}
