import 'package:flutter/material.dart';

import 'customer_app.dart';

/// Dart entrypoint for the customer-display engine (see
/// `android/app/.../dualdisplay/CustomerDisplayActivity.kt`). Deliberately does not initialize
/// the Convex client - this screen only ever displays data relayed over the native
/// `DisplayBridge`, it never queries the backend directly.
@pragma('vm:entry-point')
void customerDisplayMain() {
  WidgetsFlutterBinding.ensureInitialized();

  // In release builds, a widget that throws during build is normally replaced by a plain grey
  // box with no text - which reads as "background renders but nothing else does" on a screen
  // nobody can attach a debugger to. Show the real error here instead, and log it so `adb
  // logcat` (filtered for the `flutter` tag) catches it even without looking at the panel.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('CustomerDisplay error: ${details.exceptionAsString()}\n${details.stack}');
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

  runApp(const CustomerDisplayApp());
}
