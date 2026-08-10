import 'package:flutter/material.dart';
import 'package:kds_pos/Core/app_mode.dart';
import 'package:kds_pos/Database/repositories/device_repository.dart';

import 'app_colors.dart';

/// Process-wide appearance state (theme mode + accent color), consumed by `app.dart` to build
/// the `MaterialApp`'s theme. Deliberately NOT locally editable/persisted anymore — appearance
/// is one config per restaurant, set on the admin dashboard and applied to every device of every
/// flavour (POS/kiosk/handheld/display) via [applyRemote], called by `DeviceIdentityService`
/// whenever a `devices:whoAmI` update arrives (including live, mid-session). The values below
/// are just the pre-pairing/not-yet-configured defaults.
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  // Kiosk defaults to light (matching its storefront-style reference design) before its own
  // `kioskAppearance` config (see devices.ts's `whoAmI`) has arrived from Convex; every other
  // flavour keeps the previous dark default.
  ThemeMode _themeMode = appMode == 'kiosk' ? ThemeMode.light : ThemeMode.dark;
  Color _accent = AppColors.coralAccent;

  ThemeMode get themeMode => _themeMode;
  Color get accent => _accent;

  /// Applies a restaurant's web-configured appearance. `null` (no config
  /// set yet, or a device that's temporarily unpaired) leaves whatever's
  /// already showing untouched rather than reverting to the defaults.
  void applyRemote(RestaurantAppearance? appearance) {
    if (appearance == null) return;
    final mode = appearance.themeMode == 'light'
        ? ThemeMode.light
        : ThemeMode.dark;
    final accent = _parseHexColor(appearance.accentColorHex) ?? _accent;
    if (mode == _themeMode && accent == _accent) return;
    _themeMode = mode;
    _accent = accent;
    notifyListeners();
  }

  static Color? _parseHexColor(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }
}
