import 'package:flutter/material.dart';

import '../../api/models/monitor.dart';
import '../../design/uptrack_design.dart';
import '../../util/date_format.dart';

/// Compatibility entrypoint; actual presentation is shared with the gallery.
class MonitorStatusChip extends StatelessWidget {
  const MonitorStatusChip({required this.status, super.key});
  final String status;
  @override
  Widget build(BuildContext context) => UptrackStatusBadge(status: status);
}

/// A URL without its scheme or trailing slash, for compact rows:
/// `https://api.example.com/` → `api.example.com`.
String displayUrl(String url) => url
    .replaceFirst(RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false), '')
    .replaceFirst(RegExp(r'/$'), '');

/// Human label for a monitor type: `http` → `HTTP`, `keyword` → `Keyword`.
String monitorTypeLabel(String type) {
  const Map<String, String> known = <String, String>{
    'http': 'HTTP',
    'https': 'HTTPS',
    'tcp': 'TCP',
    'dns': 'DNS',
    'ssl': 'SSL',
    'icmp': 'Ping',
    'ping': 'Ping',
    'udp': 'UDP',
    'smtp': 'SMTP',
    'grpc': 'gRPC',
  };
  final String key = type.toLowerCase();
  if (known.containsKey(key)) return known[key]!;
  if (type.isEmpty) return type;
  return type[0].toUpperCase() + type.substring(1).replaceAll('_', ' ');
}

/// How many regions must agree before an alert: `any` → `any region`.
String? regionsLabel(String required) => switch (required.toLowerCase()) {
  '' => null,
  'any' => 'any region',
  'all' => 'all regions',
  'majority' => 'majority of regions',
  final String other => '$other regions',
};

/// "Last check 17:07 · 214 ms", or "Last check failed · 17:07" when down.
String lastCheckLabel(LastCheck check) {
  final String when = formatTimestamp(check.checkedAt);
  final bool failed = check.status != 'up' && check.status != 'operational';
  return failed
      ? 'Last check ${statusLabel(check.status).toLowerCase()} · $when'
      : 'Last check $when · ${check.responseTime} ms';
}
