/// Incident rows from `GET /api/incidents` (subset of `IncidentOut`).
class Incident {
  const Incident({
    required this.id,
    required this.monitorId,
    required this.status,
    required this.insertedAt,
    this.monitorName,
    this.startedAt,
    this.resolvedAt,
    this.acknowledgedAt,
  });

  factory Incident.fromJson(Map<String, Object?> json) {
    return Incident(
      id: json['id']! as String,
      monitorId: json['monitor_id']! as String,
      status: json['status']! as String,
      insertedAt: json['inserted_at']! as String,
      monitorName: json['monitor_name'] as String?,
      startedAt: json['started_at'] as String?,
      resolvedAt: json['resolved_at'] as String?,
      acknowledgedAt: json['acknowledged_at'] as String?,
    );
  }

  final String id;
  final String monitorId;
  final String status;
  final String insertedAt;
  final String? monitorName;
  final String? startedAt;
  final String? resolvedAt;
  final String? acknowledgedAt;

  /// Whether the incident is still open (`resolved_at` unset).
  bool get isOngoing => resolvedAt == null;

  /// Human-readable title shown on the dashboard recent-incidents list.
  String get displayName {
    final String? trimmed = monitorName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return 'Incident $id';
  }
}

/// `GET /api/incidents` envelope (`{ data }`, newest first).
class IncidentListResponse {
  const IncidentListResponse({required this.data});

  factory IncidentListResponse.fromJson(Map<String, Object?> json) {
    final Object? items = json['data'];
    if (items is! List) {
      throw FormatException('Unexpected shape for IncidentListResponse');
    }
    return IncidentListResponse(
      data: items
          .map(
            (Object? e) =>
                Incident.fromJson((e! as Map).cast<String, Object?>()),
          )
          .toList(),
    );
  }

  final List<Incident> data;
}
