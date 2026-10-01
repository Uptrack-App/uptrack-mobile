import 'package:flutter/material.dart';

/// Uptrack "Ink" palette, tokens v2. Mirrors `uptrack-web/src/styles.css`
/// (`:root` = light, `.dark` = dark) and the front matter of
/// `uptrack-web/DESIGN.md`, which are the source of truth. White pages, gray
/// bands, an ink CTA and a blue accent. Status colors are the only saturated
/// hues. Text on a status's soft background needs at least 4.5:1.
/// Change a token on the web first, then here.
abstract final class UptrackColors {
  // Light (`:root`).
  static const Color lightBackground = Color(0xFFFFFFFF); // --background
  static const Color lightSurface = Color(0xFFFFFFFF); // --card
  static const Color lightSurfaceRaised = Color(0xFFF1F4F8); // --muted
  static const Color lightBand = Color(0xFFF5F7FA); // --band
  static const Color lightForeground = Color(0xFF0E1520); // --foreground
  static const Color lightBody = Color(0xFF3D4A5C); // --body
  static const Color lightMutedForeground = Color(0xFF5E6B7D);
  static const Color lightBorder = Color(0xFFE3E8EF); // --border
  static const Color lightInput = Color(0xFFD5DCE6); // --input
  static const Color lightPrimary = Color(0xFF1F5AD6); // --primary (accent)
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightCta = Color(0xFF0E1520); // --cta (ink)
  static const Color lightOnCta = Color(0xFFFFFFFF);
  static const Color lightDestructive = Color(0xFFBC4123);

  // Dark (`.dark`).
  static const Color darkBackground = Color(0xFF0A0E14);
  static const Color darkSurface = Color(0xFF111822);
  static const Color darkSurfaceRaised = Color(0xFF18212D);
  static const Color darkBand = Color(0xFF111822);
  static const Color darkForeground = Color(0xFFEEF2F6);
  static const Color darkBody = Color(0xFFBAC5D2);
  static const Color darkMutedForeground = Color(0xFF8795A8);
  static const Color darkBorder = Color(0xFF243041);
  static const Color darkInput = Color(0xFF2B3848);
  static const Color darkPrimary = Color(0xFF8FB2F2);
  static const Color darkOnPrimary = Color(0xFF0A0E14);
  static const Color darkCta = Color(0xFFF2F5F8);
  static const Color darkOnCta = Color(0xFF0A0E14);
  static const Color darkDestructive = Color(0xFFEE7A63);

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
}

/// `--shadow-raised-value` from the web, light and dark.
abstract final class UptrackShadows {
  static const List<BoxShadow> raisedLight = <BoxShadow>[
    BoxShadow(color: Color(0x0F0E1520), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(
      color: Color(0x2E0E1520),
      offset: Offset(0, 10),
      blurRadius: 28,
      spreadRadius: -14,
    ),
  ];
  static const List<BoxShadow> raisedDark = <BoxShadow>[
    BoxShadow(
      color: Color(0x8C000000),
      offset: Offset(0, 10),
      blurRadius: 30,
      spreadRadius: -14,
    ),
  ];
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
  static const double frame = 14;
  static const double pill = 999;
}

abstract final class UptrackTypography {
  static const String fontFamily = 'IBMPlexSans';
  static const String monoFamily = 'IBMPlexMono';

  static const double xs = 12;
  static const double sm = 14;
  static const double md = 16;
  static const double lg = 18;
  static const double xl = 20;
  static const double xxl = 24;
  static const double displaySm = 30;
  static const double displayMd = 36;

  /// [color] is the heading/label ink; [body] is running text (web `--body`);
  /// [muted] is secondary text such as timestamps (web `--muted-foreground`).
  static TextTheme textTheme(Color color, {Color? body, Color? muted}) =>
      TextTheme(
        bodySmall: TextStyle(
          fontFamily: fontFamily,
          fontSize: xs,
          color: muted ?? color,
        ),
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: md,
          color: body ?? color,
        ),
        bodyLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: lg,
          color: body ?? color,
        ),
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
