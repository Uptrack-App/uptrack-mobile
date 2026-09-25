import 'package:drift/drift.dart';

import '../../api/models/monitor.dart';
import 'app_database.dart';

/// Cache-freshness keys (mirrors the `cache_meta` rows).
const String kMonitorsCacheKey = 'monitors';
const String kIncidentsCacheKey = 'incidents';

/// Cache key for one monitor's check history.
String checksCacheKey(String monitorId) => 'checks_$monitorId';

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

  // -- monitors ---------------------------------------------------------

  /// Replaces the cached monitor list and marks it fresh.
  Future<void> saveMonitors(List<Monitor> monitors) async {
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
  Future<void> saveIncidents(List<IncidentSnapshot> incidents) async {
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
}
