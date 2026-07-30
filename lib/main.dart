import 'package:convex_flutter/convex_flutter.dart';
import 'package:flutter/material.dart';
import 'package:kds_pos/app.dart';

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
