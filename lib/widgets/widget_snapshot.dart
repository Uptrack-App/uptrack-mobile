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

  /// Set to [feedAllClear] only when a complete feed proved that nothing is
  /// open; removed by any incident write and by logout. The iOS widget says
  /// "No ongoing incidents" only with this mark. Without it (signed out, new
  /// install, never synced) the widget asks the user to open the app, so it
  /// never claims an all-clear it does not know. Not in [all]: an all-clear
  /// write clears [all] and then sets this key.
  static const String feedState = '${prefix}feed_state';
  static const String feedAllClear = 'all_clear';

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

/// A cached incident row paired with the instant its data was **actually**
/// last fetched (R5).
///
/// The pairing is the point: the cache persists both facts separately (the row
/// and R4's `cachedAt` sync stamp) and the widget must report the one the
/// server gave it. Keeping them in one value makes "row without a known sync
/// time" a representable, testable state instead of an accident that gets
/// papered over with `DateTime.now()`.
class WidgetIncidentCandidate {
  const WidgetIncidentCandidate({required this.row, this.syncedAt});

  final IncidentSnapshot row;

  /// When this row was actually last fetched from the API.
  ///
  /// Null when the cache does not say — which is *unknown freshness*, never
  /// "fresh now". A cached read must never renew it (R5).
  final DateTime? syncedAt;

  /// Whether this incident may still be shown: not resolved, by either signal.
  ///
  /// `status` and `resolved_at` are both consulted because the server can land
  /// either first; treating a status-only resolution as still-open would leave
  /// a dead incident on the home screen.
  bool get isEligible =>
      row.resolvedAt == null && row.status != WidgetSnapshot.resolvedStatus;

  /// The widget snapshot for this row, carrying [syncedAt] as its freshness.
  WidgetSnapshot toSnapshot() =>
      WidgetSnapshot.fromCache(row, syncedAt: syncedAt);
}

/// One load of the incident set, plus the provenance needed to tell
/// "nothing is open" from "we do not know" (R5).
///
/// The distinction is not cosmetic. Three different states all look like an
/// empty list, and treating any of them as a fact would blank the home screen —
/// claiming an all-clear on the strength of data nobody enumerated:
///
/// - an uninitialized cache (never synced, or wiped at logout);
/// - a failed read;
/// - a **partial** cache: rows written by a detail read or an action upsert with
///   no list sync behind them, so the set says nothing about what else is open.
///
/// That last one is why this is not derived from [candidates] being non-empty. A
/// cache holding one resolved row is a positive statement about that row and
/// *nothing* about the incidents that were never written, and clearing on it is
/// how the widget ends up claiming "no ongoing incidents" while some are.
///
/// So a load may only *clear* the widget when it can prove the feed was
/// enumerated: [syncedAt] (the collection's own sync instant, written only by a
/// completed list sync) or an explicit [enumeratesAll] from a loader that cannot
/// report one. Selecting an open candidate needs no such proof — showing a real
/// ongoing incident is never the dangerous direction.
class WidgetCandidateLoad {
  const WidgetCandidateLoad({
    required this.candidates,
    this.syncedAt,
    this.enumeratesAll = false,
  });

  final List<WidgetIncidentCandidate> candidates;

  /// When the underlying collection last completed a successful sync; null when
  /// it has never synced, or when the loader cannot report it.
  ///
  /// Deliberately the collection's own sync instant (the cache's `cache_meta`
  /// row), not a row stamp: a per-row `cachedAt` says when one incident was
  /// fetched, never that the *list* was enumerated.
  final DateTime? syncedAt;

  /// Explicit completeness, for loaders that cannot report a sync instant (the
  /// plain row-list seam). Never derived from [candidates] being non-empty, and
  /// never accompanied by a fabricated [syncedAt]: it is a claim about coverage,
  /// not a freshness time.
  final bool enumeratesAll;

  /// Whether this load enumerated the whole incident collection.
  bool get isComplete => enumeratesAll || syncedAt != null;

  /// Whether any candidate is still eligible to be shown.
  bool get hasOpen =>
      candidates.any((WidgetIncidentCandidate c) => c.isEligible);

  /// The only state in which the widget may be cleared for "nothing open".
  bool get isKnownAllClear => isComplete && !hasOpen;
}

/// Incident-summary snapshot backing the home widget and the Live Activity
/// content: status, elapsed time anchor, and monitor name.
///
/// Pure data — built from the Drift cache ([IncidentSnapshot]), the API
/// ([Incident]), or merged with a push ([PushMessage]); serialized to
/// `home_widget` string/bool primitives via [toWidgetData].
///
/// **Freshness provenance (R5):** [updatedAt] is the instant the underlying
/// data was actually fetched, and it is nullable on purpose. Nothing here ever
/// substitutes `DateTime.now()` — reading a cached row, rebuilding a stored
/// snapshot or merging a push are not syncs, so all three leave a missing
/// timestamp missing instead of claiming the widget is current.
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.incidentId,
    required this.monitorId,
    required this.status,
    this.updatedAt,
    this.monitorName,
    this.startedAt,
    this.acknowledged = false,
  });

  /// Status the API uses for a resolved incident.
  static const String resolvedStatus = 'resolved';

  /// Builds a snapshot from a Drift cache row.
  ///
  /// [syncedAt] is the row's real sync stamp; omitting it yields a snapshot
  /// with unknown freshness rather than a fabricated "now".
  factory WidgetSnapshot.fromCache(
    IncidentSnapshot row, {
    DateTime? syncedAt,
  }) => WidgetSnapshot(
    incidentId: row.id,
    monitorId: row.monitorId,
    monitorName: row.monitorName,
    status: row.status,
    startedAt: row.startedAt,
    acknowledged: row.acknowledgedAt != null,
    updatedAt: syncedAt,
  );

  /// Builds a snapshot from an API incident.
  factory WidgetSnapshot.fromIncident(
    Incident incident, {
    DateTime? syncedAt,
  }) => WidgetSnapshot(
    incidentId: incident.id,
    monitorId: incident.monitorId,
    monitorName: incident.monitorName,
    status: incident.status,
    startedAt: incident.startedAt,
    acknowledged: incident.isAcknowledged,
    updatedAt: syncedAt,
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
    // An absent or unparseable timestamp means unknown freshness. It must not
    // become `DateTime.now()`: that would make a stale cached read look like a
    // sync the app never performed (R5).
    DateTime? updatedAt;
    if (rawUpdated is String) {
      updatedAt = DateTime.tryParse(rawUpdated);
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
  ///
  /// [updatedAt] is carried over untouched: a push announcement is not a sync,
  /// so merging one cannot make the widget look fresher than the data it
  /// displays actually is (R5).
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
      updatedAt: updatedAt,
    );
  }

  final String incidentId;
  final String monitorId;
  final String? monitorName;
  final String status;
  final String? startedAt;
  final bool acknowledged;

  /// When this incident's data was actually last fetched; null when unknown.
  final DateTime? updatedAt;

  /// This snapshot stamped with [syncedAt], everything else preserved.
  ///
  /// Used when the authoritative row carries no sync time of its own but the
  /// stored copy of the *same* incident does: the older stamp is still the last
  /// known fetch, and discarding a real one would leave the widget less
  /// informed than it is. Only ever applied to the same incident — carrying a
  /// stamp over to a different one would misattribute it.
  WidgetSnapshot withSyncStamp(DateTime? syncedAt) => WidgetSnapshot(
    incidentId: incidentId,
    monitorId: monitorId,
    monitorName: monitorName,
    status: status,
    startedAt: startedAt,
    acknowledged: acknowledged,
    updatedAt: syncedAt,
  );

  /// Whether the tracked incident resolved (the widget should clear).
  bool get isResolved => status == resolvedStatus;

  /// Whether the freshness of this snapshot is genuinely unknown.
  ///
  /// Distinct from "fresh": an unknown stamp must never render as, or be
  /// compared as, current data (R5).
  bool get freshnessUnknown => updatedAt == null;

  /// Age of the underlying data at [now], or null when the sync time is
  /// unknown. Negative ages (a stamp in the future) clamp to zero.
  Duration? syncAge(DateTime now) {
    final DateTime? at = updatedAt;
    if (at == null) {
      return null;
    }
    final Duration age = now.difference(at);
    return age.isNegative ? Duration.zero : age;
  }

  /// Whether the data is older than [threshold] at [now].
  ///
  /// False when the sync time is unknown — an unknown stamp is not fresh data,
  /// but this answers "is the known data old", and the widget renders
  /// unknown freshness separately rather than guessing an age.
  bool isStaleAt(DateTime now, Duration threshold) {
    final Duration? age = syncAge(now);
    return age != null && age > threshold;
  }

  /// Display name for the widget title (falls back to the incident id).
  String get displayName {
    final String? trimmed = monitorName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return 'Incident $incidentId';
  }

  /// Elapsed time since the incident started (falls back to [updatedAt]
  /// when no start timestamp is known); null when neither is usable — an
  /// unknown anchor is reported as unknown, not as zero.
  Duration? elapsedSince(DateTime now) {
    final String? anchor = startedAt;
    if (anchor == null || anchor.isEmpty) {
      return syncAge(now);
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
  ///
  /// An unknown [updatedAt] is written as an empty string, which the native
  /// provider renders as "no freshness information" instead of guessing one.
  Map<String, Object?> toWidgetData() => <String, Object?>{
    WidgetDataKeys.incidentId: incidentId,
    WidgetDataKeys.monitorId: monitorId,
    WidgetDataKeys.monitorName: monitorName ?? '',
    WidgetDataKeys.status: status,
    WidgetDataKeys.startedAt: startedAt ?? '',
    WidgetDataKeys.acknowledged: acknowledged,
    WidgetDataKeys.updatedAt: updatedAt?.toIso8601String() ?? '',
  };
}

/// Decides whether a resolved snapshot may be written to persistent widget
/// storage. Injectable so the single post-R4 integration owner can wire the
/// authoritative session-mode signal without this file changing again.
typedef WidgetPublishGate = bool Function(WidgetSnapshot snapshot);

/// Whether [id] belongs to the in-app demo session's fixtures.
///
/// The demo session serves sample monitors/incidents from an in-process
/// `HttpClientAdapter` but shares the app's Drift database, so its rows are
/// indistinguishable from real ones once cached. Server ids are UUIDs, which
/// is why a `demo` prefix is a safe marker here.
bool isSampleFixtureId(String id) => id.startsWith(WidgetSampleGuard.idPrefix);

/// Widget-local guard keeping sample/demo rows off the live home screen (R5).
///
/// This is defence in depth for the widget store only: it refuses to *write*
/// fixtures, and it does not prove that any caller outside `lib/widgets` keeps
/// demo state out of the cache. It also never calls the network — the demo path
/// is in-process by construction.
abstract final class WidgetSampleGuard {
  /// Marker prefix of the demo session's fixture ids (`demo-incident`,
  /// `demo-api`, …; see `lib/features/auth/demo_session.dart`).
  static const String idPrefix = 'demo';

  /// Default [WidgetPublishGate]: live, signed-in data only.
  static bool allow(WidgetSnapshot snapshot) => !isSampleSnapshot(snapshot);

  /// Whether [snapshot] is demo fixture data.
  static bool isSampleSnapshot(WidgetSnapshot snapshot) =>
      isSampleFixtureId(snapshot.incidentId) ||
      (snapshot.monitorId.isNotEmpty && isSampleFixtureId(snapshot.monitorId));
}
