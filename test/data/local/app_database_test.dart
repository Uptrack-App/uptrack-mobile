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

/// Writes incident rows under the repository's current fences, the way a
/// loader that just fetched them would.
Future<bool> _saveIncidents(
  CacheRepository repo,
  List<IncidentSnapshot> rows, {
  int? revision,
  int? session,
}) => repo.saveIncidents(
  rows,
  revision: revision ?? repo.incidentRevision,
  session: session ?? repo.sessionEpoch,
);

void main() {
  late AppDatabase db;
  late CacheRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CacheRepository(db);
  });

  tearDown(() => db.close());

  test('the schema opens at v2 with the detail table present', () async {
    expect(db.schemaVersion, 2);
    // Forces the database open + migration.
    await db.select(db.cachedMonitors).get();
    // v2 only *adds* this table, so a fresh install has it and nothing in it.
    expect(await db.select(db.cachedIncidentDetails).get(), isEmpty);
    // The upgrade of a real v1 file, with the rows it already held, is covered in
    // detail_snapshot_cache_test.dart — that test builds the v1 schema by hand at
    // user_version 1, which this one cannot: it starts from an empty database.
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
    await _saveIncidents(repo, const <IncidentSnapshot>[
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
    await _saveIncidents(repo, const <IncidentSnapshot>[
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

  group('incident write fence', () {
    test('clearAll advances the session epoch', () async {
      final int before = repo.sessionEpoch;
      await repo.clearAll();
      expect(repo.sessionEpoch, greaterThan(before));
    });

    test('a list write captured before an upsert is rejected', () async {
      final int revision = repo.incidentRevision;
      final int session = repo.sessionEpoch;
      await _saveIncidents(repo, const <IncidentSnapshot>[
        IncidentSnapshot(
          id: 'i1',
          monitorId: 'm1',
          status: 'ongoing',
          insertedAt: '2026-09-27T10:00:00Z',
        ),
      ]);

      // The acknowledge lands first and writes the authoritative row.
      expect(
        await repo.upsertIncident(
          const IncidentSnapshot(
            id: 'i1',
            monitorId: 'm1',
            status: 'ongoing',
            acknowledgedAt: '2026-09-27T10:05:00Z',
            insertedAt: '2026-09-27T10:00:00Z',
          ),
          session: session,
        ),
        isTrue,
      );

      // The older list response now lands and must be refused.
      final bool applied = await repo.saveIncidentsIfCurrent(
        const <IncidentSnapshot>[
          IncidentSnapshot(
            id: 'i1',
            monitorId: 'm1',
            status: 'ongoing',
            insertedAt: '2026-09-27T10:00:00Z',
          ),
        ],
        revision,
        session: session,
      );

      expect(applied, isFalse);
      expect(
        (await repo.getIncidents()).data.single.acknowledgedAt,
        '2026-09-27T10:05:00Z',
      );
    });

    test('a write queued after clearAll is refused (logout fence)', () async {
      final int session = repo.sessionEpoch;
      await repo.clearAll();

      final bool applied = await repo.saveIncidentsIfCurrent(
        const <IncidentSnapshot>[
          IncidentSnapshot(
            id: 'i1',
            monitorId: 'm1',
            status: 'ongoing',
            insertedAt: '2026-09-27T10:00:00Z',
          ),
        ],
        repo.incidentRevision,
        session: session,
      );

      expect(applied, isFalse);
      expect((await repo.getIncidents()).data, isEmpty);
    });

    test(
      'an upsert queued before clearAll does not survive the wipe',
      () async {
        final int session = repo.sessionEpoch;
        // Queue the upsert, then wipe: the wipe is sequenced after it, so the
        // cache ends up empty instead of holding a post-logout row.
        final Future<bool> upsert = repo.upsertIncident(
          const IncidentSnapshot(
            id: 'i1',
            monitorId: 'm1',
            status: 'ongoing',
            acknowledgedAt: '2026-09-27T10:05:00Z',
            insertedAt: '2026-09-27T10:00:00Z',
          ),
          session: session,
        );
        final Future<void> wipe = repo.clearAll();
        await Future.wait(<Future<void>>[upsert, wipe]);

        expect((await repo.getIncidents()).data, isEmpty);
      },
    );

    test(
      'a failed write reports to its caller and leaves the queue usable',
      () async {
        // One successful write opens the connection, so closing it makes the
        // following writes fail deterministically.
        await _saveIncidents(repo, const <IncidentSnapshot>[
          IncidentSnapshot(
            id: 'i0',
            monitorId: 'm1',
            status: 'ongoing',
            insertedAt: '2026-09-27T09:59:00Z',
          ),
        ]);
        await db.close();

        // The error reaches the caller instead of being swallowed or hanging.
        await expectLater(
          repo.saveIncidents(
            const <IncidentSnapshot>[
              IncidentSnapshot(
                id: 'i1',
                monitorId: 'm1',
                status: 'ongoing',
                insertedAt: '2026-09-27T10:00:00Z',
              ),
            ],
            revision: repo.incidentRevision,
            session: repo.sessionEpoch,
          ),
          throwsA(isA<Object>()),
        );

        // The queue tail still runs: this write resolves with its own error
        // rather than deadlocking behind the failed one.
        await expectLater(
          repo.upsertIncident(
            const IncidentSnapshot(
              id: 'i2',
              monitorId: 'm1',
              status: 'ongoing',
              insertedAt: '2026-09-27T10:01:00Z',
            ),
            session: repo.sessionEpoch,
          ),
          throwsA(isA<Object>()),
        );

        // A wipe after a failure also completes (surfacing its own error)
        // instead of hanging, and the queue still accepts work afterwards.
        await expectLater(repo.clearAll(), throwsA(isA<Object>()));
        await expectLater(
          repo.saveIncidentsIfCurrent(
            const <IncidentSnapshot>[],
            repo.incidentRevision,
            session: repo.sessionEpoch,
          ),
          throwsA(isA<Object>()),
        );
      },
    );

    test('a fenced write leaves the queue usable', () async {
      final int session = repo.sessionEpoch;
      await _saveIncidents(repo, const <IncidentSnapshot>[
        IncidentSnapshot(
          id: 'i1',
          monitorId: 'm1',
          status: 'ongoing',
          insertedAt: '2026-09-27T10:00:00Z',
        ),
      ]);

      // A stale revision is refused (fence hit, no error), then a valid write
      // still lands.
      expect(
        await repo.saveIncidentsIfCurrent(
          const <IncidentSnapshot>[],
          repo.incidentRevision - 1,
          session: session,
        ),
        isFalse,
      );
      expect(
        await _saveIncidents(repo, const <IncidentSnapshot>[
          IncidentSnapshot(
            id: 'i2',
            monitorId: 'm1',
            status: 'ongoing',
            insertedAt: '2026-09-27T10:01:00Z',
          ),
        ], session: session),
        isTrue,
      );
      expect((await repo.getIncidents()).data.single.id, 'i2');
    });

    test('a write queued during a logout is not applied', () async {
      final int session = repo.sessionEpoch;
      // Occupy the queue first so the logout lands before this write runs.
      await _saveIncidents(repo, const <IncidentSnapshot>[
        IncidentSnapshot(
          id: 'i1',
          monitorId: 'm1',
          status: 'ongoing',
          insertedAt: '2026-09-27T10:00:00Z',
        ),
      ]);

      final Future<bool> late = repo.upsertIncident(
        const IncidentSnapshot(
          id: 'i2',
          monitorId: 'm1',
          status: 'ongoing',
          insertedAt: '2026-09-27T10:01:00Z',
        ),
        session: session,
      );
      await repo.clearAll();

      expect(await late, isFalse);
      expect((await repo.getIncidents()).data, isEmpty);
    });

    test('monitor writes are refused after the session ends', () async {
      final int session = repo.sessionEpoch;
      await repo.clearAll();

      final bool stored = await repo.saveMonitors(<Monitor>[
        _monitor('m1'),
      ], session: session);

      expect(stored, isFalse);
      expect((await repo.getMonitors()).data, isEmpty);
    });

    test('overlapping replace and upsert keep the confirmed row', () async {
      final int session = repo.sessionEpoch;
      await _saveIncidents(repo, const <IncidentSnapshot>[
        IncidentSnapshot(
          id: 'i1',
          monitorId: 'm1',
          status: 'ongoing',
          insertedAt: '2026-09-27T10:00:00Z',
        ),
      ]);

      // Both writes start from the same revision; the upsert (mutation) must
      // win regardless of the order their transactions interleave in.
      final int revision = repo.incidentRevision;
      await Future.wait(<Future<void>>[
        repo
            .saveIncidents(
              const <IncidentSnapshot>[
                IncidentSnapshot(
                  id: 'i1',
                  monitorId: 'm1',
                  status: 'ongoing',
                  insertedAt: '2026-09-27T10:00:00Z',
                ),
              ],
              revision: revision,
              session: session,
            )
            .then((_) {}),
        repo
            .upsertIncident(
              const IncidentSnapshot(
                id: 'i1',
                monitorId: 'm1',
                status: 'ongoing',
                acknowledgedAt: '2026-09-27T10:05:00Z',
                insertedAt: '2026-09-27T10:00:00Z',
              ),
              session: session,
            )
            .then((_) {}),
      ]);

      expect(
        (await repo.getIncidents()).data.single.acknowledgedAt,
        '2026-09-27T10:05:00Z',
      );
    });
  });
}
