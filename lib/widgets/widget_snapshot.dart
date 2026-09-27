import '../api/models/incident.dart';
import '../data/local/cache_repository.dart';
import '../push/push_message.dart';

/// Storage keys for the per-field widget data written via `home_widget`
/// (`saveWidgetData` stores one primitive per key; see `widget_store.dart`).
abstract final class WidgetDataKeys {
  static const String prefix = 'uptrack_widget_';
  static const String incidentId = '${prefix}incident_id';
  static const String monitorId = '${prefix}monitor_id';
  static const String monitorName = '${prefix}monitor_name';
  static const String status = '${prefix}status';
  static const String startedAt = '${prefix}started_at';
  static const String acknowledged = '${prefix}acknowledged';
  static const String updatedAt = '${prefix}updated_at';

  /// Set when a push names an incident the cache does not know yet (push
  /// arrived before the next sync); cleared on the next successful refresh.
  static const String pendingIncidentId = '${prefix}pending_incident_id';

  static const List<String> all = <String>[
    incidentId,
    monitorId,
    monitorName,
    status,
    startedAt,
    acknowledged,
    updatedAt,
    pendingIncidentId,
  ];
}

/// What applying an incoming snapshot does to the currently stored one —
/// the collapse semantics shared by the cache refresh and the push path.
///
/// The home widget shows a single most-recent incident: repeat pushes for
/// the same incident *update* the stored fields in place, a different
/// incident *replaces* them, and a resolved incident *clears* the widget.
enum WidgetUpdateAction { update, replace, clear, noop }

/// Collapse decision for an incoming snapshot against the stored one.
///
/// - `clear` when the incoming incident resolved (nothing live to show).
/// - `noop` when there is nothing stored and nothing incoming.
/// - `update` when the incoming incident matches the stored one.
/// - `replace` otherwise (first incident, or a different incident).
WidgetUpdateAction collapseWidgetUpdate({
  required WidgetSnapshot? current,
  required WidgetSnapshot? incoming,
}) {
  if (incoming == null) {
    return current == null ? WidgetUpdateAction.noop : WidgetUpdateAction.clear;
  }
  if (incoming.isResolved) {
    return WidgetUpdateAction.clear;
  }
  if (current == null) {
    return WidgetUpdateAction.replace;
  }
  if (current.incidentId == incoming.incidentId) {
    return WidgetUpdateAction.update;
  }
  return WidgetUpdateAction.replace;
}

/// Incident-summary snapshot backing the home widget and the Live Activity
/// content: status, elapsed time anchor, and monitor name.
///
/// Pure data — built from the Drift cache ([IncidentSnapshot]), the API
/// ([Incident]), or merged with a push ([PushMessage]); serialized to
/// `home_widget` string/bool primitives via [toWidgetData].
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.incidentId,
    required this.monitorId,
    required this.status,
    required this.updatedAt,
    this.monitorName,
    this.startedAt,
    this.acknowledged = false,
  });

  /// Builds a snapshot from a Drift cache row.
  factory WidgetSnapshot.fromCache(IncidentSnapshot row) => WidgetSnapshot(
    incidentId: row.id,
    monitorId: row.monitorId,
    monitorName: row.monitorName,
    status: row.status,
    startedAt: row.startedAt,
    acknowledged: row.acknowledgedAt != null,
    updatedAt: DateTime.now(),
  );

  /// Builds a snapshot from an API incident.
  factory WidgetSnapshot.fromIncident(Incident incident) => WidgetSnapshot(
    incidentId: incident.id,
    monitorId: incident.monitorId,
    monitorName: incident.monitorName,
    status: incident.status,
    startedAt: incident.startedAt,
    acknowledged: incident.isAcknowledged,
    updatedAt: DateTime.now(),
  );

  /// Rebuilds a snapshot from previously stored widget data; null when
  /// [data] names no incident (fresh install or after a clear).
  static WidgetSnapshot? fromWidgetData(Map<String, Object?> data) {
    final Object? rawId = data[WidgetDataKeys.incidentId];
    if (rawId is! String || rawId.isEmpty) {
      return null;
    }
    final Object? rawMonitorId = data[WidgetDataKeys.monitorId];
    final Object? rawStatus = data[WidgetDataKeys.status];
    if (rawMonitorId is! String ||
        rawMonitorId.isEmpty ||
        rawStatus is! String ||
        rawStatus.isEmpty) {
      return null;
    }
    final Object? rawName = data[WidgetDataKeys.monitorName];
    final Object? rawStarted = data[WidgetDataKeys.startedAt];
    final Object? rawUpdated = data[WidgetDataKeys.updatedAt];
    DateTime updatedAt;
    if (rawUpdated is String) {
      updatedAt = DateTime.tryParse(rawUpdated) ?? DateTime.now();
    } else {
      updatedAt = DateTime.now();
    }
    return WidgetSnapshot(
      incidentId: rawId,
      monitorId: rawMonitorId,
      monitorName: rawName is String && rawName.isNotEmpty ? rawName : null,
      status: rawStatus,
      startedAt: rawStarted is String && rawStarted.isNotEmpty
          ? rawStarted
          : null,
      acknowledged: data[WidgetDataKeys.acknowledged] == true,
      updatedAt: updatedAt,
    );
  }

  /// Merges a push naming the *same* incident into this snapshot: the push
  /// carries no status of its own, so fields are preserved and only the
  /// monitor reference is filled in when previously unknown. Returns null
  /// when [message] names a different incident (or none) — the caller then
  /// re-resolves from the cache instead of guessing.
  WidgetSnapshot? mergePush(PushMessage message) {
    final String? incomingId = message.incidentId;
    if (incomingId == null || incomingId != incidentId) {
      return null;
    }
    final String? incomingMonitor = message.monitorId;
    return WidgetSnapshot(
      incidentId: incidentId,
      monitorId: monitorId.isNotEmpty
          ? monitorId
          : (incomingMonitor ?? monitorId),
      monitorName: monitorName,
      status: status,
      startedAt: startedAt,
      acknowledged: acknowledged,
      updatedAt: DateTime.now(),
    );
  }

  final String incidentId;
  final String monitorId;
  final String? monitorName;
  final String status;
  final String? startedAt;
  final bool acknowledged;
  final DateTime updatedAt;

  /// Whether the tracked incident resolved (the widget should clear).
  bool get isResolved => status == 'resolved';

  /// Display name for the widget title (falls back to the incident id).
  String get displayName {
    final String? trimmed = monitorName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return 'Incident $incidentId';
  }

  /// Elapsed time since the incident started (falls back to [updatedAt]
  /// when no start timestamp is known); null when unparseable.
  Duration? elapsedSince(DateTime now) {
    final String? anchor = startedAt;
    if (anchor == null || anchor.isEmpty) {
      return now.difference(updatedAt);
    }
    final DateTime? parsed = DateTime.tryParse(anchor);
    if (parsed == null) {
      return null;
    }
    return now.difference(parsed);
  }

  /// Short human label for [elapsedSince], e.g. `5m`, `2h`, `3d`.
  String elapsedLabel(DateTime now) {
    final Duration? elapsed = elapsedSince(now);
    if (elapsed == null) {
      return '—';
    }
    if (elapsed.isNegative) {
      return '0m';
    }
    if (elapsed.inMinutes < 60) {
      return '${elapsed.inMinutes}m';
    }
    if (elapsed.inHours < 48) {
      return '${elapsed.inHours}h';
    }
    return '${elapsed.inDays}d';
  }

  /// Serializes to `home_widget`-compatible primitives (strings + bool).
  Map<String, Object?> toWidgetData() => <String, Object?>{
    WidgetDataKeys.incidentId: incidentId,
    WidgetDataKeys.monitorId: monitorId,
    WidgetDataKeys.monitorName: monitorName ?? '',
    WidgetDataKeys.status: status,
    WidgetDataKeys.startedAt: startedAt ?? '',
    WidgetDataKeys.acknowledged: acknowledged,
    WidgetDataKeys.updatedAt: updatedAt.toIso8601String(),
  };
}
