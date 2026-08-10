import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kds_pos/Core/app_mode.dart';
import 'package:kds_pos/Core/connectivity/connectivity_service.dart';
import 'package:kds_pos/Database/convex_client.dart';
import 'package:kds_pos/Database/repositories/order_event_outbox.dart';
import 'package:kds_pos/app.dart';

// Referenced only so the customerDisplayMain() entrypoint is included in the compiled kernel -
// the native side invokes it by name via DartExecutor.DartEntrypoint, which fails with
// "Dart_LookupLibrary: ... not found" if nothing in main's import graph reaches this library.
// ignore: unused_import
import 'package:kds_pos/Feactures/POS/CustomerTerminal/customer_display_main.dart';

Future<void> main() async {
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
