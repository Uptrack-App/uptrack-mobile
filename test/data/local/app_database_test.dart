import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/monitor.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';

Monitor _monitor(String id, {String status = 'up'}) => Monitor(
  id: id,
  name: 'Monitor $id',
  url: 'https://example.com/$id',
  monitorType: 'website',
  status: status,
  interval: 60,
  timeout: 10,
  confirmationWindow: 'rolling_5m',
  regionsRequired: 'any',
  createdAt: '2026-09-01T00:00:00Z',
  updatedAt: '2026-09-26T00:00:00Z',
  uptimePercentage: 99.9,
  lastCheck: const LastCheck(
    status: 'up',
    responseTime: 123,
    checkedAt: '2026-09-26T00:00:00Z',
  ),
);

void main() {
  late AppDatabase db;
  late CacheRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CacheRepository(db);
  });

  tearDown(() => db.close());

  test('schema migrates to v1 on open', () async {
    expect(db.schemaVersion, 1);
    // Forces the database open + migration.
    await db.select(db.cachedMonitors).get();
  });

  test('monitors round-trip and mark the collection fresh', () async {
    expect(await repo.isStale(kMonitorsCacheKey), isTrue);

    await repo.saveMonitors(<Monitor>[_monitor('m1'), _monitor('m2')]);

    final CachedList<CachedMonitor> cached = await repo.getMonitors();
    expect(cached.data.map((CachedMonitor m) => m.id), <String>['m1', 'm2']);
    expect(cached.data.first.name, 'Monitor m1');
    expect(cached.data.first.uptimePercentage, 99.9);
    expect(cached.data.first.lastCheckStatus, 'up');
    expect(cached.data.first.lastCheckResponseTime, 123);
    expect(cached.cachedAt, isNotNull);
    expect(cached.isStale, isFalse);
  });

  test('saving monitors upserts on id conflict', () async {
    await repo.saveMonitors(<Monitor>[_monitor('m1')]);
    await repo.saveMonitors(<Monitor>[_monitor('m1', status: 'down')]);

    final CachedList<CachedMonitor> cached = await repo.getMonitors();
    expect(cached.data, hasLength(1));
    expect(cached.data.single.status, 'down');
  });

  test('incidents round-trip', () async {
    await repo.saveIncidents(const <IncidentSnapshot>[
      IncidentSnapshot(
        id: 'i1',
        monitorId: 'm1',
        monitorName: 'Monitor m1',
        status: 'open',
        startedAt: '2026-09-26T00:00:00Z',
        insertedAt: '2026-09-26T00:00:00Z',
      ),
    ]);

    final CachedList<CachedIncident> cached = await repo.getIncidents();
    expect(cached.data, hasLength(1));
    expect(cached.data.single.monitorName, 'Monitor m1');
    expect(cached.isStale, isFalse);
  });

  test('checks round-trip oldest-first per monitor', () async {
    await repo.saveChecks('m1', const <CheckSnapshot>[
      CheckSnapshot(
        monitorId: 'm1',
        status: 'up',
        responseTime: 200,
        statusCode: 200,
        checkedAt: '2026-09-26T00:02:00Z',
      ),
      CheckSnapshot(
        monitorId: 'm1',
        status: 'down',
        responseTime: 0,
        statusCode: 500,
        checkedAt: '2026-09-26T00:01:00Z',
        errorMessage: 'boom',
      ),
    ]);
    await repo.saveChecks('m2', const <CheckSnapshot>[
      CheckSnapshot(
        monitorId: 'm2',
        status: 'up',
        responseTime: 50,
        statusCode: 200,
        checkedAt: '2026-09-26T00:01:00Z',
      ),
    ]);

    final CachedList<CachedCheck> cached = await repo.getChecks('m1');
    expect(cached.data.map((CachedCheck c) => c.checkedAt), <String>[
      '2026-09-26T00:01:00Z',
      '2026-09-26T00:02:00Z',
    ]);
    expect(cached.data.first.errorMessage, 'boom');
    expect(cached.isStale, isFalse);
  });

  test('staleness honors a custom max age', () async {
    await repo.saveMonitors(<Monitor>[_monitor('m1')]);
    expect(await repo.isStale(kMonitorsCacheKey), isFalse);
    expect(
      await repo.isStale(kMonitorsCacheKey, maxAge: Duration.zero),
      isTrue,
    );
  });

  test('clearAll wipes collections and freshness (R2.4)', () async {
    await repo.saveMonitors(<Monitor>[_monitor('m1')]);
    await repo.saveIncidents(const <IncidentSnapshot>[
      IncidentSnapshot(
        id: 'i1',
        monitorId: 'm1',
        status: 'ongoing',
        insertedAt: '2026-09-27T10:00:00Z',
      ),
    ]);

    await repo.clearAll();

    expect((await repo.getMonitors()).data, isEmpty);
    expect((await repo.getIncidents()).data, isEmpty);
    expect(await repo.isStale(kMonitorsCacheKey), isTrue);
    expect(await repo.isStale(kIncidentsCacheKey), isTrue);
  });
}
