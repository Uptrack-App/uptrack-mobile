import 'package:flutter/material.dart';

/// Ink Blue palette. Mirrors `uptrack-web/DESIGN.md` (the source of truth): cool
/// blue-gray neutrals and a navy ink primary. Status colors are the only
/// saturated hues. Text on a status's soft background needs at least 4.5:1.
/// Change a token in web DESIGN.md first, then here. See
/// docs/mobile/design-system.md in uptrack-spec.
abstract final class UptrackColors {
  // Primary (navy ink in light mode, light ink-blue in dark mode).
  static const Color brandLight = Color(0xFF1E3A5F);
  static const Color brandDark = Color(0xFF9CB8E0);

  // Status (light / dark).
  static const Color upLight = Color(0xFF387048);
  static const Color upDark = Color(0xFF7FB08A);
  static const Color downLight = Color(0xFFB03B1F);
  static const Color downDark = Color(0xFFEE7A63);
  static const Color degradedLight = Color(0xFF8A6400);
  static const Color degradedDark = Color(0xFFE0B354);
  static const Color pausedLight = Color(0xFF476685);
  static const Color pausedDark = Color(0xFF8AA8C4);
  static const Color unknownLight = Color(0xFF526176);
  static const Color unknownDark = Color(0xFF93A2B6);

  // Status soft backgrounds (text/icon sits on these).
  static const Color upSoftLight = Color(0xFFE6F0E8);
  static const Color upSoftDark = Color(0xFF2B3A30);
  static const Color downSoftLight = Color(0xFFF6E3DD);
  static const Color downSoftDark = Color(0xFF3B2B27);
  static const Color degradedSoftLight = Color(0xFFF4ECD6);
  static const Color degradedSoftDark = Color(0xFF3A3320);
  static const Color pausedSoftLight = Color(0xFFE3EAF1);
  static const Color pausedSoftDark = Color(0xFF28323C);
  static const Color unknownSoftLight = Color(0xFFE6EBF1);
  static const Color unknownSoftDark = Color(0xFF232D3A);

  // Neutrals.
  static const Color lightBackground = Color(0xFFF5F7FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightMuted = Color(0xFFEAEFF5);
  static const Color lightForeground = Color(0xFF121B28);
  static const Color lightBorder = Color(0xFFD6DEE8);

  static const Color darkBackground = Color(0xFF0E141C);
  static const Color darkSurface = Color(0xFF151D28);
  static const Color darkMuted = Color(0xFF1D2836);
  static const Color darkForeground = Color(0xFFE8EEF5);
  static const Color darkBorder = Color(0xFF2B3848);
}

abstract final class UptrackSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;
}

abstract final class UptrackRadii {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double pill = 999;
}

abstract final class UptrackTypography {
  static const String fontFamily = 'Geist';
  static const String monoFamily = 'GeistMono';

  static const double xs = 12;
  static const double sm = 14;
  static const double md = 16;
  static const double lg = 18;
  static const double xl = 20;
  static const double xxl = 24;
  static const double displaySm = 30;
  static const double displayMd = 36;

  static TextTheme textTheme(Color color) => TextTheme(
    bodySmall: TextStyle(fontFamily: fontFamily, fontSize: xs, color: color),
    bodyMedium: TextStyle(fontFamily: fontFamily, fontSize: md, color: color),
    bodyLarge: TextStyle(fontFamily: fontFamily, fontSize: lg, color: color),
    labelSmall: TextStyle(
      fontFamily: fontFamily,
      fontWeight: FontWeight.w500,
      fontSize: xs,
      color: color,
    ),
    labelMedium: TextStyle(
      fontFamily: fontFamily,
      fontWeight: FontWeight.w500,
      fontSize: sm,
      color: color,
    ),
    labelLarge: TextStyle(
      fontFamily: fontFamily,
      fontWeight: FontWeight.w500,
      fontSize: md,
      color: color,
    ),
    titleSmall: TextStyle(
      fontFamily: fontFamily,
      fontWeight: FontWeight.w600,
      fontSize: md,
      color: color,
    ),
    titleMedium: TextStyle(
      fontFamily: fontFamily,
      fontWeight: FontWeight.w600,
      fontSize: xl,
      color: color,
    ),
    titleLarge: TextStyle(
      fontFamily: fontFamily,
      fontWeight: FontWeight.w600,
      fontSize: xxl,
      color: color,
    ),
    headlineSmall: TextStyle(
      fontFamily: fontFamily,
      fontWeight: FontWeight.w600,
      fontSize: xxl,
      color: color,
    ),
    headlineMedium: TextStyle(
      fontFamily: fontFamily,
      fontWeight: FontWeight.w600,
      fontSize: displaySm,
      color: color,
    ),
    headlineLarge: TextStyle(
      fontFamily: fontFamily,
      fontWeight: FontWeight.w600,
      fontSize: displayMd,
      color: color,
    ),
  );
}
