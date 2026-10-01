import 'package:flutter/material.dart';

import '../../theme/status_colors.dart';

/// Status pill shared by the monitor list and detail screens.
class MonitorStatusChip extends StatelessWidget {
  const MonitorStatusChip({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final UptrackStatus look = UptrackStatusColors.of(context)
        .forStatus(status);
    return Chip(
      avatar: Icon(look.icon, size: 14, color: look.color),
      label: Text(statusLabel(status)),
      backgroundColor: look.soft,
      side: BorderSide.none,
      labelStyle: theme.textTheme.labelSmall?.copyWith(color: look.color),
      visualDensity: VisualDensity.compact,
    );
  }
}
