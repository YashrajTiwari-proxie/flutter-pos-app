import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

/// Process-wide appearance state (theme mode + accent color), consumed by `app.dart` to build
/// the `MaterialApp`'s theme. Persisted to [SharedPreferences] so a staff member's choice in
/// Settings > Appearance survives an app restart instead of resetting to the defaults below -
/// call [load] once before `runApp` (see `main.dart`).
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const _themeModeKey = 'appearance.theme_mode';
  static const _accentKey = 'appearance.accent_color';

  ThemeMode _themeMode = ThemeMode.dark;
  Color _accent = AppColors.coralAccent;

  ThemeMode get themeMode => _themeMode;
  Color get accent => _accent;

  /// Loads the last-saved theme mode/accent, if any. Falls back to the defaults above when
  /// nothing has been saved yet (first run) or storage isn't readable.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_themeModeKey);
    if (savedMode == ThemeMode.light.name) {
      _themeMode = ThemeMode.light;
    } else if (savedMode == ThemeMode.dark.name) {
      _themeMode = ThemeMode.dark;
    }
    final savedAccent = prefs.getInt(_accentKey);
    if (savedAccent != null) {
      _accent = Color(savedAccent);
    }
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    _save(_themeModeKey, mode.name);
  }

  void toggleMode() {
    setThemeMode(
      _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }

  void setAccent(Color color) {
    if (_accent == color) return;
    _accent = color;
    notifyListeners();
    _saveAccent(color);
  }

  Future<void> _save(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _saveAccent(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accentKey, color.toARGB32());
  }
}
