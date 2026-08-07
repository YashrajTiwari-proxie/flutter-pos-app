import 'package:flutter/material.dart';
import 'package:kds_pos/Core/navigation/route_observer.dart';
import 'package:kds_pos/Core/theme/app_theme.dart';
import 'package:kds_pos/Core/theme/theme_controller.dart';
import 'package:kds_pos/Feactures/POS/EmployeeTerminal/employee_terminal_screen.dart';
import 'package:kds_pos/Feactures/POS/Kiosk/kiosk_screen.dart';
import 'package:kds_pos/Feactures/POS/OrderStatusDisplay/order_status_display_screen.dart';

/// Which of the three build targets this binary is - set per Android product flavor via
/// `--dart-define=APP_MODE=...` (see android/app/build.gradle.kts). Defaults to the cashier
/// POS app so an unflavored `flutter run` behaves exactly as before.
const _appMode = String.fromEnvironment('APP_MODE', defaultValue: 'pos');

class App extends StatelessWidget {
  const App({super.key});

  Widget _home() {
    switch (_appMode) {
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
          home: _home(),
        );
      },
    );
  }
}
