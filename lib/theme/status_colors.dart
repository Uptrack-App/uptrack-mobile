import 'package:flutter/material.dart';

import 'tokens.dart';

/// Semantic status look: a foreground color, its soft background, an icon and a
/// label. Status is never color alone (icon + text + color), as in web
/// DESIGN.md. Read it with `UptrackStatusColors.of(context)`.
@immutable
class UptrackStatus {
  const UptrackStatus({
    required this.color,
    required this.soft,
    required this.icon,
    required this.label,
  });

  final Color color;
  final Color soft;
  final IconData icon;
  final String label;
}

@immutable
class UptrackStatusColors extends ThemeExtension<UptrackStatusColors> {
  const UptrackStatusColors({
    required this.up,
    required this.down,
    required this.degraded,
    required this.paused,
    required this.unknown,
  });

  final UptrackStatus up;
  final UptrackStatus down;
  final UptrackStatus degraded;
  final UptrackStatus paused;
  final UptrackStatus unknown;

  static const UptrackStatusColors light = UptrackStatusColors(
    up: UptrackStatus(
      color: UptrackColors.upLight,
      soft: UptrackColors.upSoftLight,
      icon: Icons.check,
      label: 'Up',
    ),
    down: UptrackStatus(
      color: UptrackColors.downLight,
      soft: UptrackColors.downSoftLight,
      icon: Icons.close,
      label: 'Down',
    ),
    degraded: UptrackStatus(
      color: UptrackColors.degradedLight,
      soft: UptrackColors.degradedSoftLight,
      icon: Icons.warning_amber_rounded,
      label: 'Degraded',
    ),
    paused: UptrackStatus(
      color: UptrackColors.pausedLight,
      soft: UptrackColors.pausedSoftLight,
      icon: Icons.pause,
      label: 'Paused',
    ),
    unknown: UptrackStatus(
      color: UptrackColors.unknownLight,
      soft: UptrackColors.unknownSoftLight,
      icon: Icons.help_outline,
      label: 'Unknown',
    ),
  );

  static const UptrackStatusColors dark = UptrackStatusColors(
    up: UptrackStatus(
      color: UptrackColors.upDark,
      soft: UptrackColors.upSoftDark,
      icon: Icons.check,
      label: 'Up',
    ),
    down: UptrackStatus(
      color: UptrackColors.downDark,
      soft: UptrackColors.downSoftDark,
      icon: Icons.close,
      label: 'Down',
    ),
    degraded: UptrackStatus(
      color: UptrackColors.degradedDark,
      soft: UptrackColors.degradedSoftDark,
      icon: Icons.warning_amber_rounded,
      label: 'Degraded',
    ),
    paused: UptrackStatus(
      color: UptrackColors.pausedDark,
      soft: UptrackColors.pausedSoftDark,
      icon: Icons.pause,
      label: 'Paused',
    ),
    unknown: UptrackStatus(
      color: UptrackColors.unknownDark,
      soft: UptrackColors.unknownSoftDark,
      icon: Icons.help_outline,
      label: 'Unknown',
    ),
  );

  static UptrackStatusColors of(BuildContext context) {
    return Theme.of(context).extension<UptrackStatusColors>() ??
        (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

  /// Maps an API status string to a status look.
  UptrackStatus forStatus(String? status) {
    switch (status) {
      case 'up':
      case 'operational':
        return up;
      case 'down':
        return down;
      case 'degraded':
      case 'visual_regression':
      case 'partial_outage':
        return degraded;
      case 'paused':
      case 'disabled':
        return paused;
      default:
        return unknown;
    }
  }

  @override
  UptrackStatusColors copyWith({
    UptrackStatus? up,
    UptrackStatus? down,
    UptrackStatus? degraded,
    UptrackStatus? paused,
    UptrackStatus? unknown,
  }) {
    return UptrackStatusColors(
      up: up ?? this.up,
      down: down ?? this.down,
      degraded: degraded ?? this.degraded,
      paused: paused ?? this.paused,
      unknown: unknown ?? this.unknown,
    );
  }

  // Status colors do not animate between themes; switch at the midpoint.
  @override
  UptrackStatusColors lerp(
    ThemeExtension<UptrackStatusColors>? other,
    double t,
  ) {
    if (other is! UptrackStatusColors) return this;
    return t < 0.5 ? this : other;
  }
}
