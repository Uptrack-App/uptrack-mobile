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

  /// Whether the incident has been acknowledged.
  bool get isAcknowledged => acknowledgedAt != null;

  /// Copy with a new `acknowledged_at` value (used for the optimistic
  /// acknowledge update; rolls back on error).
  Incident copyWith({String? acknowledgedAt}) => Incident(
    id: id,
    monitorId: monitorId,
    status: status,
    insertedAt: insertedAt,
    monitorName: monitorName,
    startedAt: startedAt,
    resolvedAt: resolvedAt,
    acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
  );

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

/// One posted incident update (`incident_updates.id` is a bigint, not a uuid).
class IncidentUpdate {
  const IncidentUpdate({
    required this.id,
    required this.status,
    this.title,
    this.description,
    this.postedAt,
  });

  factory IncidentUpdate.fromJson(Map<String, Object?> json) {
    return IncidentUpdate(
      id: (json['id']! as num).toInt(),
      status: json['status']! as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      postedAt: json['posted_at'] as String?,
    );
  }

  final int id;
  final String status;
  final String? title;
  final String? description;
  final String? postedAt;

  /// Headline shown in the updates list (falls back to the status).
  String get displayTitle {
    final String? trimmed = title?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return status;
  }
}

/// `GET /api/incidents/{id}` / `POST .../acknowledge` inner payload:
/// the incident plus its posted updates.
class IncidentDetail {
  const IncidentDetail({required this.incident, required this.updates});

  factory IncidentDetail.fromJson(Map<String, Object?> json) {
    final Object? incidentValue = json['incident'];
    if (incidentValue is! Map<String, Object?>) {
      throw FormatException('Unexpected shape for IncidentDetail');
    }
    final Object? updatesValue = json['updates'];
    return IncidentDetail(
      incident: Incident.fromJson(incidentValue),
      updates: updatesValue is List
          ? updatesValue
                .map(
                  (Object? e) => IncidentUpdate.fromJson(
                    (e! as Map).cast<String, Object?>(),
                  ),
                )
                .toList()
          : const <IncidentUpdate>[],
    );
  }

  final Incident incident;
  final List<IncidentUpdate> updates;
}
