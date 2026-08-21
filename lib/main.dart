import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kds_pos/Core/app_mode.dart';
import 'package:kds_pos/Core/connectivity/connectivity_service.dart';
import 'package:kds_pos/Database/convex_client.dart';
import 'package:kds_pos/Database/repositories/order_event_outbox.dart';
import 'package:kds_pos/app.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

// Referenced only so the customerDisplayMain() entrypoint is included in the compiled kernel -
// the native side invokes it by name via DartExecutor.DartEntrypoint, which fails with
// "Dart_LookupLibrary: ... not found" if nothing in main's import graph reaches this library.
// ignore: unused_import
import 'package:kds_pos/Feactures/POS/CustomerTerminal/customer_display_main.dart';

Future<void> main() async {
  await SentryFlutter.init((options) {
    // Self-hosted Bugsink instance (Sentry-protocol-compatible ingest) -
    // not sentry.io. Crash/error reporting only for now, no session
    // replay/perf tracing wired up, so tracesSampleRate stays at 0.
    options.dsn = 'https://72fdc9650846489ab46a66e3eca7c12d@bugsink.weareproxie.com/7';
    options.tracesSampleRate = 0.0;
  }, appRunner: _startApp);
}

Future<void> _startApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Landscape is only right for the cashier/D3-mini tablet layout and the wall-mounted order
  // status display - the kiosk (Sunmi Flex 3) is a portrait self-service panel, so locking it to
  // landscape too would rotate its whole UI sideways.
  await SystemChrome.setPreferredOrientations(
    appMode == 'kiosk'
        ? [DeviceOrientation.portraitUp]
        : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
  );
  await AppConvexClient.initialize(clientId: 'kds-pos-$appMode');
  // Universal, continuous connectivity monitor - starts once here rather than being wired up
  // per-screen, so it's already running (and ConnectivityBanner already live) by the time any
  // screen builds, on both the POS and Kiosk targets.
  ConnectivityService.instance.start();
  // Retries any order-lifecycle report (payment result/refund/cancellation) that didn't make it
  // to Convex before the app was last killed - see OrderEventOutbox's own doc comment for why
  // these can never be a plain fire-and-forget call.
  OrderEventOutbox.instance.start();
  runApp(const App());
}
