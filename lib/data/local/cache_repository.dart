import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../api/models/incident.dart';
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

/// Internal signal that a detail write's fence stopped holding once the write
/// was already under way, so the transaction rolls back.
///
/// Private rather than public because it never escapes [CacheRepository]: a
/// caller learns that its write was refused through `false`, never through this.
class _FenceRefused implements Exception {
  const _FenceRefused();
}

/// A [CachedList] plus the timestamp it was last refreshed from the API.
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

  CachedIncidentsCompanion toCompanion({DateTime? cachedAt}) =>
      CachedIncidentsCompanion.insert(
        id: id,
        monitorId: monitorId,
        monitorName: Value<String?>(monitorName),
        status: status,
        startedAt: Value<String?>(startedAt),
        resolvedAt: Value<String?>(resolvedAt),
        acknowledgedAt: Value<String?>(acknowledgedAt),
        insertedAt: insertedAt,
        // Stamped explicitly by the writer rather than left to the column
        // default: a cached row's own write time is what an offline detail
        // read reports as the summary's sync time, so it has to be the instant
        // the write that produced this row actually ran.
        cachedAt: cachedAt == null
            ? const Value<DateTime>.absent()
            : Value(cachedAt),
      );
}

/// One incident's saved detail snapshot: the updates of the last successful
/// detail read and the instant they were actually read.
///
/// Named apart from drift's generated row class (`CachedIncidentDetail` for
/// the `cached_incident_details` table): this is the decoded, usable snapshot,
/// and it is null whenever there is nothing usable saved.
class CachedIncidentDetailSnapshot {
  const CachedIncidentDetailSnapshot({
    required this.incidentId,
    required this.updates,
    required this.syncedAt,
  });

  final String incidentId;

  /// Posted updates in the order the server returned them. Empty when the last
  /// successful read genuinely carried none — which is a different fact from
  /// having no snapshot at all, and the two are never merged.
  final List<IncidentUpdate> updates;

  /// When these updates were actually last fetched. Never the time a cached
  /// row was read back.
  final DateTime syncedAt;
}

/// Encodes posted updates for the offline detail snapshot.
///
/// Server field names and order, so the stored payload is the detail response
/// the updates came from rather than a private dialect.
String encodeIncidentUpdates(List<IncidentUpdate> updates) => jsonEncode(
  updates
      .map(
        (IncidentUpdate u) => <String, Object?>{
          'id': u.id,
          'status': u.status,
          'title': u.title,
          'description': u.description,
          'posted_at': u.postedAt,
        },
      )
      .toList(),
);

/// Decodes a stored updates payload, or returns null when it cannot be read.
///
/// Null rather than an empty list on purpose: a snapshot the app cannot decode
/// is *no usable snapshot*, not an incident with no updates, and the detail
/// screen must say one thing and not the other.
List<IncidentUpdate>? decodeIncidentUpdates(String payload) {
  try {
    final Object? decoded = jsonDecode(payload);
    if (decoded is! List) {
      return null;
    }
    return decoded
        .map(
          (Object? e) =>
              IncidentUpdate.fromJson((e! as Map).cast<String, Object?>()),
        )
        .toList();
  } on FormatException {
    return null;
  } on TypeError {
    // A payload with the right shape but wrong field types is unreadable too.
    return null;
  }
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

  /// Monotonic generation for **every** incident read across the app, shared by
  /// the feed, the dashboard and the detail screen.
  ///
  /// [incidentRevision] cannot do this job on its own. It only advances when a
  /// write reaches its body, so an acknowledgement whose cache write fails
  /// leaves it exactly where it was — and an incident list GET that started
  /// earlier (the feed's, or the dashboard's own second read) is then, by
  /// revision, still the newest thing there is. Its Open rows would overwrite
  /// what the server just confirmed, on every surface at once. Advancing this
  /// counter is what the acknowledgement does instead, at the instant the server
  /// confirms and before any storage is attempted, so those reads are fenced
  /// wherever they happen to be: already queued behind another write, or part
  /// way through a transaction.
  ///
  /// Advances for reads only — it invalidates pending reads, it does not write
  /// anything. No cache metadata is stamped and no sync time moves, because this
  /// is not a read of anything: a confirmed action is a fact the server produced,
  /// and pretending it was a fresh sync would claim data this device never
  /// fetched. Nothing about the cache's contents changes here.
  int _incidentReadGeneration = 0;

  /// Generation to capture before starting any incident request.
  int get incidentReadGeneration => _incidentReadGeneration;

  /// Invalidates every incident read already in flight, synchronously.
  ///
  /// Called by the acknowledgement path the moment the server confirms, before
  /// its own storage attempt — so the fence exists whether that attempt
  /// succeeds, fails before its body, or fails inside the transaction.
  void invalidateIncidentReads() {
    _incidentReadGeneration++;
  }

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
    int? readGeneration,
    bool Function()? fence,
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
        if (readGeneration != null &&
            readGeneration != _incidentReadGeneration) {
          // An acknowledged action was confirmed since this read started, so its
          // rows are older than a fact the server has already recorded. Checked
          // here, inside the queue, because the confirmation can land while this
          // write is waiting its turn.
          completer.complete(null);
          return;
        }
        if (fence != null && !fence()) {
          // The caller's own fence stopped holding at the store boundary.
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
  ///
  /// [syncedAt] is the instant the API read succeeded (default: now, at the
  /// moment of the write) and is stored as this collection's freshness time, so
  /// a cached read afterwards cannot make the collection look fresher than the
  /// read that filled it.
  Future<bool> saveMonitors(
    List<Monitor> monitors, {
    int? session,
    DateTime? syncedAt,
  }) async {
    final Future<bool?> queued = _enqueueCacheWrite<bool>(
      () => _writeMonitors(monitors, syncedAt ?? DateTime.now()),
      // No caller-supplied session means an internal write (seeding, tests).
      session: session ?? _sessionEpoch,
    );
    return (await queued) ?? false;
  }

  Future<bool> _writeMonitors(List<Monitor> monitors, DateTime at) async {
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
            cachedAt: Value<DateTime>(at),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
    await markFresh(kMonitorsCacheKey, at: at);
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
  ///
  /// [readGeneration] is the shared read fence: pass the
  /// [incidentReadGeneration] captured before the network call and the write is
  /// refused if an acknowledged action was confirmed in the meantime. It is
  /// checked inside the ordered queue, so a read that has been waiting its turn
  /// is fenced too — including one whose response predates the confirmation.
  /// Null means "not a read" (internal seeding, tests).
  ///
  /// Only the list summary is touched: saved detail snapshots and their own
  /// sync times are left exactly as they were, because a list read says nothing
  /// about what an incident's updates look like.
  Future<bool> saveIncidents(
    List<IncidentSnapshot> incidents, {
    required int session,
    required int revision,
    int? readGeneration,
    DateTime? syncedAt,
  }) async {
    final bool? applied = await _enqueueIncidentWrite<bool>(
      () async {
        _incidentRevision++;
        try {
          await _writeIncidents(
            incidents,
            syncedAt ?? DateTime.now(),
            session: session,
            readGeneration: readGeneration,
          );
        } on _FenceRefused {
          // Rolled back inside [_writeIncidents]; reported as a refused write so
          // the loader resolves against the cache instead of serving this
          // response.
          return false;
        }
        return true;
      },
      session: session,
      revision: revision,
      readGeneration: readGeneration,
    );
    return applied ?? false;
  }

  /// Replaces the cached incident list only if [revision], [session] and
  /// [readGeneration] are still current.
  ///
  /// Returns whether the write was applied, so a loader can tell a fenced
  /// write from a successful one instead of silently serving older rows.
  Future<bool> saveIncidentsIfCurrent(
    List<IncidentSnapshot> incidents,
    int revision, {
    required int session,
    int? readGeneration,
    DateTime? syncedAt,
  }) => saveIncidents(
    incidents,
    session: session,
    revision: revision,
    readGeneration: readGeneration,
    syncedAt: syncedAt,
  );

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
    DateTime? syncedAt,
  }) async {
    final bool? applied = await _enqueueIncidentWrite<bool>(
      () async {
        _incidentRevision++;
        await _writeIncidentSummary(incident, syncedAt ?? DateTime.now());
        return true;
      },
      session: session,
      // No revision fence: a mutation is the newest fact there is.
      revision: null,
    );
    return applied ?? false;
  }

  /// Stores the authoritative incident summary, its posted updates and the
  /// instant they were actually read, in one write (R4).
  ///
  /// All three land in a single transaction behind the ordered epoch/revision
  /// boundary, so a relaunch can never find a summary whose updates are from a
  /// different read. [revision] fences a *read* that started before something
  /// newer was learned; pass null for a server-confirmed mutation, which is
  /// always the newest fact there is. Returns whether the write was applied.
  ///
  /// [fence] is the last line of defence, evaluated where the write actually
  /// happens rather than before this call: a caller that started a request
  /// before a newer fact was learned can still stop the write even if the
  /// ordering only became clear while it sat in the queue. It is checked three
  /// times — at the store boundary before anything is written, and twice inside
  /// the transaction, which then rolls back whole rather than committing part of
  /// a read that is no longer authoritative.
  ///
  /// A refused fence returns false and leaves [incidentRevision] alone: nothing
  /// was stored, so nothing may look newer for it. Moving the revision on a
  /// refusal would make the newer fact that caused it look stale.
  ///
  /// Advances [incidentRevision] before the transaction opens, because a detail
  /// read is a later authoritative read than any list response already in
  /// flight. A write that fails *inside* the transaction therefore leaves the
  /// revision moved with nothing stored — the same state the caller's own failed
  /// write leaves, and the reason the fences above are what decide, not the
  /// revision.
  Future<bool> saveIncidentDetail(
    IncidentSnapshot incident,
    List<IncidentUpdate> updates, {
    required int session,
    int? revision,
    int? readGeneration,
    DateTime? syncedAt,
    bool Function()? fence,
  }) async {
    final bool? applied = await _enqueueIncidentWrite<bool>(
      () async {
        final DateTime at = syncedAt ?? DateTime.now();
        if (fence != null && !fence()) {
          // Refused at the store boundary, before the revision moves: this
          // response is not the newest fact and must not become what a relaunch
          // reads.
          return false;
        }
        _incidentRevision++;
        try {
          await _db.transaction(() async {
            await _writeIncidentSummary(incident, at);
            if (_readFenced(readGeneration) || (fence != null && !fence())) {
              // Something newer was confirmed while this write was in flight, so
              // the summary just written is rolled back with the rest instead of
              // committing half of a read that is no longer authoritative.
              throw const _FenceRefused();
            }
            // Replaces the stored updates wholesale, empty included: a
            // successful read that carried none has genuinely replaced what the
            // snapshot used to hold.
            await _db
                .into(_db.cachedIncidentDetails)
                .insert(
                  CachedIncidentDetailsCompanion.insert(
                    incidentId: incident.id,
                    updatesJson: encodeIncidentUpdates(updates),
                    syncedAt: at,
                  ),
                  mode: InsertMode.insertOrReplace,
                );
            if (_readFenced(readGeneration) || (fence != null && !fence())) {
              // Last gate before the commit, for an action confirmed during the
              // insert itself.
              throw const _FenceRefused();
            }
          });
        } on _FenceRefused {
          return false;
        }
        return true;
      },
      session: session,
      revision: revision,
      readGeneration: readGeneration,
    );
    return applied ?? false;
  }

  /// Whether [readGeneration] has been superseded by a confirmed action.
  ///
  /// Read again inside the transaction, not only at the queue boundary: the
  /// confirmation can land while the write is already part way through, and a
  /// half-written older read must roll back rather than commit.
  bool _readFenced(int? readGeneration) =>
      readGeneration != null && readGeneration != _incidentReadGeneration;

  Future<void> _writeIncidentSummary(IncidentSnapshot incident, DateTime at) =>
      _db
          .into(_db.cachedIncidents)
          .insert(
            incident.toCompanion(cachedAt: at),
            mode: InsertMode.insertOrReplace,
          );

  /// Reads one incident's saved detail snapshot, or null when there is none
  /// (or the stored payload cannot be decoded).
  Future<CachedIncidentDetailSnapshot?> getIncidentDetail(
    String incidentId,
  ) async {
    final CachedIncidentDetail? row =
        await (_db.select(_db.cachedIncidentDetails)..where(
              (CachedIncidentDetails t) => t.incidentId.equals(incidentId),
            ))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final List<IncidentUpdate>? updates = decodeIncidentUpdates(
      row.updatesJson,
    );
    if (updates == null) {
      // Unreadable payload: reported as no snapshot rather than as an empty
      // one, so the screen cannot claim "no updates yet" for content it could
      // not decode.
      return null;
    }
    return CachedIncidentDetailSnapshot(
      incidentId: row.incidentId,
      updates: updates,
      syncedAt: row.syncedAt,
    );
  }

  /// How many detail snapshots are saved, without reading their payloads.
  /// Used to assert that logout really deleted them.
  Future<int> countIncidentDetails() async {
    final Expression<int> count = _db.cachedIncidentDetails.incidentId.count();
    final TypedResult row = await (_db.selectOnly(
      _db.cachedIncidentDetails,
    )..addColumns(<Expression<Object>>[count])).getSingle();
    return row.read(count) ?? 0;
  }

  /// Replaces the whole cached incident list and marks the collection fresh.
  ///
  /// [session] and [readGeneration] are the fences that apply to this write, and
  /// they are rechecked **inside** the transaction, after the delete and the
  /// inserts — not only at the queue boundary before it. Every one of those awaits
  /// is a point where an acknowledgement can be confirmed, and a commit after that
  /// point would leave the disk holding a pre-acknowledgement Open list while
  /// claiming it was just synced. Throwing [_FenceRefused] rolls the whole
  /// replacement back, rows and freshness together.
  ///
  /// The freshness marker is written *inside* the transaction for the same reason:
  /// a timestamp that survived a rolled-back write would date rows that are no
  /// longer there, which is precisely the false freshness this guards against.
  ///
  /// Only the list's freshness moves: saved detail snapshots keep the sync times of
  /// the detail reads that produced them.
  Future<void> _writeIncidents(
    List<IncidentSnapshot> incidents,
    DateTime at, {
    required int session,
    int? readGeneration,
  }) async {
    await _db.transaction(() async {
      await _db.delete(_db.cachedIncidents).go();
      for (final IncidentSnapshot i in incidents) {
        await _db
            .into(_db.cachedIncidents)
            .insert(
              i.toCompanion(cachedAt: at),
              mode: InsertMode.insertOrReplace,
            );
      }
      await markFresh(kIncidentsCacheKey, at: at);
      // Last check before the commit, covering the awaits above.
      if (session != _sessionEpoch || _readFenced(readGeneration)) {
        throw const _FenceRefused();
      }
    });
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
  ///
  /// [at] is the instant the API read that produced this data succeeded;
  /// it defaults to now, at the moment of the write. It is *not* refreshed by a
  /// cached read: only a write that carried new data calls this.
  Future<void> markFresh(String key, {DateTime? at}) => _db
      .into(_db.cacheMeta)
      .insertOnConflictUpdate(
        CacheMetaCompanion.insert(key: key, updatedAt: at ?? DateTime.now()),
      );

  /// Wipes every cached collection, saved detail snapshot and freshness marker
  /// (R2.4 logout / account-switch / 401 hygiene: no signed-in user's monitors,
  /// incidents, updates or check history may survive for the next account).
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
    // Explicit, and inside the same transaction as the summary rows: the
    // detail table has no foreign key, so nothing would cascade it away and a
    // signed-out account's incident updates would otherwise outlive the rows
    // they belong to.
    await _db.delete(_db.cachedIncidentDetails).go();
    await _db.delete(_db.cacheMeta).go();
  });
}
