import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/material.dart';
import 'package:kds_pos/app.dart';

// Referenced only so the customerDisplayMain() entrypoint is included in the compiled kernel -
// the native side invokes it by name via DartExecutor.DartEntrypoint, which fails with
// "Dart_LookupLibrary: ... not found" if nothing in main's import graph reaches this library.
// ignore: unused_import
import 'package:kds_pos/Feactures/POS/CustomerTerminal/customer_display_main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ConvexClient.initialize(
    const ConvexConfig(
      deploymentUrl: 'https://glad-bear-64.eu-west-1.convex.cloud',
      clientId: 'kds-pos-employee-terminal',
    ),
  );
  runApp(const App());
}
