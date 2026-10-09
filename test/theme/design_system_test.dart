import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/theme/app_theme.dart';
import 'package:uptrack_mobile/theme/status_colors.dart';
import 'package:uptrack_mobile/theme/tokens.dart';

/// Guard rails for the Ink design system (tokens v2) (uptrack-web/DESIGN.md is the
/// source of truth; token map: uptrack-spec/docs/mobile/design-system.md).

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('text contrast is at least 4.5:1 (WCAG AA)', () {
    for (final bool isDark in <bool>[true, false]) {
      final String mode = isDark ? 'dark' : 'light';
      final ThemeData theme = isDark ? AppTheme.dark : AppTheme.light;
      final ColorScheme scheme = theme.colorScheme;
      final UptrackStatusColors status = isDark
          ? UptrackStatusColors.dark
          : UptrackStatusColors.light;
      final Color background = theme.scaffoldBackgroundColor;

      final Map<String, (Color, Color)> pairs = <String, (Color, Color)>{
        'foreground on background': (scheme.onSurface, background),
        'foreground on surface': (scheme.onSurface, scheme.surface),
        'muted text on background': (scheme.onSurfaceVariant, background),
        'muted text on surface': (scheme.onSurfaceVariant, scheme.surface),
        'primary on background': (scheme.primary, background),
        'onPrimary on primary': (scheme.onPrimary, scheme.primary),
        'onError on error': (scheme.onError, scheme.error),
        'onSecondary on secondary': (scheme.onSecondary, scheme.secondary),
        'onTertiary on tertiary': (scheme.onTertiary, scheme.tertiary),
      };
      for (final MapEntry<String, UptrackStatus> e in <String, UptrackStatus>{
        'up': status.up,
        'down': status.down,
        'degraded': status.degraded,
        'paused': status.paused,
        'unknown': status.unknown,
      }.entries) {
        pairs['status ${e.key} on its soft background'] = (
          e.value.color,
          e.value.soft,
        );
        pairs['status ${e.key} on surface'] = (e.value.color, scheme.surface);
      }

      for (final MapEntry<String, (Color, Color)> p in pairs.entries) {
        test('$mode: ${p.key}', () {
          final double ratio = _contrast(p.value.$1, p.value.$2);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '${p.key} is ${ratio.toStringAsFixed(2)}:1',
          );
        });
      }
    }
  });

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    test('${theme.brightness}: essential input outline contrast', () {
      final border =
          theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
      expect(
        _contrast(border.borderSide.color, theme.colorScheme.surface),
        greaterThanOrEqualTo(3),
      );
      expect(
        _contrast(theme.colorScheme.outline, theme.colorScheme.surface),
        greaterThanOrEqualTo(3),
      );
    });
  }

  test('screens use theme colors: no hardcoded colors outside lib/theme', () {
    final RegExp hardcoded = RegExp(
      r'Color\(\s*0x|Colors\.(red|green|amber|orange|blue|purple|deepPurple|pink|indigo|teal|yellow|grey|brown|cyan|lime)',
    );
    final List<String> offenders = <String>[];
    for (final FileSystemEntity f in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains(
        '${Platform.pathSeparator}theme${Platform.pathSeparator}',
      )) {
        continue;
      }
      final List<String> lines = f.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (hardcoded.hasMatch(lines[i])) {
          offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('theme uses the bundled Instrument Sans and JetBrains Mono families', () {
    expect(UptrackTypography.fontFamily, 'InstrumentSans');
    expect(UptrackTypography.monoFamily, 'JetBrainsMono');
    expect(AppTheme.dark.textTheme.bodyMedium?.fontFamily, 'InstrumentSans');
    expect(AppTheme.light.textTheme.titleLarge?.fontFamily, 'InstrumentSans');
  });

  test('tokens v2 match uptrack-web styles.css', () {
    expect(UptrackColors.lightBackground, const Color(0xFFFFFFFF));
    expect(UptrackColors.lightForeground, const Color(0xFF0E1520));
    expect(UptrackColors.lightCta, const Color(0xFF0E1520));
    expect(UptrackColors.lightPrimary, const Color(0xFF1F5AD6));
    expect(UptrackColors.darkBackground, const Color(0xFF0A0E14));
    expect(UptrackColors.darkCta, const Color(0xFFF2F5F8));
    expect(UptrackColors.darkPrimary, const Color(0xFF8FB2F2));
    expect(AppTheme.light.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
    expect(AppTheme.dark.scaffoldBackgroundColor, const Color(0xFF0A0E14));
  });

  test('selected segment and secondary are neutral, not status colors', () {
    for (final bool isDark in <bool>[true, false]) {
      final ThemeData theme = isDark ? AppTheme.dark : AppTheme.light;
      final UptrackStatusColors status = isDark
          ? UptrackStatusColors.dark
          : UptrackStatusColors.light;
      final Set<Color> statusColors = <Color>{
        for (final UptrackStatus s in <UptrackStatus>[
          status.up,
          status.down,
          status.degraded,
          status.paused,
          status.unknown,
        ]) ...<Color>[s.color, s.soft],
      };
      final Color? selected = theme.segmentedButtonTheme.style?.backgroundColor
          ?.resolve(<WidgetState>{WidgetState.selected});
      expect(selected, isNotNull);
      expect(statusColors, isNot(contains(selected)));
      expect(statusColors, isNot(contains(theme.colorScheme.secondary)));
      expect(
        statusColors,
        isNot(contains(theme.colorScheme.secondaryContainer)),
      );
    }
  });

  test('filled buttons use the ink CTA', () {
    expect(
      AppTheme.light.filledButtonTheme.style?.backgroundColor?.resolve(
        <WidgetState>{},
      ),
      UptrackColors.lightCta,
    );
    expect(
      AppTheme.dark.filledButtonTheme.style?.backgroundColor?.resolve(
        <WidgetState>{},
      ),
      UptrackColors.darkCta,
    );
  });
}
