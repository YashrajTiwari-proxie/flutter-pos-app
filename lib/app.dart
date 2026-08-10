import 'package:flutter/material.dart';
import 'package:kds_pos/Core/app_mode.dart';
import 'package:kds_pos/Core/navigation/route_observer.dart';
import 'package:kds_pos/Core/theme/app_theme.dart';
import 'package:kds_pos/Core/theme/theme_controller.dart';
import 'package:kds_pos/Database/device_identity_service.dart';
import 'package:kds_pos/Database/pairing_screen.dart';
import 'package:kds_pos/Feactures/POS/EmployeeTerminal/employee_terminal_screen.dart';
import 'package:kds_pos/Feactures/Kiosk/kiosk_screen.dart';
import 'package:kds_pos/Feactures/OrderStatusDisplay/order_status_display_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  Widget _home() {
    switch (appMode) {
      case 'kiosk':
        return const KioskScreen();
      case 'display':
        return const OrderStatusDisplayScreen();
      default:
        return const EmployeeTerminalScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final controller = ThemeController.instance;
        return MaterialApp(
          title: 'NorrOne POS',
          // Each flavour is its own install/process, so `controller.themeMode` is always this
          // device's own flavour - which for kiosk now resolves to `kioskAppearance` (falling
          // back to the restaurant's shared `appearance`) via devices.ts's `whoAmI`, rather than
          // being hardcoded light here regardless of what's configured.
          themeMode: controller.themeMode,
          theme: buildAppTheme(
            brightness: Brightness.light,
            accent: controller.accent,
          ),
          darkTheme: buildAppTheme(
            brightness: Brightness.dark,
            accent: controller.accent,
          ),
          navigatorObservers: [routeObserver],
          home: ValueListenableBuilder<bool>(
            valueListenable: DeviceIdentityService.instance.isPairedNotifier,
            // Keyed on isPaired so a revocation mid-session (see
            // DeviceIdentityService's live status subscription) forces a
            // brand-new subtree here, rather than Flutter trying to
            // update the existing EmployeeTerminalScreen/KioskScreen
            // element in place - any pushed Orders/Settings routes on the
            // Navigator get discarded along with it, which is exactly
            // what should happen once this device's token no longer works.
            builder: (context, isPaired, _) => KeyedSubtree(
              key: ValueKey(isPaired),
              child: isPaired ? _home() : const PairingScreen(),
            ),
          ),
        );
      },
    );
  }
}
