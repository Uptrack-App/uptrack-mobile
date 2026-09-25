import 'package:flutter/material.dart';

abstract final class UptrackColors {
  static const Color brand = Color(0xFFD97757);

  static const Color upLight = Color(0xFF4F8A5B);
  static const Color upDark = Color(0xFF7FB08A);
  static const Color downLight = Color(0xFFBC4123);
  static const Color downDark = Color(0xFFE2654C);
  static const Color degradedLight = Color(0xFFB5791F);
  static const Color degradedDark = Color(0xFFE0B354);
  static const Color paused = Color(0xFF6B8AA8);
  static const Color unknownLight = Color(0xFF777873);
  static const Color unknownDark = Color(0xFFAAA9A2);

  static const Color lightBackground = Color(0xFFF7F5F0);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightMuted = Color(0xFFECEAE4);
  static const Color lightForeground = Color(0xFF252622);
  static const Color lightBorder = Color(0xFFD8D6CF);

  static const Color darkBackground = Color(0xFF171816);
  static const Color darkSurface = Color(0xFF222320);
  static const Color darkMuted = Color(0xFF30312D);
  static const Color darkForeground = Color(0xFFF1F0EB);
  static const Color darkBorder = Color(0xFF41423D);
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
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
  static const double pill = 999;
}

abstract final class UptrackTypography {
  static const String fontFamily = 'Inter';

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
    labelSmall: TextStyle(fontFamily: fontFamily, fontSize: xs, color: color),
    labelMedium: TextStyle(fontFamily: fontFamily, fontSize: sm, color: color),
    labelLarge: TextStyle(fontFamily: fontFamily, fontSize: md, color: color),
    titleSmall: TextStyle(fontFamily: fontFamily, fontSize: md, color: color),
    titleMedium: TextStyle(fontFamily: fontFamily, fontSize: xl, color: color),
    titleLarge: TextStyle(fontFamily: fontFamily, fontSize: xxl, color: color),
    headlineSmall: TextStyle(
      fontFamily: fontFamily,
      fontSize: xxl,
      color: color,
    ),
    headlineMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: displaySm,
      color: color,
    ),
    headlineLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: displayMd,
      color: color,
    ),
  );
}
