import 'package:flutter/material.dart';

import 'customer_app.dart';

/// Dart entrypoint for the customer-display engine (see
/// `android/app/.../dualdisplay/CustomerDisplayActivity.kt`). Deliberately does not initialize
/// the Convex client - this screen only ever displays data relayed over the native
/// `DisplayBridge`, it never queries the backend directly.
@pragma('vm:entry-point')
void customerDisplayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CustomerDisplayApp());
}
