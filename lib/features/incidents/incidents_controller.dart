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
  const IncidentsData({
    required this.incidents,
    required this.offline,
    this.syncedAt,
  });

  final List<Incident> incidents;
  final bool offline;

  /// When this snapshot was actually last read from the API (R4).
  ///
  /// Null when nothing has ever synced. It is never the time a cached row was
  /// read back: a fallback read reports the timestamp of the write that filled
  /// the cache, which is the honest age of what is on screen.
  final DateTime? syncedAt;
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
    // The shared read fence, captured alongside the revision. The revision alone
    // cannot see an acknowledgement whose cache write failed (it never moved), so
    // a feed read older than the confirmation would restore the pre-ack Open rows
    // for every surface at once.
    final int readGeneration = cache.incidentReadGeneration;
    try {
      final IncidentListResponse res = await api.listIncidents();
      // The instant this read succeeded, stored with the rows and reported
      // back to the screen (R4): a later cached read must not restate it.
      final DateTime readAt = DateTime.now();
      final bool applied = await cache.saveIncidentsIfCurrent(
        res.data.map(incidentToSnapshot).toList(),
        revision,
        session: session,
        readGeneration: readGeneration,
        syncedAt: readAt,
      );
      if (!applied) {
        // Whether the write was fenced by a newer mutation or by the session
        // ending, the response is stale. Checked outside the try so the
        // session error is not mistaken for a transport failure.
        _rejectEndedSession(cache, session);
        // The read itself succeeded: the rows are served from the cache because
        // a newer authoritative write already owns them, which is the same thing
        // the dashboard loader does here. Reporting this as offline would tell
        // the user the network is down while blocking every response action
        // ("Response actions need a connection") on a feed that is merely
        // serving the newest rows it holds.
        return await _reloadFromCache(session, offline: false);
      }
      return IncidentsData(
        incidents: res.data,
        offline: false,
        syncedAt: readAt,
      );
    } on DioException {
      final CachedList<CachedIncident> cached = await cache.getIncidents();
      // After the read, not only before it: a logout landing while the read was
      // in flight must not surface the previous session's rows.
      _rejectEndedSession(cache, session);
      if (cached.data.isEmpty) {
        rethrow;
      }
      return IncidentsData(
        incidents: _byRecency(cached),
        // The one case that really is offline: the request never got through.
        offline: true,
        syncedAt: cached.cachedAt,
      );
    }
  }

  /// Serves the newest rows the cache actually holds after a fenced list
  /// write, rather than the rejected API response.
  ///
  /// [session] is rechecked after the read so a logout that lands while the
  /// cache is being read rejects the load instead of returning old rows. The
  /// snapshot's own sync time comes back with it, so a fallback never claims
  /// to be a fresh read.
  /// [offline] is whether the fallback follows a transport failure. A fenced
  /// write is not one: the response arrived, and the cache holds the rows that
  /// superseded it.
  Future<IncidentsData> _reloadFromCache(
    int session, {
    required bool offline,
  }) async {
    final CachedList<CachedIncident> cached = await cache.getIncidents();
    _rejectEndedSession(cache, session);
    if (cached.data.isEmpty) {
      throw StateError('Incident cache is empty after a fenced write');
    }
    return IncidentsData(
      incidents: _byRecency(cached),
      offline: offline,
      syncedAt: cached.cachedAt,
    );
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

/// Incident detail content: the incident, its posted updates, and whether the
/// content came from the offline cache.
class IncidentDetailData {
  const IncidentDetailData({
    required this.incident,
    required this.updates,
    required this.offline,
    this.summarySyncedAt,
    this.updatesSyncedAt,
    this.savedOffline = true,
  });

  final Incident incident;
  final List<IncidentUpdate> updates;
  final bool offline;

  /// When the summary this detail was built from was actually last read from
  /// the API (R4). Null when that is unknown, which the screen states rather
  /// than papering over.
  final DateTime? summarySyncedAt;

  /// When [updates] were actually last read from the API (R4).
  ///
  /// Null when there is no saved detail snapshot at all. That is a different
  /// fact from a saved snapshot that was genuinely empty, and the screen keeps
  /// them apart.
  final DateTime? updatesSyncedAt;

  /// Whether this content reached the offline cache.
  ///
  /// False when a server-confirmed action could not be written (R4): the fact
  /// is real and stays on screen, but the app must not claim it will be there
  /// offline or after a relaunch, because it is not.
  final bool savedOffline;

  /// Whether a saved detail snapshot backs [updates].
  ///
  /// The offline screen only claims "no updates yet" for a saved snapshot: with
  /// nothing saved it has to say the updates are not available offline, because
  /// it does not know whether there were any.
  bool get hasSavedSnapshot => updatesSyncedAt != null && savedOffline;

  IncidentDetailData copyWith({Incident? incident}) => IncidentDetailData(
    incident: incident ?? this.incident,
    updates: updates,
    offline: offline,
    summarySyncedAt: summarySyncedAt,
    updatesSyncedAt: updatesSyncedAt,
    savedOffline: savedOffline,
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

/// A server-confirmed detail held for the current session (R4).
///
/// [epoch] scopes it to one login: an entry from an ended session is neither
/// served nor kept, so it can never reach the next account.
sealed class _ConfirmedEntry {
  const _ConfirmedEntry({
    required this.epoch,
    required this.confirmedAt,
    required this.cacheRevision,
    required this.detail,
  });

  /// Session epoch that produced this entry.
  final int epoch;

  /// When the server confirmed it — the instant of the read or the action.
  final DateTime confirmedAt;

  /// [CacheRepository.incidentRevision] once this entry had been written, so
  /// [_ApiIncidentDetailRepository._supersedesRow] can tell whether a newer
  /// write has landed since.
  final int cacheRevision;

  final IncidentDetailData detail;

  /// Whether this entry is a confirmed *action* (which may override the cache)
  /// rather than a plain read (which may not).
  bool get isAction => false;
}

/// Detail confirmed by a successful read. It is a copy of what the write
/// boundary just stored, so it never outranks the cached row.
final class _ConfirmedRead extends _ConfirmedEntry {
  const _ConfirmedRead({
    required super.epoch,
    required super.confirmedAt,
    required super.cacheRevision,
    required super.detail,
  });
}

/// Detail confirmed by a server-recorded action (an acknowledgement). The cache
/// may not know about it yet, so it may stand in for the cached row — while it
/// is the newer fact.
final class _ConfirmedAction extends _ConfirmedEntry {
  const _ConfirmedAction({
    required super.epoch,
    required super.confirmedAt,
    required super.cacheRevision,
    required this.actionSerial,
    required super.detail,
  });

  /// [_ApiIncidentDetailRepository._actionSerial] when the server confirmed
  /// this, which is what tells a read that started *before* the action from one
  /// that started after it.
  final int actionSerial;

  @override
  bool get isAction => true;
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

/// Loads incident detail from the API, persists the authoritative summary, the
/// updates and their real sync time to the offline cache (R4), and falls back
/// to that cache when the API is unreachable. Acknowledges via the API (no
/// offline path — the mutation needs the server; failures roll back the
/// optimistic update in the UI).
///
/// Escalate and snooze are server-only too: both change who gets notified,
/// so there is no offline fallback that could claim otherwise.
class ApiIncidentDetailRepository implements IncidentDetailRepository {
  ApiIncidentDetailRepository({required this.api, required this.cache});

  final UptrackApi api;
  final CacheRepository cache;

  /// Detail confirmed by a server response in this session, keyed by incident
  /// id.
  ///
  /// Two kinds of entry, and the difference decides whether memory may override
  /// the cache:
  ///
  /// * a plain successful **read** is a copy of what the write boundary already
  ///   put on disk, so it never outranks the cached row. Treating it as
  ///   authoritative is exactly what let a pre-resolution detail GET keep
  ///   serving an open incident after a newer list read had already written the
  ///   resolved row.
  /// * a confirmed **action** is a fact the server recorded that the cache may
  ///   not know yet, so it may stand in for the row — but only while it is
  ///   genuinely the newer fact.
  ///
  /// Every entry is tagged with the session epoch that produced it: this
  /// repository is a provider singleton that outlives
  /// [CacheRepository.clearAll], so an entry keyed only by incident id would
  /// hand the *next* account the previous account's detail the moment its GET
  /// fails. Entries from another epoch are dropped on read by [_readConfirmed].
  final Map<String, _ConfirmedEntry> _confirmed = <String, _ConfirmedEntry>{};

  /// How many server-confirmed actions this session has recorded.
  ///
  /// This is the explicit action/request fence, and it is deliberately
  /// independent of [CacheRepository.incidentRevision]: a write that fails
  /// *before* it reaches disk (a full volume, a locked database) never moves
  /// the revision, so a request that started before the action and lands after
  /// it would see the same revision and be taken for the newest thing there is.
  /// A read captures the counter before its request, and an entry stamped with a
  /// higher one is a fact that read cannot undo.
  int _actionSerial = 0;

  /// The confirmed action for [id], when one was recorded after [actionSerial]
  /// was captured and nothing newer has replaced it on disk.
  ///
  /// Returns the entry itself so the caller serves it. The revision check is
  /// [_supersedesRow], not a blanket precedence: a list read that resolved the
  /// incident *after* the action is the newer summary and still wins.
  Future<_ConfirmedEntry?> _newerConfirmedAction(
    String id,
    int session,
    int actionSerial,
  ) async {
    final _ConfirmedEntry? entry = _readConfirmed(id);
    // Checked before the row read: with no action newer than this request there
    // is nothing to compare, so the common path costs no extra query.
    if (entry is! _ConfirmedAction || entry.actionSerial <= actionSerial) {
      return null;
    }
    if (!_supersedesRow(entry, await _rowSyncedAt(id, session))) {
      return null;
    }
    return entry;
  }

  /// Whether a server-confirmed action for [id] landed after [actionSerial] was
  /// captured, whatever the cache revision says.
  ///
  /// Used at a write boundary that the earlier decision could not see: an action
  /// can be confirmed while a read's write is queued, and then that read is
  /// older than the action no matter which revision it captured.
  bool _actedAfter(String id, int actionSerial) {
    final _ConfirmedEntry? entry = _readConfirmed(id);
    return entry is _ConfirmedAction && entry.actionSerial > actionSerial;
  }

  /// The most recent server-confirmed detail for [id], but only when the
  /// server confirmed it in the session the cache is currently in.
  ///
  /// Epoch-scoped like the lookups inside [load]: after a logout
  /// [CacheRepository.clearAll] has advanced the epoch, so a value confirmed
  /// by the ended session is neither returned nor kept.
  IncidentDetailData? confirmedDetail(String id) => _readConfirmed(id)?.detail;

  _ConfirmedEntry? _readConfirmed(String id) {
    final _ConfirmedEntry? entry = _confirmed[id];
    if (entry == null) {
      return null;
    }
    if (entry.epoch != cache.sessionEpoch) {
      // Confirmed under a session that no longer exists: unusable here, so it
      // is dropped instead of lingering for the next session's failed load.
      _confirmed.remove(id);
      return null;
    }
    return entry;
  }

  /// Whether [entry] is newer than the cached summary row last written at
  /// [rowSyncedAt], and may therefore stand in for it.
  ///
  /// Both a cache revision and a wall-clock instant are required, because
  /// either alone has a blind spot: the revision advances on writes that never
  /// carried this incident's row (another list, a wipe), while a clock can tie
  /// or move backwards. An entry only wins if it is at least as new on *both*,
  /// and a row with no known write time never loses to memory.
  bool _supersedesRow(_ConfirmedEntry entry, DateTime? rowSyncedAt) {
    if (entry.cacheRevision < cache.incidentRevision) {
      // A newer write has landed since this entry was confirmed, so memory is
      // behind whatever is on disk now.
      return false;
    }
    if (rowSyncedAt == null) {
      return true;
    }
    return !entry.confirmedAt.isBefore(rowSyncedAt);
  }

  @override
  Future<IncidentDetailData> load(String id) async {
    // Captured before the request: a GET that started before an acknowledge
    // must not overwrite the authoritative acknowledgement when it lands, and
    // a response that arrives after a logout must not be remembered at all.
    //
    // Both fences are captured, because neither alone covers every ordering:
    // the revision only moves when a write reaches its body, so a write that
    // fails before that leaves a request that started before the action looking
    // current ([actionSerial] catches that), while the action serial alone would
    // let this read overwrite a resolution a list read has since stored
    // ([revision] catches that).
    final int revision = cache.incidentRevision;
    final int session = cache.sessionEpoch;
    final int actionSerial = _actionSerial;
    // Shared with the feed and the dashboard (see
    // [CacheRepository.incidentReadGeneration]): one acknowledgement invalidates
    // every incident read in flight, not just this screen's.
    final int readGeneration = cache.incidentReadGeneration;
    try {
      final IncidentDetail detail = await api.getIncident(id);
      if (session != cache.sessionEpoch) {
        // The session ended mid-request: this detail belongs to a session
        // that no longer exists, so it is never returned or remembered.
        throw const SessionEndedException();
      }
      // A server-confirmed action that landed while this request was in flight
      // is newer than this response — including when the action's own write
      // failed and the cache revision never moved. It is not automatically the
      // other way round either: an in-flight GET older than a later list read
      // must not resurrect the pre-list state, so the newest summary wins (see
      // [_newestSummary]).
      final _ConfirmedEntry? action = await _newerConfirmedAction(
        id,
        session,
        actionSerial,
      );
      if (action != null) {
        // This GET started before a confirmed mutation that nothing newer has
        // replaced: the acknowledged detail is the newest fact, and is not
        // overwritten.
        return action.detail;
      }
      final bool conflicted = revision != cache.incidentRevision;
      if (conflicted) {
        // Fallback is this response itself, flagged unsaved: it never reached
        // the cache, so it is only used when the cache holds no summary at all.
        final IncidentDetailData unsaved = IncidentDetailData(
          incident: detail.incident,
          updates: detail.updates,
          offline: false,
          summarySyncedAt: DateTime.now(),
          savedOffline: false,
        );
        return await _newestSummary(
              id,
              session,
              fallback: unsaved,
              // The server answered: whichever summary wins here came from a
              // successful read, so it is superseded, never offline.
              offline: false,
            ) ??
            unsaved;
      }
      // The instant this read succeeded. Written with the summary and the
      // updates in one fenced write and reported as the sync time — never a
      // "now" stamped onto a cached read later on.
      final DateTime readAt = DateTime.now();
      final bool stored = await cache.saveIncidentDetail(
        incidentToSnapshot(detail.incident),
        detail.updates,
        session: session,
        revision: revision,
        readGeneration: readGeneration,
        syncedAt: readAt,
        // Carried into the write boundary itself, because the decision above is
        // not the last word: this write sits in the cache queue, and an action
        // can be confirmed — and recorded — while it waits there. Evaluating the
        // fence where the write actually lands is what stops an older read from
        // being persisted over a newer fact; the call above already refused the
        // ordering this one is the backstop for.
        fence: () => !_actedAfter(id, actionSerial),
      );
      if (session != cache.sessionEpoch) {
        // The session ended while the write was queued: nothing was written for
        // a session that no longer exists, and this response is not ours to
        // show either.
        throw const SessionEndedException();
      }
      final IncidentDetailData fresh = IncidentDetailData(
        incident: detail.incident,
        updates: detail.updates,
        offline: false,
        summarySyncedAt: readAt,
        updatesSyncedAt: readAt,
        // Whether this response actually reached the cache. A fenced write did
        // not, so nothing about it may be promised for offline or relaunch.
        savedOffline: stored,
      );
      if (stored) {
        // Rechecked where the write actually completed, because an action can be
        // confirmed while this write sits in the cache queue — after the decision
        // above and after this request captured its fences. Then this response is
        // older than a fact the server already recorded, whatever the revision
        // says, and resolving keeps the newest-summary rule in one place: the
        // action when it is still the newest fact, the stored row when something
        // newer replaced it. It is also never remembered as [_ConfirmedRead],
        // which would erase the action it just lost to.
        if (_actedAfter(id, actionSerial)) {
          // Server-sourced on every branch here, so a superseded summary is
          // still online content and must not be reported as an offline
          // fallback that disables every response action.
          return await _newestSummary(
                id,
                session,
                fallback: fresh,
                offline: false,
              ) ??
              fresh;
        }
        // Remembered as a plain read: it is now on disk, so nothing is gained
        // by treating it as an override for later cache reads.
        _confirmed[id] = _ConfirmedRead(
          epoch: session,
          confirmedAt: readAt,
          cacheRevision: cache.incidentRevision,
          detail: fresh,
        );
        return fresh;
      }
      // Refused: a newer write landed while this one was queued (a list refresh,
      // or another detail read), or the fence above stopped holding at the store
      // boundary because an action was confirmed in the meantime. The response
      // is real but is not the newest summary, so resolve against the cache
      // instead of serving it stale.
      //
      // An action confirmed since this read started comes first: it is the newest
      // fact unless something replaced it, and it is served even when the cache
      // holds no row at all — nothing here was ever stored, so there is no cached
      // summary to prefer over it.
      final _ConfirmedEntry? confirmedAction = await _newerConfirmedAction(
        id,
        session,
        actionSerial,
      );
      if (confirmedAction != null) {
        return confirmedAction.detail;
      }
      final IncidentDetailData? resolved = await _newestSummary(
        id,
        session,
        fallback: fresh,
        // The write was refused, not the read: this response came from the
        // server, so it is superseded content rather than an offline one.
        offline: false,
      );
      // [fresh] is always a usable answer here, so this cannot be null; the
      // null case is spelled out rather than asserted away.
      return resolved ?? fresh;
    } on DioException catch (error, stackTrace) {
      final IncidentDetailData? savedData = await _newestSummary(
        id,
        session,
        fallback: null,
      );
      if (savedData != null) {
        return savedData;
      }
      // Nothing is saved for this incident, so there is no offline context to
      // report: re-raise the transport failure instead of describing an
      // incident the cache does not hold.
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// When the cached summary row for [id] was last written, or null when there
  /// is no row for it.
  ///
  /// [session] is rechecked after the read, so a logout that lands while the
  /// cache is being read rejects the load instead of answering for a session
  /// that no longer exists.
  Future<DateTime?> _rowSyncedAt(String id, int session) async {
    final DateTime? rowTime = await _rowSyncTime(id);
    _rejectEndedSession(cache, session);
    return rowTime;
  }

  /// The cached row's write time, looked up without any session check.
  Future<DateTime?> _rowSyncTime(String id) async {
    final CachedList<CachedIncident> cached = await cache.getIncidents();
    for (final CachedIncident candidate in cached.data) {
      if (candidate.id == id) {
        return candidate.cachedAt;
      }
    }
    return null;
  }

  /// The newest summary this session knows about for [id], with the updates
  /// that go with it (R4).
  ///
  /// One resolution used by both the offline fallback and the fenced-write
  /// paths, because they face the same question: the cached row may be newer
  /// than anything in memory (a list read resolved the incident after this
  /// screen loaded it), or memory may hold a confirmed action the cache has not
  /// seen yet. The rule is the same either way — **the newest summary wins**,
  /// and the updates come from whichever source backs it:
  ///
  /// * an action entry that genuinely supersedes the row owns both the summary
  ///   and the updates (including [IncidentDetailData.savedOffline], so an
  ///   unsaved acknowledgement is never reported as saved);
  /// * otherwise the cached row owns the summary, and the updates come from the
  ///   persisted detail snapshot with its own stored sync time — a list read
  ///   says nothing about what the updates look like, so they keep their own
  ///   provenance;
  /// * with no cached row at all, [fallback] is used when the caller has one,
  ///   and null otherwise (an offline load with nothing saved must report the
  ///   failed read rather than describe an incident the cache does not hold).
  ///
  /// [offline] is how the *served* content is labelled, and the caller owns
  /// that answer because only the caller knows where its content came from. A
  /// failed read leaves `true`: the row is all there is, and saying so is what
  /// keeps the response actions disabled rather than pretending a connection
  /// exists. A read the server answered leaves `false`: the winning summary
  /// came from a successful server read either way — this response or the
  /// cached row a newer list write replaced it with — so "newest summary wins"
  /// must not be read as "offline". Labelling those `true` claimed a dropped
  /// connection on a device that was talking to the server the whole time, and
  /// disabled acknowledge/escalate/snooze on a screen that had just loaded.
  Future<IncidentDetailData?> _newestSummary(
    String id,
    int session, {
    required IncidentDetailData? fallback,
    bool offline = true,
  }) async {
    // Scoped to the session, so a previous account's confirmation is never
    // served and a logout drops it (see [_readConfirmed]).
    final _ConfirmedEntry? confirmed = _readConfirmed(id);
    final CachedIncidentDetailSnapshot? saved = await cache.getIncidentDetail(
      id,
    );
    final CachedList<CachedIncident> cached = await cache.getIncidents();
    // Rechecked after both reads, not only before them: a check made before
    // them cannot see a logout that lands while they are in flight, and neither
    // the confirmed detail, nor the saved snapshot, nor a cached row may be
    // used after the session ended.
    _rejectEndedSession(cache, session);
    CachedIncident? row;
    for (final CachedIncident candidate in cached.data) {
      if (candidate.id == id) {
        row = candidate;
        break;
      }
    }
    if (row == null) {
      return fallback;
    }
    if (confirmed != null &&
        confirmed.isAction &&
        _supersedesRow(confirmed, row.cachedAt)) {
      return IncidentDetailData(
        incident: confirmed.detail.incident,
        updates: confirmed.detail.updates,
        offline: offline,
        // The action's own read time: the cached row may since have been
        // rewritten by a list read, which would overstate this content's
        // freshness.
        summarySyncedAt: confirmed.detail.summarySyncedAt ?? row.cachedAt,
        updatesSyncedAt: confirmed.detail.updatesSyncedAt,
        // Carried through rather than assumed: an action whose write failed
        // must not be described as saved once it is served from here.
        savedOffline: confirmed.detail.savedOffline,
      );
    }
    return IncidentDetailData(
      incident: incidentFromCached(row),
      // A missing snapshot stays missing: the screen says the updates are not
      // available offline rather than claiming the incident has none.
      updates: saved?.updates ?? const <IncidentUpdate>[],
      offline: offline,
      summarySyncedAt: row.cachedAt,
      updatesSyncedAt: saved?.syncedAt,
      savedOffline: saved != null,
    );
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
    // Every incident read already in flight — the feed's, the dashboard's, and this
    // screen's own earlier one — is now older than a fact the server has
    // recorded. Invalidated here, synchronously, **before** any storage is
    // attempted: whether this device's write succeeds, fails before its body, or
    // fails inside its transaction, none of those outcomes may leave an older
    // Open list free to overwrite the acknowledgement on any surface.
    //
    // Nothing is written and no sync time moves. This is not a read of anything,
    // so it must not look like one.
    cache.invalidateIncidentReads();
    // The instant the server's acknowledgement came back.
    final DateTime acknowledgedAt = DateTime.now();
    final IncidentDetailData refreshed = IncidentDetailData(
      incident: detail.incident,
      updates: detail.updates,
      offline: false,
      summarySyncedAt: acknowledgedAt,
      updatesSyncedAt: acknowledgedAt,
    );
    // Recorded **before** the write, not after it: the server has already
    // confirmed this, so the fence every read in flight checks has to see it
    // now. Waiting for this device to finish writing would leave a gap in which
    // an older read — whose own write is queued ahead of this one — persists the
    // pre-acknowledgement incident after the fact the server recorded.
    //
    // It is recorded as *not yet saved*, because it is not: only the store can
    // say that, and until it answers, nothing about offline or relaunch context
    // may be promised (the entry is upgraded below once the write is applied).
    final int actionSerial = ++_actionSerial;
    _recordConfirmedAction(
      id,
      _ConfirmedAction(
        epoch: session,
        confirmedAt: acknowledgedAt,
        cacheRevision: cache.incidentRevision,
        actionSerial: actionSerial,
        detail: IncidentDetailData(
          incident: detail.incident,
          updates: detail.updates,
          offline: false,
          summarySyncedAt: acknowledgedAt,
          updatesSyncedAt: acknowledgedAt,
          savedOffline: false,
        ),
      ),
    );
    // The server's answer is the authoritative acknowledgement and the newest
    // fact there is, so it takes the unfenced write: summary, updates and that
    // instant all land together. Persisting it before the screen invalidates
    // means a refresh that fails — or one that is fenced out by an in-flight
    // list load — still falls back to the acknowledged context instead of the
    // pre-acknowledgement cache state.
    bool stored = false;
    try {
      stored = await cache.saveIncidentDetail(
        incidentToSnapshot(detail.incident),
        detail.updates,
        session: session,
        // No revision fence: a confirmed mutation is the newest fact.
        revision: null,
        syncedAt: acknowledgedAt,
      );
    } on Object {
      // The server has already acknowledged. A local storage failure after that
      // is **not** a failed mutation: reporting it as one would show "could not
      // acknowledge" for an action that succeeded and invite a retry that would
      // acknowledge it twice.
      //
      // So the outcome is returned, not thrown, with [IncidentDetailData
      // .savedOffline] false: the acknowledgement is real, the screen's normal
      // success path runs and states the save problem, and nothing is promised
      // about offline or relaunch context. An ended session still throws —
      // there, this belongs to an account that no longer exists.
      if (session != cache.sessionEpoch) {
        throw const SessionEndedException();
      }
      // Same serial as the entry recorded before the write — the request fence
      // must not move twice for one acknowledgement — with the cache revision
      // read *now*: the failing write advanced it, and a later resolution on the
      // list must still be able to supersede this entry (see [_supersedesRow]).
      _recordConfirmedAction(
        id,
        _ConfirmedAction(
          epoch: session,
          confirmedAt: acknowledgedAt,
          cacheRevision: cache.incidentRevision,
          actionSerial: actionSerial,
          detail: IncidentDetailData(
            incident: detail.incident,
            updates: detail.updates,
            offline: false,
            summarySyncedAt: acknowledgedAt,
            updatesSyncedAt: acknowledgedAt,
            // Nothing reached the cache, so nothing may be promised about
            // offline or relaunch context for this incident.
            savedOffline: false,
          ),
        ),
      );
      return _confirmed[id]!.detail;
    }
    if (session != cache.sessionEpoch || !stored) {
      // The session ended while the write was queued: the write was refused,
      // so nothing is remembered for a session that no longer exists.
      throw const SessionEndedException();
    }
    // Stored, so the entry it was recorded as finally earns the saved claim.
    // The revision is read here for the same reason as in the catch above.
    _recordConfirmedAction(
      id,
      _ConfirmedAction(
        epoch: session,
        confirmedAt: acknowledgedAt,
        cacheRevision: cache.incidentRevision,
        actionSerial: actionSerial,
        detail: refreshed,
      ),
    );
    return refreshed;
  }

  /// Keeps [entry] as the newest confirmed fact for [id], unless a newer action
  /// has already been recorded.
  ///
  /// The acknowledgement path writes this entry twice — once the moment the
  /// server confirms, and again once the write settles — and a read landing in
  /// between must not lose the newer of the two.
  void _recordConfirmedAction(String id, _ConfirmedAction entry) {
    final _ConfirmedEntry? current = _confirmed[id];
    if (current is _ConfirmedAction &&
        current.actionSerial > entry.actionSerial) {
      return;
    }
    _confirmed[id] = entry;
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
