import 'package:convex_flutter/convex_flutter.dart';

/// Single Convex client bootstrap, shared by every flavour (pos/kiosk/
/// handheld/display) — `main.dart` calls [initialize] once at startup;
/// every repository under `lib/Database` then talks to
/// `ConvexClient.instance` directly. Centralizes what used to be one
/// hardcoded `ConvexClient.initialize(...)` call living in `main.dart`
/// alone, pointed at a throwaway single-purpose backend.
class AppConvexClient {
  AppConvexClient._();

  /// Points at the admin-panel-v2 Convex deployment
  /// (`convex_main/admin-panel-v2/packages/backend`), deployed onto the
  /// same `glad-bear-64` project pos/kds_pos_backend previously used.
  /// Override per build with
  /// `--dart-define=CONVEX_URL=https://your-deployment.convex.cloud` so
  /// dev/staging/prod builds can target a different deployment without a
  /// code change.
  static const String deploymentUrl = String.fromEnvironment(
    'CONVEX_URL',
    defaultValue: 'https://glad-bear-64.eu-west-1.convex.cloud',
  );

  static Future<void> initialize({required String clientId}) {
    return ConvexClient.initialize(ConvexConfig(deploymentUrl: deploymentUrl, clientId: clientId));
  }
}
