import 'package:flutter/material.dart';

/// Palette tokens sampled from the "Food POS Dark - Tablet Device" Figma reference.
/// [AppTheme] (see `app_theme.dart`) is the only place these should be consumed from.
class AppColors {
  AppColors._();

  static const Color coralAccent = Color(0xFFF3775C);

  // Curated accent swatches offered from Settings > Appearance.
  static const List<Color> accentSwatches = [
    coralAccent,
    Color(0xFFE85D75), // rose
    Color(0xFFB56AF0), // violet
    Color(0xFF5B8DEF), // blue
    Color(0xFF3DBE8B), // green
    Color(0xFFE0B33D), // amber
    Color(0xFF4FC0D0), // teal
    Color(0xFFEF8A3D), // orange
  ];

  static const Color darkBackground = Color(0xFF14151E);
  static const Color darkSidebar = Color(0xFF1B1C28);
  static const Color darkSurface = Color(0xFF20212E);
  static const Color darkInputFill = Color(0xFF282A3A);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextMuted = Color(0xFF9497AC);
  static const Color darkOutline = Color(0xFF33354A);

  static const Color lightBackground = Color(0xFFF5F6FA);
  static const Color lightSidebar = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightInputFill = Color(0xFFEDEEF4);
  static const Color lightTextPrimary = Color(0xFF1C1D28);
  static const Color lightTextMuted = Color(0xFF6C6E80);
  static const Color lightOutline = Color(0xFFE1E2EC);

  static const Color success = Color(0xFF3DBE8B);
  static const Color warning = Color(0xFFE0B33D);
  static const Color info = Color(0xFF6C7BE0);
}
