import 'package:flutter/material.dart';

import 'status_colors.dart';
import 'tokens.dart';

abstract final class AppTheme {
  static final ThemeData dark = _build(Brightness.dark);
  static final ThemeData light = _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final foreground = isDark
        ? UptrackColors.darkForeground
        : UptrackColors.lightForeground;
    final background = isDark
        ? UptrackColors.darkBackground
        : UptrackColors.lightBackground;
    final surface = isDark
        ? UptrackColors.darkSurface
        : UptrackColors.lightSurface;
    final muted = isDark ? UptrackColors.darkMuted : UptrackColors.lightMuted;
    final border = isDark
        ? UptrackColors.darkBorder
        : UptrackColors.lightBorder;
    final brand = isDark ? UptrackColors.brandDark : UptrackColors.brandLight;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: brand,
      onPrimary: isDark ? UptrackColors.darkBackground : Colors.white,
      secondary: isDark ? UptrackColors.upDark : UptrackColors.upLight,
      onSecondary: isDark ? UptrackColors.darkBackground : Colors.white,
      error: isDark ? UptrackColors.downDark : UptrackColors.downLight,
      onError: isDark ? UptrackColors.darkBackground : Colors.white,
      surface: surface,
      onSurface: foreground,
      surfaceContainerHighest: muted,
      onSurfaceVariant: isDark
          ? UptrackColors.unknownDark
          : UptrackColors.unknownLight,
      outline: border,
      outlineVariant: border,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: foreground,
      onInverseSurface: background,
      inversePrimary: isDark
          ? UptrackColors.brandLight
          : UptrackColors.brandDark,
      tertiary: isDark
          ? UptrackColors.degradedDark
          : UptrackColors.degradedLight,
      onTertiary: isDark ? UptrackColors.darkBackground : Colors.white,
      surfaceTint: brand,
    );
    final borderRadius = BorderRadius.circular(UptrackRadii.md);
    final shape = RoundedRectangleBorder(borderRadius: borderRadius);

    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: UptrackTypography.textTheme(foreground),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: shape,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(borderRadius: borderRadius),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: brand, width: 2),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        isDark ? UptrackStatusColors.dark : UptrackStatusColors.light,
      ],
      useMaterial3: true,
    );
  }
}
