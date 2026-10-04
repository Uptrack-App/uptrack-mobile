import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/incident.dart';
import '../../api/uptrack_api.dart';
import '../../data/local/app_database.dart';
import '../../data/local/cache_repository.dart';
import '../../data/local/database_providers.dart';
import '../auth/auth_controller.dart';
import '../dashboard/dashboard_controller.dart'
    show
        compareOutstanding,
        dashboardProvider,
        incidentFromCached,
        incidentToSnapshot;

/// Feed filter for the incident list.
enum IncidentStatusFilter {
  all,
  open,
  needsAcknowledgement;

  /// Short label for the filter control. Written out rather than abbreviated so
  /// the response queue is unambiguous at large text sizes.
  String get label => switch (this) {
    IncidentStatusFilter.all => 'All',
    IncidentStatusFilter.open => 'Open',
    IncidentStatusFilter.needsAcknowledgement => 'Needs acknowledgement',
  };

  /// Stable query value, so a deep link (`/incidents?filter=…`) opens exactly
  /// the view the link on the dashboard described.
  String get queryValue => switch (this) {
    IncidentStatusFilter.all => 'all',
    IncidentStatusFilter.open => 'open',
    IncidentStatusFilter.needsAcknowledgement => 'needs-acknowledgement',
  };
}

/// The filter a `?filter=` query asks for, or null when it names none (an
/// unknown value falls back to the screen's own default rather than failing).
IncidentStatusFilter? incidentFilterFromQuery(String? value) {
  if (value == null) {
    return null;
  }
  for (final IncidentStatusFilter filter in IncidentStatusFilter.values) {
    if (filter.queryValue == value) {
      return filter;
    }
  }
  return null;
}

/// Client-side filter over the loaded incidents: open means still ongoing
/// (`resolved_at` unset); needs acknowledgement means ongoing and not yet
/// acknowledged.
///
/// Filtering is client-side (not the API `status` param) so it keeps working
/// on the offline cache fallback.
List<Incident> filterIncidents(
  List<Incident> incidents, {
  IncidentStatusFilter status = IncidentStatusFilter.all,
}) {
  if (status == IncidentStatusFilter.all) {
    return incidents.toList();
  }
  if (status == IncidentStatusFilter.needsAcknowledgement) {
    // Same order as the dashboard's response queue: oldest outstanding first.
    return incidents
        .where((Incident i) => i.isOngoing && !i.isAcknowledged)
        .toList()
      ..sort(compareOutstanding);
  }
  return incidents.where((Incident i) => i.isOngoing).toList();
}

/// Empty-state copy for [filter].
///
/// The needs-acknowledgement filter never falls back to "No open incidents":
/// acknowledged-but-open incidents are real, so that copy would be a lie when
/// one exists and the queue is simply empty.
String incidentsEmptyMessage(
  IncidentStatusFilter filter, {
  required bool hasAny,
}) => switch (filter) {
  IncidentStatusFilter.needsAcknowledgement =>
    hasAny ? 'No incidents need acknowledgement.' : 'No incidents.',
  IncidentStatusFilter.open => 'No open incidents.',
  IncidentStatusFilter.all => 'No incidents.',
};

/// Incident feed content: rows plus whether they came from the offline cache.
class IncidentsData {
  const IncidentsData({required this.incidents, required this.offline});

  final List<Incident> incidents;
  final bool offline;
}

/// Source of [IncidentsData] (faked in widget tests).
abstract class IncidentsRepository {
  Future<IncidentsData> load();
}

/// Throws when the session that captured [session] is no longer the cache's
/// session, meaning whatever was read belongs to a session that has ended.
///
/// Called again *after* every awaited cache read, not only before it: a check
/// made before the read cannot observe a logout that lands while the read is in
/// flight (TOCTOU), and the rows it returns would then reach the screen after
/// the session they belong to was wiped.
void _rejectEndedSession(CacheRepository cache, int session) {
  if (session != cache.sessionEpoch) {
    throw const SessionEndedException();
  }
}

/// Loads the incident feed from the API, persists it to the offline cache,
/// and falls back to the cache when the API is unreachable. Rethrows the
/// API error when the cache is empty too.
class ApiIncidentsRepository implements IncidentsRepository {
  ApiIncidentsRepository({required this.api, required this.cache});

  final UptrackApi api;
  final CacheRepository cache;

  @override
  Future<IncidentsData> load() async {
    // Captured before the request: an acknowledge that lands while this is in
    // flight wins the cache write, so this response cannot restore a stale
    // unacknowledged row. [session] covers the logout case.
    final int revision = cache.incidentRevision;
    final int session = cache.sessionEpoch;
    try {
      final IncidentListResponse res = await api.listIncidents();
      final bool applied = await cache.saveIncidentsIfCurrent(
        res.data.map(incidentToSnapshot).toList(),
        revision,
        session: session,
      );
      if (!applied) {
        // Whether the write was fenced by a newer mutation or by the session
        // ending, the response is stale. Checked outside the try so the
        // session error is not mistaken for a transport failure.
        _rejectEndedSession(cache, session);
        return await _reloadFromCache(session);
      }
      return IncidentsData(incidents: res.data, offline: false);
    } on DioException {
      final CachedList<CachedIncident> cached = await cache.getIncidents();
      // After the read, not only before it: a logout landing while the read was
      // in flight must not surface the previous session's rows.
      _rejectEndedSession(cache, session);
      if (cached.data.isEmpty) {
        rethrow;
      }
      return IncidentsData(incidents: _byRecency(cached), offline: true);
    }
  }

  /// Serves the newest rows the cache actually holds after a fenced list
  /// write, rather than the rejected API response.
  ///
  /// [session] is rechecked after the read so a logout that lands while the
  /// cache is being read rejects the load instead of returning old rows.
  Future<IncidentsData> _reloadFromCache(int session) async {
    final CachedList<CachedIncident> cached = await cache.getIncidents();
    _rejectEndedSession(cache, session);
    if (cached.data.isEmpty) {
      throw StateError('Incident cache is empty after a fenced write');
    }
    return IncidentsData(incidents: _byRecency(cached), offline: true);
  }

  static List<Incident> _byRecency(CachedList<CachedIncident> cached) {
    final List<CachedIncident> byRecency = cached.data.toList()
      ..sort(
        (CachedIncident a, CachedIncident b) =>
            b.insertedAt.compareTo(a.insertedAt),
      );
    return byRecency.map(incidentFromCached).toList();
  }
}

final Provider<IncidentsRepository> incidentsRepositoryProvider =
    Provider<IncidentsRepository>(
      (Ref ref) => ApiIncidentsRepository(
        api: ref.watch(uptrackApiProvider),
        cache: ref.watch(cacheRepositoryProvider),
      ),
    );

final FutureProvider<IncidentsData> incidentsProvider =
    FutureProvider<IncidentsData>(
      (Ref ref) => ref.watch(incidentsRepositoryProvider).load(),
      // No automatic retry: a failed load falls back to the offline cache
      // inside the repository, and any remaining error is retried
      // explicitly via the Retry button / pull-to-refresh.
      retry: (int retryCount, Object error) => null,
    );

/// User-facing message for an incident-feed load failure (prefers the
/// server's `error` field when present).
String incidentsErrorMessage(Object err) {
  if (err is DioException) {
    final Object? data = err.response?.data;
    if (data is Map<String, Object?>) {
      final Object? serverError = data['error'];
      if (serverError is String && serverError.isNotEmpty) {
        return serverError;
      }
    }
    if (err.response?.statusCode == 401) {
      return 'Session expired. Sign in again.';
    }
  }
  return 'Could not load incidents. Check your connection and try again.';
}

/// Incident detail content: the incident, its posted updates, and whether
/// the incident row came from the offline cache (updates are API-only —
/// the cache stores incident rows but no updates table, so offline detail
/// shows an empty updates list).
class IncidentDetailData {
  const IncidentDetailData({
    required this.incident,
    required this.updates,
    required this.offline,
  });

  final Incident incident;
  final List<IncidentUpdate> updates;
  final bool offline;

  IncidentDetailData copyWith({Incident? incident}) => IncidentDetailData(
    incident: incident ?? this.incident,
    updates: updates,
    offline: offline,
  );
}

/// Optimistic acknowledge update: marks the incident acknowledged immediately
/// (the caller sends the request and rolls back to the previous data — by
/// invalidating the provider — when it fails). Already-acknowledged
/// incidents are returned unchanged so a stale optimistic flag never
/// overwrites the server timestamp after a refetch.
IncidentDetailData optimisticAcknowledge(
  IncidentDetailData data, {
  DateTime? now,
}) {
  if (data.incident.isAcknowledged) {
    return data;
  }
  return data.copyWith(
    incident: data.incident.copyWith(
      acknowledgedAt: (now ?? DateTime.now().toUtc()).toIso8601String(),
    ),
  );
}

/// Source of [IncidentDetailData] (faked in widget tests).
abstract class IncidentDetailRepository {
  Future<IncidentDetailData> load(String id);

  /// Acknowledges the incident and returns the refreshed detail.
  Future<IncidentDetailData> acknowledge(String id);

  /// Fires the monitor's remaining escalation policy steps now
  /// (`POST /api/incidents/{id}/escalate`).
  Future<EscalateResult> escalate(String id);

  /// Suppresses this user's mobile push alerts for one monitor
  /// (`POST /api/monitors/{id}/snooze`) and returns when they resume.
  Future<SnoozeResult> snooze(String monitorId);
}

/// Loads incident detail from the API with an offline row fallback, and
/// acknowledges via the API (no offline path — the mutation needs the
/// server; failures roll back the optimistic update in the UI).
///
/// Escalate and snooze are server-only too: both change who gets notified,
/// so there is no offline fallback that could claim otherwise.
class ApiIncidentDetailRepository implements IncidentDetailRepository {
  ApiIncidentDetailRepository({required this.api, required this.cache});

  final UptrackApi api;
  final CacheRepository cache;

  /// Authoritative detail confirmed by a server response, keyed by incident
  /// id and tagged with the session epoch that confirmed it. [load] prefers
  /// it over the cache row so a failed refresh after an action cannot revert
  /// a fact the server already confirmed.
  ///
  /// The epoch tag is what keeps it safe across sessions: this repository is a
  /// provider singleton that outlives [CacheRepository.clearAll], so a map
  /// keyed only by incident id would hand the *next* account the previous
  /// account's confirmed detail the moment its GET fails. Entries confirmed
  /// under a different epoch are dropped on read by [_readConfirmed].
  final Map<String, ({int epoch, IncidentDetailData detail})> _confirmed =
      <String, ({int epoch, IncidentDetailData detail})>{};

  /// The most recent server-confirmed detail for [id], but only when the
  /// server confirmed it in the session the cache is currently in.
  ///
  /// Epoch-scoped like the lookups inside [load]: after a logout
  /// [CacheRepository.clearAll] has advanced the epoch, so a value confirmed
  /// by the ended session is neither returned nor kept.
  IncidentDetailData? confirmedDetail(String id) => _readConfirmed(id);

  IncidentDetailData? _readConfirmed(String id) {
    final ({int epoch, IncidentDetailData detail})? entry = _confirmed[id];
    if (entry == null) {
      return null;
    }
    if (entry.epoch != cache.sessionEpoch) {
      // Confirmed under a session that no longer exists: unusable here, so it
      // is dropped instead of lingering for the next session's failed load.
      _confirmed.remove(id);
      return null;
    }
    return entry.detail;
  }

  @override
  Future<IncidentDetailData> load(String id) async {
    // Captured before the request: a GET that started before an acknowledge
    // must not overwrite the authoritative acknowledgement when it lands, and
    // a response that arrives after a logout must not be remembered at all.
    final int revision = cache.incidentRevision;
    final int session = cache.sessionEpoch;
    try {
      final IncidentDetail detail = await api.getIncident(id);
      final IncidentDetailData fresh = IncidentDetailData(
        incident: detail.incident,
        updates: detail.updates,
        offline: false,
      );
      if (session != cache.sessionEpoch) {
        // The session ended mid-request: this detail belongs to a session
        // that no longer exists, so it is never returned or remembered.
        throw const SessionEndedException();
      }
      final IncidentDetailData? confirmed = _readConfirmed(id);
      if (confirmed != null && revision != cache.incidentRevision) {
        // This GET started before a confirmed mutation, so it is the older
        // fact: the acknowledged detail wins and is not overwritten.
        return confirmed;
      }
      _confirmed[id] = (epoch: session, detail: fresh);
      return fresh;
    } on DioException {
      _rejectEndedSession(cache, session);
      // A server-confirmed action beats the cached row: the cache may be
      // older than the acknowledgement the API already returned. Scoped to
      // the session, so a previous account's confirmation is never served.
      final IncidentDetailData? confirmed = _readConfirmed(id);
      if (confirmed != null) {
        return IncidentDetailData(
          incident: confirmed.incident,
          updates: confirmed.updates,
          offline: true,
        );
      }
      final CachedList<CachedIncident> cached = await cache.getIncidents();
      // Rechecked after the read: the check above cannot see a logout that
      // lands while the cache read is in flight, and neither the confirmed
      // detail nor this row may be used after the session ended.
      _rejectEndedSession(cache, session);
      CachedIncident? row;
      for (final CachedIncident candidate in cached.data) {
        if (candidate.id == id) {
          row = candidate;
          break;
        }
      }
      if (row == null) {
        rethrow;
      }
      return IncidentDetailData(
        incident: incidentFromCached(row),
        updates: const <IncidentUpdate>[],
        offline: true,
      );
    }
  }

  @override
  Future<IncidentDetailData> acknowledge(String id) async {
    // Captured before the request: if the session ends while this is in
    // flight, the late answer is neither returned as state nor written to the
    // cache that logout just wiped.
    final int session = cache.sessionEpoch;
    final IncidentDetail detail = await api.acknowledgeIncident(id);
    if (session != cache.sessionEpoch) {
      throw const SessionEndedException();
    }
    final IncidentDetailData refreshed = IncidentDetailData(
      incident: detail.incident,
      updates: detail.updates,
      offline: false,
    );
    // The server's answer is the authoritative acknowledgement. Persist it
    // before the screen invalidates, so a refresh that fails or is fenced out
    // by an in-flight list load still falls back to an acknowledged row
    // instead of the pre-acknowledgement cache state.
    final bool stored = await cache.upsertIncident(
      incidentToSnapshot(detail.incident),
      session: session,
    );
    if (session != cache.sessionEpoch || !stored) {
      // The session ended while the write was queued: the row was refused,
      // so nothing is remembered for a session that no longer exists.
      throw const SessionEndedException();
    }
    _confirmed[id] = (epoch: session, detail: refreshed);
    return refreshed;
  }

  @override
  Future<EscalateResult> escalate(String id) => api.escalateIncident(id);

  @override
  Future<SnoozeResult> snooze(String monitorId) => api.snoozeMonitor(monitorId);
}

final Provider<IncidentDetailRepository> incidentDetailRepositoryProvider =
    Provider<IncidentDetailRepository>(
      (Ref ref) => ApiIncidentDetailRepository(
        api: ref.watch(uptrackApiProvider),
        cache: ref.watch(cacheRepositoryProvider),
      ),
    );

/// Detail content for one incident.
final incidentDetailProvider =
    FutureProvider.family<IncidentDetailData, String>(
      (Ref ref, String id) =>
          ref.watch(incidentDetailRepositoryProvider).load(id),
      retry: (int retryCount, Object error) => null,
    );

/// Invalidates every surface a successful response action can change: the
/// open incident detail, the incident feed and the dashboard.
///
/// Acknowledgement and escalation are facts the user can see in all three,
/// so leaving any of them stale would contradict the action that just
/// succeeded. Refresh failures stay visible: the invalidated providers fall
/// back to their offline cache or surface their own retryable error state.
void invalidateIncidentSurfaces(WidgetRef ref, String incidentId) {
  ref.invalidate(incidentDetailProvider(incidentId));
  ref.invalidate(incidentsProvider);
  ref.invalidate(dashboardProvider);
}

/// Builds a user-facing message for a failed response mutation. A 401 is
/// reported as an expired session before the body is consulted, so an
/// action that never reached the server is never described as a server
/// error; otherwise the server's `error` field wins when present.
String responseActionErrorMessage(Object err, String fallback) {
  if (err is DioException) {
    if (err.response?.statusCode == 401) {
      return 'Session expired. Sign in again, then retry this action.';
    }
    final Object? data = err.response?.data;
    if (data is Map<String, Object?>) {
      final Object? serverError = data['error'];
      if (serverError is String && serverError.isNotEmpty) {
        return serverError;
      }
    }
  }
  return fallback;
}

/// User-facing message for an acknowledge failure (prefers the server's
/// `error` field when present).
String acknowledgeErrorMessage(Object err) => responseActionErrorMessage(
  err,
  'Could not acknowledge this incident. Try again.',
);

/// User-facing message for an escalate failure.
String escalateErrorMessage(Object err) => responseActionErrorMessage(
  err,
  'Could not escalate this incident. Try again.',
);

/// User-facing message for a snooze failure.
String snoozeErrorMessage(Object err) =>
    responseActionErrorMessage(err, 'Could not snooze your alerts. Try again.');
