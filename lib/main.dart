import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kds_pos/Core/connectivity/connectivity_service.dart';
import 'package:kds_pos/Core/theme/theme_controller.dart';
import 'package:kds_pos/app.dart';

// Referenced only so the customerDisplayMain() entrypoint is included in the compiled kernel -
// the native side invokes it by name via DartExecutor.DartEntrypoint, which fails with
// "Dart_LookupLibrary: ... not found" if nothing in main's import graph reaches this library.
// ignore: unused_import
import 'package:kds_pos/Feactures/POS/CustomerTerminal/customer_display_main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await ConvexClient.initialize(
    const ConvexConfig(
      deploymentUrl: 'https://glad-bear-64.eu-west-1.convex.cloud',
      clientId: 'kds-pos-employee-terminal',
    ),
  );
  await ThemeController.instance.load();
  // Universal, continuous connectivity monitor - starts once here rather than being wired up
  // per-screen, so it's already running (and ConnectivityBanner already live) by the time any
  // screen builds, on both the POS and Kiosk targets.
  ConnectivityService.instance.start();
  runApp(const App());
}
