import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Cached monitor rows (subset of `MonitorOut` used by the mobile v1
/// read flows — see `lib/api/models/monitor.dart`).
class CachedMonitors extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get url => text()();
  TextColumn get monitorType => text()();
  TextColumn get status => text()();
  IntColumn get interval => integer()();
  IntColumn get timeout => integer()();
  RealColumn get uptimePercentage => real().nullable()();
  TextColumn get lastCheckStatus => text().nullable()();
  IntColumn get lastCheckResponseTime => integer().nullable()();
  TextColumn get lastCheckAt => text().nullable()();
  TextColumn get updatedAt => text()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached incident rows (subset of `IncidentOut` in `openapi-v2.json`).
class CachedIncidents extends Table {
  TextColumn get id => text()();
  TextColumn get monitorId => text()();
  TextColumn get monitorName => text().nullable()();
  TextColumn get status => text()();
  TextColumn get startedAt => text().nullable()();
  TextColumn get resolvedAt => text().nullable()();
  TextColumn get acknowledgedAt => text().nullable()();
  TextColumn get insertedAt => text()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached check rows (subset of `CheckOut` in `openapi-v2.json`).
class CachedChecks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get monitorId => text()();
  TextColumn get status => text()();
  IntColumn get responseTime => integer()();
  IntColumn get statusCode => integer()();
  TextColumn get checkedAt => text()();
  TextColumn get errorMessage => text().nullable()();
}

/// Per-collection sync timestamps backing staleness checks
/// (keys: `monitors`, `incidents`, `checks_<monitorId>`).
class CacheMeta extends Table {
  TextColumn get key => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Persisted incident-detail snapshots (R4 offline context).
///
/// Deliberately independent of [CachedIncidents]: keyed by the incident id and
/// carrying **no foreign key**, so replacing the cached incident *list* cannot
/// cascade into these rows. A list write is not a detail read, so it must never
/// delete the updates a detail read saved — nor advance their timestamp, which
/// records when those updates were actually fetched ([syncedAt]).
class CachedIncidentDetails extends Table {
  TextColumn get incidentId => text()();

  /// Posted updates exactly as the last successful detail read returned them,
  /// JSON-encoded in server order (see `CacheRepository.encodeIncidentUpdates`).
  TextColumn get updatesJson => text()();

  /// When those updates were actually last read from the API — the honest
  /// "updates last synced" time, never the moment a cached row was read back.
  DateTimeColumn get syncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {incidentId};
}

/// Offline Drift store (schema v2).
@DriftDatabase(
  tables: <Type>[
    CachedMonitors,
    CachedIncidents,
    CachedChecks,
    CacheMeta,
    CachedIncidentDetails,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'uptrack'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  /// Explicit steps rather than drift's implicit "make it look like the
  /// current schema": v2 only *adds* [cachedIncidentDetails], so an existing
  /// v1 install keeps every row it has and gains nothing but that one empty
  /// table. `test/data/local/detail_snapshot_cache_test.dart` builds a real v1
  /// database and checks both halves of that.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) => m.createAll(),
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.createTable(cachedIncidentDetails);
      }
    },
  );
}
