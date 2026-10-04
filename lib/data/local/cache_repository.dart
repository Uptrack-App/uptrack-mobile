import 'dart:async';

import 'package:drift/drift.dart';

import '../../api/models/monitor.dart';
import 'app_database.dart';

/// Cache-freshness keys (mirrors the `cache_meta` rows).
const String kMonitorsCacheKey = 'monitors';
const String kIncidentsCacheKey = 'incidents';

/// Cache key for one monitor's check history.
String checksCacheKey(String monitorId) => 'checks_$monitorId';

/// Thrown when a request's response arrived after the session ended, so the
/// screen reports a failed load instead of showing rows or state that belong
/// to a session that no longer exists.
class SessionEndedException implements Exception {
  const SessionEndedException();

  @override
  String toString() => 'SessionEndedException: the cache session was cleared';
}

/// A cached list plus the timestamp it was last refreshed from the API.
class CachedList<T> {
  const CachedList({
    required this.data,
    required this.cachedAt,
    required this.isStale,
  });

  final List<T> data;
  final DateTime? cachedAt;
  final bool isStale;
}

/// Incident fields cached offline (subset of `IncidentOut`).
class IncidentSnapshot {
  const IncidentSnapshot({
    required this.id,
    required this.monitorId,
    this.monitorName,
    required this.status,
    this.startedAt,
    this.resolvedAt,
    this.acknowledgedAt,
    required this.insertedAt,
  });

  final String id;
  final String monitorId;
  final String? monitorName;
  final String status;
  final String? startedAt;
  final String? resolvedAt;
  final String? acknowledgedAt;
  final String insertedAt;

  CachedIncidentsCompanion toCompanion() => CachedIncidentsCompanion.insert(
    id: id,
    monitorId: monitorId,
    monitorName: Value<String?>(monitorName),
    status: status,
    startedAt: Value<String?>(startedAt),
    resolvedAt: Value<String?>(resolvedAt),
    acknowledgedAt: Value<String?>(acknowledgedAt),
    insertedAt: insertedAt,
  );
}

/// Check fields cached offline (subset of `CheckOut`).
class CheckSnapshot {
  const CheckSnapshot({
    required this.monitorId,
    required this.status,
    required this.responseTime,
    required this.statusCode,
    required this.checkedAt,
    this.errorMessage,
  });

  final String monitorId;
  final String status;
  final int responseTime;
  final int statusCode;
  final String checkedAt;
  final String? errorMessage;

  CachedChecksCompanion toCompanion() => CachedChecksCompanion.insert(
    monitorId: monitorId,
    status: status,
    responseTime: responseTime,
    statusCode: statusCode,
    checkedAt: checkedAt,
    errorMessage: Value<String?>(errorMessage),
  );
}

/// Read-through cache over [AppDatabase] with per-collection
/// staleness timestamps.
class CacheRepository {
  CacheRepository(this._db, {this._staleAfter = const Duration(minutes: 5)});

  final AppDatabase _db;
  final Duration _staleAfter;

  /// Monotonic fence for incident-row writes.
  ///
  /// A list load captures [incidentRevision] *before* its network call and
  /// only writes if the revision is unchanged ([saveIncidentsIfCurrent]); a
  /// mutation that learned something new ([upsertIncident]) bumps it. That
  /// way a slow `GET /api/incidents` that started before an acknowledge
  /// cannot land afterwards and resurrect a pre-acknowledgement row in the
  /// offline cache.
  int _incidentRevision = 0;

  /// Revision to capture before starting an incident list request.
  int get incidentRevision => _incidentRevision;

  /// Session epoch. Advanced by [clearAll] (logout / account switch / 401).
  ///
  /// A request that started under an older epoch must not write to disk
  /// afterwards: its response belongs to a session that no longer exists, and
  /// persisting it would leak the previous user's rows into the next one.
  int _sessionEpoch = 0;

  /// Epoch to capture before starting any network request.
  int get sessionEpoch => _sessionEpoch;

  /// Tail of the serialized incident-write queue.
  ///
  /// Incident writes are chained so a replace, an upsert and a wipe can never
  /// interleave: without this, an upsert landing inside another write's
  /// transaction could be deleted by that write's replace, losing an
  /// acknowledgement the server already confirmed.
  Future<void> _incidentWrites = Future<void>.value();

  /// Runs [write] after every previously queued incident write, checking the
  /// fences *inside* the queue so the decision uses the state at write time.
  ///
  /// Returns null when the write was fenced out (session ended or a newer
  /// mutation already wrote).
  ///
  /// A failing write completes the caller with that error and leaves the queue
  /// tail usable: the queue absorbs the failure instead of poisoning every
  /// later write.
  Future<T?> _enqueueIncidentWrite<T>(
    Future<T?> Function() write, {
    required int session,
    required int? revision,
  }) {
    final Completer<T?> completer = Completer<T?>();
    _incidentWrites = _incidentWrites.then((_) async {
      try {
        if (session != _sessionEpoch) {
          // The session ended while this write was queued.
          completer.complete(null);
          return;
        }
        if (revision != null && revision != _incidentRevision) {
          // A newer mutation already wrote; this result is older.
          completer.complete(null);
          return;
        }
        completer.complete(await write());
      } catch (error, stackTrace) {
        // The queue tail must stay runnable for later writes.
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  /// Runs [write] behind the same ordered boundary as the incident writes,
  /// checking [session] inside it so a response that arrives after a logout
  /// cannot write the previous session's rows back to disk.
  Future<T?> _enqueueCacheWrite<T>(
    Future<T?> Function() write, {
    required int session,
  }) {
    final Completer<T?> completer = Completer<T?>();
    _incidentWrites = _incidentWrites.then((_) async {
      try {
        if (session != _sessionEpoch) {
          completer.complete(null);
          return;
        }
        completer.complete(await write());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  // -- monitors ---------------------------------------------------------

  /// Replaces the cached monitor list and marks it fresh.
  Future<bool> saveMonitors(List<Monitor> monitors, {int? session}) async {
    final Future<bool?> queued = _enqueueCacheWrite<bool>(
      () => _writeMonitors(monitors),
      // No caller-supplied session means an internal write (seeding, tests).
      session: session ?? _sessionEpoch,
    );
    return (await queued) ?? false;
  }

  Future<bool> _writeMonitors(List<Monitor> monitors) async {
    await _db.batch((Batch batch) {
      for (final Monitor m in monitors) {
        batch.insert(
          _db.cachedMonitors,
          CachedMonitorsCompanion.insert(
            id: m.id,
            name: m.name,
            url: m.url,
            monitorType: m.monitorType,
            status: m.status,
            interval: m.interval,
            timeout: m.timeout,
            uptimePercentage: Value<double?>(m.uptimePercentage),
            lastCheckStatus: Value<String?>(m.lastCheck?.status),
            lastCheckResponseTime: Value<int?>(m.lastCheck?.responseTime),
            lastCheckAt: Value<String?>(m.lastCheck?.checkedAt),
            updatedAt: m.updatedAt,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
    await markFresh(kMonitorsCacheKey);
    return true;
  }

  /// Reads the cached monitors with their freshness state.
  Future<CachedList<CachedMonitor>> getMonitors() async {
    final List<CachedMonitor> rows = await _db.select(_db.cachedMonitors).get();
    final DateTime? synced = await lastSynced(kMonitorsCacheKey);
    return CachedList<CachedMonitor>(
      data: rows,
      cachedAt: synced,
      isStale: await isStale(kMonitorsCacheKey),
    );
  }

  /// Reactive stream of cached monitors.
  Stream<List<CachedMonitor>> watchMonitors() =>
      _db.select(_db.cachedMonitors).watch();

  // -- incidents --------------------------------------------------------

  /// Replaces the cached incident list and marks it fresh.
  ///
  /// Queued behind pending incident writes so an in-flight upsert cannot be
  /// lost, and advances [incidentRevision] so callers holding an older
  /// revision drop their now-stale result.
  Future<bool> saveIncidents(
    List<IncidentSnapshot> incidents, {
    required int session,
    required int revision,
  }) async {
    final bool? applied = await _enqueueIncidentWrite<bool>(
      () async {
        _incidentRevision++;
        await _writeIncidents(incidents);
        return true;
      },
      session: session,
      revision: revision,
    );
    return applied ?? false;
  }

  /// Replaces the cached incident list only if [revision] and [session] are
  /// still current.
  ///
  /// Returns whether the write was applied, so a loader can tell a fenced
  /// write from a successful one instead of silently serving older rows.
  Future<bool> saveIncidentsIfCurrent(
    List<IncidentSnapshot> incidents,
    int revision, {
    required int session,
  }) => saveIncidents(incidents, session: session, revision: revision);

  /// Stores one authoritative incident row without touching the others.
  ///
  /// Used for the detail an action just returned (e.g. the acknowledged
  /// incident), so a later refresh that fails — or that is fenced out above —
  /// still falls back to a cache that reflects what the server just said.
  ///
  /// Refuses to write when [session] no longer matches, so a response that
  /// arrives after a logout cannot repopulate the wiped cache. Returns whether
  /// the row was stored.
  Future<bool> upsertIncident(
    IncidentSnapshot incident, {
    required int session,
  }) async {
    final bool? applied = await _enqueueIncidentWrite<bool>(
      () async {
        _incidentRevision++;
        await _db
            .into(_db.cachedIncidents)
            .insert(incident.toCompanion(), mode: InsertMode.insertOrReplace);
        return true;
      },
      session: session,
      // No revision fence: a mutation is the newest fact there is.
      revision: null,
    );
    return applied ?? false;
  }

  Future<void> _writeIncidents(List<IncidentSnapshot> incidents) async {
    await _db.transaction(() async {
      await _db.delete(_db.cachedIncidents).go();
      for (final IncidentSnapshot i in incidents) {
        await _db
            .into(_db.cachedIncidents)
            .insert(i.toCompanion(), mode: InsertMode.insertOrReplace);
      }
    });
    await markFresh(kIncidentsCacheKey);
  }

  /// Reads the cached incidents with their freshness state.
  Future<CachedList<CachedIncident>> getIncidents() async {
    final List<CachedIncident> rows = await _db
        .select(_db.cachedIncidents)
        .get();
    final DateTime? synced = await lastSynced(kIncidentsCacheKey);
    return CachedList<CachedIncident>(
      data: rows,
      cachedAt: synced,
      isStale: await isStale(kIncidentsCacheKey),
    );
  }

  // -- checks -----------------------------------------------------------

  /// Replaces one monitor's cached check history and marks it fresh.
  Future<void> saveChecks(String monitorId, List<CheckSnapshot> checks) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.cachedChecks,
      )..where((CachedChecks t) => t.monitorId.equals(monitorId))).go();
      for (final CheckSnapshot c in checks) {
        await _db.into(_db.cachedChecks).insert(c.toCompanion());
      }
    });
    await markFresh(checksCacheKey(monitorId));
  }

  /// Reads one monitor's cached checks (oldest first) with freshness state.
  Future<CachedList<CachedCheck>> getChecks(String monitorId) async {
    final List<CachedCheck> rows =
        await (_db.select(_db.cachedChecks)
              ..where((CachedChecks t) => t.monitorId.equals(monitorId))
              ..orderBy([
                (CachedChecks t) => OrderingTerm(expression: t.checkedAt),
              ]))
            .get();
    final String key = checksCacheKey(monitorId);
    final DateTime? synced = await lastSynced(key);
    return CachedList<CachedCheck>(
      data: rows,
      cachedAt: synced,
      isStale: await isStale(key),
    );
  }

  // -- freshness --------------------------------------------------------

  /// Last successful sync for [key], or `null` when never synced.
  Future<DateTime?> lastSynced(String key) async {
    final CacheMetaData? row = await (_db.select(
      _db.cacheMeta,
    )..where((CacheMeta t) => t.key.equals(key))).getSingleOrNull();
    return row?.updatedAt;
  }

  /// Whether [key] has never synced or is older than [maxAge]
  /// (defaults to the repository's staleness threshold).
  Future<bool> isStale(String key, {Duration? maxAge}) async {
    final DateTime? synced = await lastSynced(key);
    if (synced == null) {
      return true;
    }
    return DateTime.now().difference(synced) > (maxAge ?? _staleAfter);
  }

  /// Marks [key] as freshly synced.
  Future<void> markFresh(String key) => _db
      .into(_db.cacheMeta)
      .insertOnConflictUpdate(
        CacheMetaCompanion.insert(key: key, updatedAt: DateTime.now()),
      );

  /// Wipes every cached collection and freshness marker (R2.4 logout /
  /// account-switch / 401 hygiene: no signed-in user's monitors, incidents
  /// or check history may survive for the next account).
  Future<void> clearAll() async {
    // Advance the epoch first: any request already in flight now belongs to
    // the ended session and will be refused at its write boundary.
    _sessionEpoch++;
    _incidentRevision++;
    // Queued so the wipe cannot land before an already-queued upsert, which
    // would otherwise survive the logout and repopulate the cache.
    await _enqueueIncidentWrite<void>(
      () => _wipe(),
      session: _sessionEpoch,
      revision: null,
    );
  }

  Future<void> _wipe() => _db.transaction(() async {
    await _db.delete(_db.cachedMonitors).go();
    await _db.delete(_db.cachedIncidents).go();
    await _db.delete(_db.cachedChecks).go();
    await _db.delete(_db.cacheMeta).go();
  });
}
