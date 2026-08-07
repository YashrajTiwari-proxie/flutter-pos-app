import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Builds the app's [ThemeData] for a given [brightness]/[accent] pair. Both Flutter engines
/// (cashier + customer display, see `CustomerTerminal/customer_app.dart`) render from this same
/// function so the two screens always share one visual language.
ThemeData buildAppTheme({required Brightness brightness, required Color accent}) {
  final isDark = brightness == Brightness.dark;

  final background = isDark ? AppColors.darkBackground : AppColors.lightBackground;
  final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
  final inputFill = isDark ? AppColors.darkInputFill : AppColors.lightInputFill;
  final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  final textMuted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
  final outline = isDark ? AppColors.darkOutline : AppColors.lightOutline;

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: accent,
    onPrimary: Colors.white,
    secondary: textMuted,
    onSecondary: textPrimary,
    error: const Color(0xFFE0574F),
    onError: Colors.white,
    surface: surface,
    onSurface: textPrimary,
    surfaceContainerLowest: background,
    surfaceContainerLow: surface,
    surfaceContainer: surface,
    surfaceContainerHigh: inputFill,
    surfaceContainerHighest: inputFill,
    onSurfaceVariant: textMuted,
    outline: outline,
    outlineVariant: outline,
    tertiary: AppColors.info,
    onTertiary: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: background,
    colorScheme: colorScheme,
    textTheme: Typography.material2021(platform: TargetPlatform.android).englishLike
        .apply(bodyColor: textPrimary, displayColor: textPrimary)
        .merge(
          TextTheme(
            titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
            titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
            titleSmall: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
            bodyMedium: TextStyle(color: textMuted),
            bodySmall: TextStyle(color: textMuted),
          ),
        ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputFill,
      hintStyle: TextStyle(color: textMuted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    dividerTheme: DividerThemeData(color: outline, space: 1),
    iconTheme: IconThemeData(color: textMuted),
    chipTheme: ChipThemeData(
      backgroundColor: inputFill,
      labelStyle: TextStyle(color: textPrimary),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
