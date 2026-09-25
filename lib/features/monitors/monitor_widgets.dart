import 'package:flutter/material.dart';

/// Status pill shared by the monitor list and detail screens.
class MonitorStatusChip extends StatelessWidget {
  const MonitorStatusChip({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isUp = status == 'up';
    final ColorScheme scheme = theme.colorScheme;
    return Chip(
      label: Text(status),
      backgroundColor: isUp ? scheme.primaryContainer : scheme.errorContainer,
      labelStyle: theme.textTheme.labelSmall?.copyWith(
        color: isUp ? scheme.onPrimaryContainer : scheme.onErrorContainer,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
