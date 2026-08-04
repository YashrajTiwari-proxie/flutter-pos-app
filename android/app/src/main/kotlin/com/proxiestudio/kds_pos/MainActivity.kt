package com.proxiestudio.kds_pos

import com.proxiestudio.kds_pos.dualdisplay.DisplayBridgePlugin
import com.proxiestudio.kds_pos.dualdisplay.DisplayBridgeRole
import com.proxiestudio.kds_pos.softpay.SoftPayPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // SoftPayPlugin always runs on this (cashier) engine and decides, per charge attempt,
        // whether to relay through DisplayBridge to the customer-display engine - see its class
        // doc for why that can't be decided once here at engine-configuration time.
        flutterEngine.plugins.add(SoftPayPlugin())
        // Also exposes activateSecondaryDisplay - see DualDisplayLauncher's class doc for why
        // this is triggered manually (a button in the Flutter UI) rather than automatically.
        flutterEngine.plugins.add(DisplayBridgePlugin(DisplayBridgeRole.MAIN))

        // Receipt printing is handled entirely by the sunmi_flutter_plugin_printer Dart package
        // (see printer_service.dart), which auto-registers itself via the super call above - no
        // manual plugin wiring needed here.
    }
}
