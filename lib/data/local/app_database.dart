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

/// Offline Drift store (schema v1).
@DriftDatabase(
  tables: <Type>[CachedMonitors, CachedIncidents, CachedChecks, CacheMeta],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'uptrack'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;
}
