import 'package:flutter/material.dart';

import '../../design/uptrack_design.dart';

/// Compatibility entrypoint; actual presentation is shared with the gallery.
class MonitorStatusChip extends StatelessWidget {
  const MonitorStatusChip({required this.status, super.key});
  final String status;
  @override
  Widget build(BuildContext context) => UptrackStatusBadge(status: status);
}
