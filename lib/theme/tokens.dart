import 'package:flutter/material.dart';

/// Shared Ink colors are generated from `uptrack-web/design/tokens.json`.
/// Update the canonical JSON, then run `dart run tool/generate_tokens.dart`.
/// Geometry, typography and Flutter-specific effects remain mobile-owned.
export 'colors.g.dart';

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
          height: 1.4,
          color: muted ?? color,
        ),
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: md,
          height: 1.5,
          color: body ?? color,
        ),
        bodyLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: lg,
          height: 1.5,
          color: body ?? color,
        ),
        labelSmall: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w500,
          fontSize: xs,
          height: 1.4,
          color: color,
        ),
        labelMedium: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w500,
          fontSize: sm,
          height: 1.5,
          color: color,
        ),
        labelLarge: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w500,
          fontSize: md,
          height: 1.5,
          color: color,
        ),
        titleSmall: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: md,
          height: 1.5,
          color: color,
        ),
        titleMedium: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: xl,
          height: 1.3,
          color: color,
        ),
        titleLarge: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: xxl,
          height: 1.25,
          color: color,
        ),
        headlineSmall: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: xxl,
          height: 1.25,
          color: color,
        ),
        headlineMedium: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: displaySm,
          height: 1.2,
          color: color,
        ),
        headlineLarge: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: displayMd,
          height: 1.15,
          color: color,
        ),
      );
}
