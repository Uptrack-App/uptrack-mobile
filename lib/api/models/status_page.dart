/// Public status page models for `GET /api/status/{slug}`.
///
/// Shape mirror: `ShowPublicEnvelope` / `ShowPublicData` in the web
/// backend's OpenAPI spec (`openapi-v2.json`).
class StatusPageMonitor {
  const StatusPageMonitor({
    required this.name,
    required this.status,
    this.responseTime,
    this.lastCheckedAt,
  });

  factory StatusPageMonitor.fromJson(Map<String, Object?> json) {
    return StatusPageMonitor(
      name: json['name']! as String,
      status: json['status']! as String,
      responseTime: (json['response_time'] as num?)?.toInt(),
      lastCheckedAt: json['last_checked_at'] as String?,
    );
  }

  final String name;

  /// `up` | `down` | `unknown`.
  final String status;
  final int? responseTime;
  final String? lastCheckedAt;
}

class StatusPageIncident {
  const StatusPageIncident({
    required this.id,
    required this.status,
    this.monitorName,
    this.startedAt,
    this.resolvedAt,
    this.cause,
  });

  factory StatusPageIncident.fromJson(Map<String, Object?> json) {
    return StatusPageIncident(
      id: json['id']! as String,
      status: json['status']! as String,
      monitorName: json['monitor_name'] as String?,
      startedAt: json['started_at'] as String?,
      resolvedAt: json['resolved_at'] as String?,
      cause: json['cause'] as String?,
    );
  }

  final String id;
  final String status;
  final String? monitorName;
  final String? startedAt;
  final String? resolvedAt;
  final String? cause;
}

/// The `{ data }` payload of the public status page.
class StatusPageData {
  const StatusPageData({
    required this.name,
    required this.slug,
    required this.overallStatus,
    required this.uptimePercentage,
    this.description,
    this.monitors = const <StatusPageMonitor>[],
    this.recentIncidents = const <StatusPageIncident>[],
  });

  factory StatusPageData.fromJson(Map<String, Object?> json) {
    List<StatusPageMonitor> monitorsFrom(Object? raw) {
      if (raw is! List) {
        return const <StatusPageMonitor>[];
      }
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (Map<dynamic, dynamic> e) =>
                StatusPageMonitor.fromJson(e.cast<String, Object?>()),
          )
          .toList();
    }

    List<StatusPageIncident> incidentsFrom(Object? raw) {
      if (raw is! List) {
        return const <StatusPageIncident>[];
      }
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (Map<dynamic, dynamic> e) =>
                StatusPageIncident.fromJson(e.cast<String, Object?>()),
          )
          .toList();
    }

    return StatusPageData(
      name: json['name']! as String,
      slug: json['slug']! as String,
      overallStatus: json['overall_status']! as String,
      uptimePercentage: (json['uptime_percentage'] as num? ?? 0).toDouble(),
      description: json['description'] as String?,
      monitors: monitorsFrom(json['monitors']),
      recentIncidents: incidentsFrom(json['recent_incidents']),
    );
  }

  final String name;
  final String slug;

  /// `operational` | `degraded` | `partial_outage` | `major_outage`.
  final String overallStatus;
  final double uptimePercentage;
  final String? description;
  final List<StatusPageMonitor> monitors;
  final List<StatusPageIncident> recentIncidents;
}
