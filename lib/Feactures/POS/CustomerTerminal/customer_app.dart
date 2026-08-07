import 'package:flutter/material.dart';
import 'package:kds_pos/Core/theme/app_theme.dart';
import 'package:kds_pos/Core/theme/theme_controller.dart';

import 'customer_display_screen.dart';

class CustomerDisplayApp extends StatelessWidget {
  const CustomerDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    // This runs on its own Flutter engine/isolate (see `customer_display_main.dart`), so it
    // can't observe live changes to the cashier engine's `ThemeController` instance - but both
    // engines run in the same Android process/app, so this engine's own `ThemeController`
    // (loaded from the same SharedPreferences before runApp, see `customer_display_main.dart`)
    // starts out matching whatever the cashier last picked in Settings. It won't pick up a
    // change made *while* this display is already showing, only what was set before it started.
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final controller = ThemeController.instance;
        return MaterialApp(
          title: 'Customer Display',
          themeMode: controller.themeMode,
          theme: buildAppTheme(brightness: Brightness.light, accent: controller.accent),
          darkTheme: buildAppTheme(brightness: Brightness.dark, accent: controller.accent),
          home: const CustomerDisplayScreen(),
        );
      },
    );
  }
}
