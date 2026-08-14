import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kds_pos/Database/convex_client.dart';
import 'package:kds_pos/Feactures/POS/Settings/TcsTest/tcs_test_screen.dart';

/// Entrypoint for the `tcs` product flavor — a standalone, install-side-by-
/// side build dedicated to TCS-D fiscalization testing. Deliberately
/// separate from lib/main.dart/lib/app.dart, not a branch inside them, so
/// the real POS/kiosk/display entrypoint is never touched by this test-only
/// flavor. No pairing flow, no device registration - just [TcsTestScreen]
/// with predefined test values (see that file's top-of-file constants).
///
/// Run with: `flutter run --flavor tcs -t lib/test_main.dart`
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  // Still required - TcsService calls Convex the same way every other device-facing call in
  // this app does (ConvexClient.instance.action(...)), just with a hardcoded token below
  // instead of one from a real pairing flow.
  await AppConvexClient.initialize(clientId: 'kds-pos-tcs-test');
  runApp(const MaterialApp(home: TcsTestScreen()));
}
