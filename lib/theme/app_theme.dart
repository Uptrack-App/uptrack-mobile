import 'package:flutter/material.dart';

import 'status_colors.dart';
import 'tokens.dart';

/// Material theme built from the web tokens v2 (see tokens.dart). The app
/// follows the OS brightness (`ThemeMode.system`); light is the default.
///
/// Role map:
/// - `primary` is the blue accent (links, focus, active states).
/// - `secondary` and the selected segment are neutral (web `--secondary`),
///   never a status color.
/// - `tertiary` and filled buttons are the ink CTA (web `--cta`).
/// - `error` is web `--destructive`.
abstract final class AppTheme {
  static final ThemeData dark = _build(Brightness.dark);
  static final ThemeData light = _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final foreground = isDark
        ? UptrackColors.darkForeground
        : UptrackColors.lightForeground;
    final body = isDark ? UptrackColors.darkBody : UptrackColors.lightBody;
    final mutedForeground = isDark
        ? UptrackColors.darkMutedForeground
        : UptrackColors.lightMutedForeground;
    final background = isDark
        ? UptrackColors.darkBackground
        : UptrackColors.lightBackground;
    final surface = isDark
        ? UptrackColors.darkSurface
        : UptrackColors.lightSurface;
    final surfaceRaised = isDark
        ? UptrackColors.darkSurfaceRaised
        : UptrackColors.lightSurfaceRaised;
    final band = isDark ? UptrackColors.darkBand : UptrackColors.lightBand;
    final border = isDark
        ? UptrackColors.darkBorder
        : UptrackColors.lightBorder;
    final input = isDark ? UptrackColors.darkInput : UptrackColors.lightInput;
    final primary = isDark
        ? UptrackColors.darkPrimary
        : UptrackColors.lightPrimary;
    final onPrimary = isDark
        ? UptrackColors.darkOnPrimary
        : UptrackColors.lightOnPrimary;
    final cta = isDark ? UptrackColors.darkCta : UptrackColors.lightCta;
    final onCta = isDark ? UptrackColors.darkOnCta : UptrackColors.lightOnCta;
    final destructive = isDark
        ? UptrackColors.darkDestructive
        : UptrackColors.lightDestructive;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: surfaceRaised,
      onPrimaryContainer: foreground,
      secondary: surfaceRaised,
      onSecondary: foreground,
      secondaryContainer: surfaceRaised,
      onSecondaryContainer: foreground,
      tertiary: cta,
      onTertiary: onCta,
      tertiaryContainer: surfaceRaised,
      onTertiaryContainer: foreground,
      error: destructive,
      onError: isDark ? UptrackColors.darkBackground : Colors.white,
      surface: surface,
      onSurface: foreground,
      surfaceDim: background,
      surfaceBright: surface,
      surfaceContainerLowest: background,
      surfaceContainerLow: band,
      surfaceContainer: band,
      surfaceContainerHigh: surfaceRaised,
      surfaceContainerHighest: surfaceRaised,
      onSurfaceVariant: mutedForeground,
      outline: input,
      outlineVariant: border,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: foreground,
      onInverseSurface: background,
      inversePrimary: isDark
          ? UptrackColors.lightPrimary
          : UptrackColors.darkPrimary,
      surfaceTint: Colors.transparent,
    );
    final borderRadius = BorderRadius.circular(UptrackRadii.md);
    final shape = RoundedRectangleBorder(borderRadius: borderRadius);
    final ctaStyle = FilledButton.styleFrom(
      backgroundColor: cta,
      foregroundColor: onCta,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UptrackRadii.sm),
      ),
    );

    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: UptrackTypography.fontFamily,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: UptrackTypography.textTheme(
        foreground,
        body: body,
        muted: mutedForeground,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceRaised,
        labelStyle: TextStyle(
          fontFamily: UptrackTypography.fontFamily,
          fontWeight: FontWeight.w500,
          fontSize: UptrackTypography.xs,
          color: foreground,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UptrackRadii.sm),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (Set<WidgetState> states) =>
                states.contains(WidgetState.selected) ? surfaceRaised : surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (Set<WidgetState> states) => states.contains(WidgetState.selected)
                ? foreground
                : mutedForeground,
          ),
          side: WidgetStatePropertyAll<BorderSide>(BorderSide(color: border)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: ctaStyle),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(borderRadius: borderRadius),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: input),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      listTileTheme: ListTileThemeData(shape: shape),
      extensions: <ThemeExtension<dynamic>>[
        isDark ? UptrackStatusColors.dark : UptrackStatusColors.light,
      ],
      useMaterial3: true,
    );
  }
}
