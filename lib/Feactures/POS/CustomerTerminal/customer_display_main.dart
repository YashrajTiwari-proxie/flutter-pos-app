import 'package:flutter/material.dart';

import 'customer_app.dart';

/// Dart entrypoint for the customer-display engine (see
/// `android/app/.../dualdisplay/CustomerDisplayActivity.kt`). Deliberately does not initialize
/// the Convex client - this screen only ever displays data relayed over the native
/// `DisplayBridge`, it never queries the backend directly.
@pragma('vm:entry-point')
Future<void> customerDisplayMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  // In release builds, a widget that throws during build is normally replaced by a plain grey
  // box with no text - which reads as "background renders but nothing else does" on a screen
  // nobody can attach a debugger to. Show the real error here instead, and log it so `adb
  // logcat` (filtered for the `flutter` tag) catches it even without looking at the panel.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint(
      'CustomerDisplay error: ${details.exceptionAsString()}\n${details.stack}',
    );
  };
  ErrorWidget.builder = (details) => Container(
    color: Colors.red,
    alignment: Alignment.center,
    padding: const EdgeInsets.all(16),
    child: Text(
      'Customer display error:\n${details.exceptionAsString()}',
      style: const TextStyle(color: Colors.white, fontSize: 14),
      textAlign: TextAlign.center,
    ),
  );

  // This engine has its own ThemeController instance (separate isolate from the cashier
  // engine's) and deliberately never talks to Convex, so it can't fetch the restaurant's
  // web-configured appearance itself - it just uses ThemeController's defaults. Syncing it
  // would mean relaying the appearance over the same native DisplayBridge that already
  // relays cart data; not done here.
  runApp(const CustomerDisplayApp());
}
