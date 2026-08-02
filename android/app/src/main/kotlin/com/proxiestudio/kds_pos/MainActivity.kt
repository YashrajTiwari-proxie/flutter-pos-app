package com.proxiestudio.kds_pos

import com.proxiestudio.kds_pos.dualdisplay.DisplayBridgePlugin
import com.proxiestudio.kds_pos.dualdisplay.DisplayBridgeRole
import com.proxiestudio.kds_pos.dualdisplay.DualDisplayLauncher
import com.proxiestudio.kds_pos.dualdisplay.SoftPayRelayPlugin
import com.proxiestudio.kds_pos.softpay.SoftPayPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // On a Sunmi D3 mini (or any device with a presentation-capable secondary display
        // attached), the charge flow runs on the customer-facing screen instead:
        // SoftPayRelayPlugin speaks the same `.../softpay` channel contract as SoftPayPlugin,
        // but forwards to it. With no secondary display, this falls back to exactly today's
        // single-screen behaviour. Only a cheap, side-effect-free display query happens here -
        // actually showing the customer-display Presentation is deferred to onPostResume (see
        // DualDisplayLauncher).
        if (DualDisplayLauncher.hasPresentationDisplay(this)) {
            flutterEngine.plugins.add(SoftPayRelayPlugin())
            flutterEngine.plugins.add(DisplayBridgePlugin(DisplayBridgeRole.MAIN))
        } else {
            flutterEngine.plugins.add(SoftPayPlugin())
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        DualDisplayLauncher.showIfAvailable(this)
    }
}
