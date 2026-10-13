import 'dart:io';

import 'package:drift/drift.dart' show InsertMode, QueryRow;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// The v1 fixture is built with plain sqlite on purpose — drift would create the
// current schema, including the table this file upgrades *to* — and sqlite3 is
// drift's own transitive dependency, so it is reached for directly.
// `depend_on_referenced_packages` would want a pubspec.yaml edit, which is
// outside this change's ownership.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';

/// R4 storage-level guarantees for the persisted incident-detail snapshots.
///
/// Deliberately file-backed rather than in-memory: "relaunch" is the case that
/// matters, and an in-memory database is gone by definition, so a memory-backed
/// test could not tell a real persisted snapshot from one that never left the
/// process. These tests close the database, open a new [AppDatabase] over the
/// same file and read the snapshots back through a fresh [CacheRepository].
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('uptrack-r4-detail');
  });

  tearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  File dbFile() => File('${dir.path}/uptrack.db');

  /// Opens (and migrates) the real database file, handing the handle to
  /// [body] so it is always closed again.
  Future<void> withDb(
    String name,
    Future<void> Function(AppDatabase db, CacheRepository cache) body,
  ) async {
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase(dbFile()));
    addTearDown(db.close);
    await body(db, CacheRepository(db));
  }

  IncidentSnapshot snapshot(String id, {String? acknowledgedAt}) =>
      IncidentSnapshot(
        id: id,
        monitorId: 'm1',
        monitorName: 'Homepage',
        status: 'ongoing',
        insertedAt: '2026-09-27T10:00:00Z',
        acknowledgedAt: acknowledgedAt,
      );

  IncidentUpdate update(int id, String title, {String? postedAt}) =>
      IncidentUpdate(
        id: id,
        status: 'investigating',
        title: title,
        description: 'Detail for $title',
        postedAt: postedAt ?? '2026-09-27T10:06:00Z',
      );

  Future<bool> saveDetail(
    CacheRepository cache,
    IncidentSnapshot incident,
    List<IncidentUpdate> updates, {
    DateTime? syncedAt,
  }) => cache.saveIncidentDetail(
    incident,
    updates,
    session: cache.sessionEpoch,
    revision: cache.incidentRevision,
    syncedAt: syncedAt ?? DateTime.now(),
  );

  group('detail snapshots persist and reopen', () {
    test('updates and their real sync time survive a reopen', () async {
      final DateTime syncedAt = DateTime.utc(2026, 9, 27, 10, 7);
      await withDb('write', (AppDatabase db, CacheRepository cache) async {
        expect(
          await saveDetail(cache, snapshot('i1'), <IncidentUpdate>[
            update(1, 'first', postedAt: '2026-09-27T10:01:00Z'),
            update(2, 'second', postedAt: '2026-09-27T10:06:00Z'),
          ], syncedAt: syncedAt),
          isTrue,
        );
      });

      // A new database and a new repository over the same file: what the app
      // sees after a relaunch.
      await withDb('reopen', (AppDatabase db, CacheRepository cache) async {
        final CachedIncidentDetailSnapshot? saved = await cache
            .getIncidentDetail('i1');
        expect(saved, isNotNull);
        expect(
          saved!.updates.map((IncidentUpdate u) => u.displayTitle),
          <String>['first', 'second'],
        );
        // Server order is preserved: a reopened screen lists updates the way
        // the server had them, not shuffled by the cache.
        expect(saved.updates.map((IncidentUpdate u) => u.id), <int>[1, 2]);
        expect(saved.updates.first.description, 'Detail for first');
        expect(
          saved.updates.last.postedAt,
          '2026-09-27T10:06:00Z',
          reason: 'posted_at must survive the round trip too',
        );
        expect(
          saved.syncedAt.toUtc(),
          syncedAt,
          reason: 'the sync time is the write time, not the reopen time',
        );

        // The summary row the detail read wrote is there as well, so the
        // reopened screen can show an incident at all.
        final CachedList<CachedIncident> cached = await cache.getIncidents();
        expect(cached.data.single.id, 'i1');
      });
    });

    test('a successful empty read replaces the old updates', () async {
      await withDb('write', (AppDatabase db, CacheRepository cache) async {
        expect(
          await saveDetail(cache, snapshot('i1'), <IncidentUpdate>[
            update(1, 'first'),
          ]),
          isTrue,
        );
        expect(
          await saveDetail(cache, snapshot('i1'), const <IncidentUpdate>[]),
          isTrue,
        );
      });

      await withDb('reopen', (AppDatabase db, CacheRepository cache) async {
        final CachedIncidentDetailSnapshot? saved = await cache
            .getIncidentDetail('i1');
        expect(saved, isNotNull);
        expect(
          saved!.updates,
          isEmpty,
          reason:
              'a successful read that carried no updates replaces the old ones',
        );
        // Still a saved snapshot, distinct from "nothing was ever saved".
        expect(saved.syncedAt, isNotNull);
      });
    });

    test('a detail snapshot has no foreign key to the incident list', () async {
      await withDb('write', (AppDatabase db, CacheRepository cache) async {
        await saveDetail(cache, snapshot('i1'), <IncidentUpdate>[
          update(1, 'first'),
        ]);

        final List<String> fks = await _foreignKeys(
          db,
          'cached_incident_details',
        );
        expect(
          fks,
          isEmpty,
          reason:
              'no cascading foreign key: deleting an incident row must not take '
              'the saved updates with it',
        );
      });
    });
  });

  group('list replacement preserves detail snapshots', () {
    test(
      'a full summary replace keeps the updates and their timestamp',
      () async {
        final DateTime syncedAt = DateTime.utc(2026, 9, 27, 10, 7);
        await withDb('write', (AppDatabase db, CacheRepository cache) async {
          await saveDetail(cache, snapshot('i1'), <IncidentUpdate>[
            update(1, 'first'),
          ], syncedAt: syncedAt);

          // The incident list is refreshed (e.g. the feed pulls to refresh) and
          // no longer carries i1.
          expect(
            await cache.saveIncidents(
              <IncidentSnapshot>[snapshot('i2')],
              session: cache.sessionEpoch,
              revision: cache.incidentRevision,
            ),
            isTrue,
          );

          final CachedIncidentDetailSnapshot? saved = await cache
              .getIncidentDetail('i1');
          expect(
            saved,
            isNotNull,
            reason: 'a list replacement is not a detail read',
          );
          expect(saved!.updates.single.displayTitle, 'first');
          expect(
            saved.syncedAt.toUtc(),
            syncedAt,
            reason: 'a list refresh must never advance the updates\' sync time',
          );
          // The summary collection freshness did move, though: the list really
          // was just re-read.
          expect(await cache.lastSynced(kIncidentsCacheKey), isNotNull);
        });
      },
    );

    test('a detail read does not move the list freshness time', () async {
      final DateTime listSyncedAt = DateTime.utc(2026, 9, 27, 9);
      await withDb('write', (AppDatabase db, CacheRepository cache) async {
        await cache.saveIncidents(
          <IncidentSnapshot>[snapshot('i1')],
          session: cache.sessionEpoch,
          revision: cache.incidentRevision,
          syncedAt: listSyncedAt,
        );
        await saveDetail(cache, snapshot('i1'), <IncidentUpdate>[
          update(1, 'first'),
        ], syncedAt: DateTime.utc(2026, 9, 27, 10));

        expect(
          (await cache.lastSynced(kIncidentsCacheKey))!.toUtc(),
          listSyncedAt,
          reason:
              'reading one incident says nothing about the whole list, so the '
              'list timestamp must stay where it was',
        );
      });
    });
  });

  group('logout', () {
    test('clearAll deletes detail snapshots and advances the epoch', () async {
      await withDb('write', (AppDatabase db, CacheRepository cache) async {
        await saveDetail(cache, snapshot('i1'), <IncidentUpdate>[
          update(1, 'a'),
        ]);
        await saveDetail(cache, snapshot('i2'), <IncidentUpdate>[
          update(2, 'b'),
        ]);
        expect(await cache.countIncidentDetails(), 2);
        expect(await cache.getIncidentDetail('i1'), isNotNull);

        final int sessionBefore = cache.sessionEpoch;
        await cache.clearAll();

        expect(
          await cache.countIncidentDetails(),
          0,
          reason:
              'the detail table has no foreign key, so the wipe has to delete '
              'it explicitly',
        );
        expect(await cache.getIncidentDetail('i1'), isNull);
        expect(await cache.getIncidentDetail('i2'), isNull);
        expect(cache.sessionEpoch, greaterThan(sessionBefore));
      });

      // And it stays gone after a relaunch.
      await withDb('reopen', (AppDatabase db, CacheRepository cache) async {
        expect(await cache.countIncidentDetails(), 0);
      });
    });

    test('a detail write captured before clearAll is refused', () async {
      await withDb('write', (AppDatabase db, CacheRepository cache) async {
        final int session = cache.sessionEpoch;
        expect(
          await cache.saveIncidentDetail(
            snapshot('i-old-session'),
            <IncidentUpdate>[update(1, 'a')],
            session: session,
            revision: cache.incidentRevision,
          ),
          isTrue,
        );

        await cache.clearAll();

        // A response that arrives after the logout, carrying the ended
        // session's epoch.
        expect(
          await cache.saveIncidentDetail(
            snapshot('i-old-session'),
            <IncidentUpdate>[update(2, 'b')],
            session: session,
            revision: cache.incidentRevision,
          ),
          isFalse,
        );
        expect(await cache.countIncidentDetails(), 0);
      });
    });
  });

  group('fencing', () {
    test('an older detail read cannot overwrite a newer one', () async {
      final DateTime olderRead = DateTime.utc(2026, 9, 27, 10, 1);
      final DateTime newerRead = DateTime.utc(2026, 9, 27, 10, 9);
      await withDb('write', (AppDatabase db, CacheRepository cache) async {
        // A GET that started first captures the revision it is fenced on.
        final int revision = cache.incidentRevision;

        // An acknowledgement lands while it is in flight: newest fact, so an
        // unfenced write.
        expect(
          await cache.saveIncidentDetail(
            snapshot('i1', acknowledgedAt: '2026-09-27T10:05:00Z'),
            <IncidentUpdate>[update(2, 'acknowledged')],
            session: cache.sessionEpoch,
            revision: null,
            syncedAt: newerRead,
          ),
          isTrue,
        );

        // The pre-acknowledgement GET now lands and must be refused, updates
        // and timestamp alike.
        expect(
          await cache.saveIncidentDetail(
            snapshot('i1'),
            <IncidentUpdate>[update(1, 'stale')],
            session: cache.sessionEpoch,
            revision: revision,
            syncedAt: olderRead,
          ),
          isFalse,
        );

        final CachedIncidentDetailSnapshot? saved = await cache
            .getIncidentDetail('i1');
        expect(saved!.updates.single.displayTitle, 'acknowledged');
        expect(saved.syncedAt.toUtc(), newerRead);
        expect(
          (await cache.getIncidents()).data.single.acknowledgedAt,
          '2026-09-27T10:05:00Z',
        );
      });
    });

    test(
      'a fence that stops holding at the store boundary writes nothing',
      () async {
        // The boundary a caller cannot fence from the outside: its own decision is
        // already made and the write is queued, so a newer fact can only be
        // recognised where the write actually lands.
        await withDb('fence', (AppDatabase db, CacheRepository cache) async {
          final int revisionBefore = cache.incidentRevision;

          expect(
            await cache.saveIncidentDetail(
              snapshot('i1'),
              <IncidentUpdate>[update(1, 'older read')],
              session: cache.sessionEpoch,
              revision: cache.incidentRevision,
              syncedAt: DateTime.utc(2026, 9, 27, 10, 9),
              fence: () => false,
            ),
            isFalse,
          );

          expect(
            cache.incidentRevision,
            revisionBefore,
            reason:
                'a refused write stored nothing, so it must not move the revision: '
                'the newer fact that caused the refusal would then look stale',
          );
          expect(
            (await cache.getIncidents()).data,
            isEmpty,
            reason: 'the summary of a read that is no longer authoritative',
          );
          expect(await cache.countIncidentDetails(), 0);
        });
      },
    );

    test(
      'a fence that stops holding mid-transaction rolls the write back',
      () async {
        await withDb('fence-mid', (
          AppDatabase db,
          CacheRepository cache,
        ) async {
          // True at the store boundary, false once the summary row has been
          // written: the window the in-transaction recheck exists for.
          int checks = 0;

          expect(
            await cache.saveIncidentDetail(
              snapshot('i1'),
              <IncidentUpdate>[update(1, 'older read')],
              session: cache.sessionEpoch,
              revision: cache.incidentRevision,
              syncedAt: DateTime.utc(2026, 9, 27, 10, 9),
              fence: () => ++checks < 2,
            ),
            isFalse,
          );

          expect(
            checks,
            greaterThanOrEqualTo(2),
            reason:
                'the fence is rechecked after the summary is written, not only '
                'before the write starts',
          );
          expect(
            (await cache.getIncidents()).data,
            isEmpty,
            reason:
                'the summary written before the fence tripped is rolled back',
          );
          expect(await cache.countIncidentDetails(), 0);
        });
      },
    );

    test('a fence that keeps holding leaves the write untouched', () async {
      // The fence must cost the ordinary read nothing but the calls.
      await withDb('fence-holds', (
        AppDatabase db,
        CacheRepository cache,
      ) async {
        final DateTime readAt = DateTime.utc(2026, 9, 27, 10, 9);

        expect(
          await cache.saveIncidentDetail(
            snapshot('i1', acknowledgedAt: '2026-09-27T10:05:00Z'),
            <IncidentUpdate>[update(2, 'acknowledged')],
            session: cache.sessionEpoch,
            revision: cache.incidentRevision,
            syncedAt: readAt,
            fence: () => true,
          ),
          isTrue,
        );

        final CachedIncidentDetailSnapshot? saved = await cache
            .getIncidentDetail('i1');
        expect(saved!.updates.single.displayTitle, 'acknowledged');
        expect(saved.syncedAt.toUtc(), readAt);
        expect(
          (await cache.getIncidents()).data.single.acknowledgedAt,
          '2026-09-27T10:05:00Z',
        );
      });
    });
  });

  group('payload encoding', () {
    test('round-trips every update field the server sent', () {
      final List<IncidentUpdate> updates = <IncidentUpdate>[
        const IncidentUpdate(id: 3, status: 'identified'),
        IncidentUpdate(
          id: 4,
          status: 'resolved',
          title: 'Fixed',
          description: 'Rolled back the deploy',
          postedAt: '2026-09-27T11:00:00Z',
        ),
      ];

      // Field-wise rather than `equals`: IncidentUpdate is a plain model with
      // no value equality, so a list comparison would fail on identity even
      // when every field round-tripped.
      final List<IncidentUpdate>? decoded = decodeIncidentUpdates(
        encodeIncidentUpdates(updates),
      );
      expect(decoded, isNotNull);
      expect(
        decoded!
            .map(
              (IncidentUpdate u) =>
                  (u.id, u.status, u.title, u.description, u.postedAt),
            )
            .toList(),
        updates
            .map(
              (IncidentUpdate u) =>
                  (u.id, u.status, u.title, u.description, u.postedAt),
            )
            .toList(),
      );
    });

    test('an empty list encodes as an empty snapshot, not a missing one', () {
      expect(encodeIncidentUpdates(const <IncidentUpdate>[]), '[]');
      expect(decodeIncidentUpdates('[]'), isEmpty);
    });

    test('an unreadable payload decodes as no snapshot, never as empty', () {
      // Both failures matter, and they must be distinguishable from "[]":
      // claiming an incident has no updates because a payload could not be
      // read would be inventing state.
      expect(decodeIncidentUpdates('not json'), isNull);
      expect(decodeIncidentUpdates('{"not": "a list"}'), isNull);
      expect(decodeIncidentUpdates('[{"no_id": 1}]'), isNull);
    });

    test('a stored unreadable payload is reported as no usable snapshot', () async {
      await withDb('write', (AppDatabase db, CacheRepository cache) async {
        await saveDetail(cache, snapshot('i1'), <IncidentUpdate>[
          update(1, 'a'),
        ]);
        // Simulate a payload corrupted outside the app.
        await db
            .into(db.cachedIncidentDetails)
            .insert(
              CachedIncidentDetailsCompanion.insert(
                incidentId: 'i1',
                updatesJson: 'not json',
                syncedAt: DateTime.utc(2026, 9, 27, 10),
              ),
              mode: InsertMode.insertOrReplace,
            );

        expect(
          await cache.getIncidentDetail('i1'),
          isNull,
          reason:
              'unreadable content is reported as absent, so the screen can say '
              'it has no saved updates instead of claiming there are none',
        );
        expect(await cache.countIncidentDetails(), 1);
      });
    });
  });

  group('schema migration', () {
    test('v1 opens at v2, keeps its rows and gains the detail table', () async {
      // Build a real v1 database file: the four v1 tables, no detail table, and
      // user_version 1, exactly as an installed app would have left it. Plain
      // sqlite rather than a drift database, because drift would create the
      // current schema — including the table this test is upgrading *to*.
      final sqlite3.Database v1 = sqlite3.sqlite3.open(dbFile().path);
      try {
        _createV1(v1);
      } finally {
        v1.close();
      }

      await withDb('upgrade', (AppDatabase db, CacheRepository cache) async {
        expect(db.schemaVersion, 2);

        // The pre-existing rows survived the migration.
        final CachedList<CachedIncident> incidents = await cache.getIncidents();
        expect(incidents.data.single.id, 'i1');
        expect(incidents.data.single.monitorName, 'Homepage');
        final CachedList<CachedMonitor> monitors = await cache.getMonitors();
        expect(monitors.data.single.name, 'Monitor m1');
        expect(await cache.lastSynced(kIncidentsCacheKey), isNotNull);
        expect(await cache.isStale(kIncidentsCacheKey), isFalse);

        // And the new table exists, empty and usable.
        expect(await cache.countIncidentDetails(), 0);
        expect(
          await saveDetail(cache, snapshot('i2'), <IncidentUpdate>[
            update(1, 'a'),
          ]),
          isTrue,
        );
        expect(
          (await cache.getIncidentDetail('i2'))!.updates.single.displayTitle,
          'a',
        );
      });
    });

    test(
      'the v2 schema contains the detail table and v1 columns are intact',
      () async {
        await withDb('fresh', (AppDatabase db, CacheRepository cache) async {
          final Set<String> tables = await _tableNames(db);
          expect(
            tables,
            containsAll(<String>[
              'cached_monitors',
              'cached_incidents',
              'cached_checks',
              'cache_meta',
              'cached_incident_details',
            ]),
          );
          final List<String> detailColumns = await _columns(
            db,
            'cached_incident_details',
          );
          expect(
            detailColumns,
            containsAll(<String>['incident_id', 'updates_json', 'synced_at']),
          );
        });
      },
    );
  });
}

/// Creates the v1 schema by hand: the tables that existed before the detail
/// table was added, at `user_version` 1, so opening the current database runs
/// the real v1 → v2 upgrade path.
void _createV1(sqlite3.Database db) {
  void run(String sql) => db.execute(sql);

  run('''
CREATE TABLE IF NOT EXISTS "cached_monitors" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "url" TEXT NOT NULL,
  "monitor_type" TEXT NOT NULL,
  "status" TEXT NOT NULL,
  "interval" INTEGER NOT NULL,
  "timeout" INTEGER NOT NULL,
  "uptime_percentage" REAL,
  "last_check_status" TEXT,
  "last_check_response_time" INTEGER,
  "last_check_at" TEXT,
  "updated_at" TEXT NOT NULL,
  "cached_at" INTEGER NOT NULL
    DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  PRIMARY KEY ("id")
)''');
  run('''
CREATE TABLE IF NOT EXISTS "cached_incidents" (
  "id" TEXT NOT NULL,
  "monitor_id" TEXT NOT NULL,
  "monitor_name" TEXT,
  "status" TEXT NOT NULL,
  "started_at" TEXT,
  "resolved_at" TEXT,
  "acknowledged_at" TEXT,
  "inserted_at" TEXT NOT NULL,
  "cached_at" INTEGER NOT NULL
    DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  PRIMARY KEY ("id")
)''');
  run('''
CREATE TABLE IF NOT EXISTS "cached_checks" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "monitor_id" TEXT NOT NULL,
  "status" TEXT NOT NULL,
  "response_time" INTEGER NOT NULL,
  "status_code" INTEGER NOT NULL,
  "checked_at" TEXT NOT NULL,
  "error_message" TEXT
)''');
  run('''
CREATE TABLE IF NOT EXISTS "cache_meta" (
  "key" TEXT NOT NULL,
  "updated_at" INTEGER NOT NULL,
  PRIMARY KEY ("key")
)''');

  run(
    "INSERT INTO cached_monitors (id, name, url, monitor_type, status, "
    "interval, timeout, updated_at, cached_at) VALUES "
    "('m1', 'Monitor m1', 'https://example.com', 'website', 'up', 60, 10, "
    "'2026-09-26T00:00:00Z', 1790000000);",
  );
  run(
    "INSERT INTO cached_incidents (id, monitor_id, monitor_name, status, "
    "inserted_at, cached_at) VALUES "
    "('i1', 'm1', 'Homepage', 'ongoing', '2026-09-27T10:00:00Z', "
    "1790000001);",
  );
  run(
    "INSERT INTO cache_meta (key, updated_at) VALUES ('incidents', 1790600000000);",
  );
  // drift records the schema version here and refuses nothing else, so this is
  // what makes the next open a genuine upgrade.
  run('PRAGMA user_version = 1;');
}

/// Foreign keys declared on [table], from sqlite's own catalogue.
Future<List<String>> _foreignKeys(AppDatabase db, String table) async {
  final List<QueryRow> rows = await db
      .customSelect('PRAGMA foreign_key_list($table)')
      .get();
  return rows.map((QueryRow row) => row.read<String>('table')).toList();
}

Future<Set<String>> _tableNames(AppDatabase db) async {
  final List<QueryRow> rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return rows.map((QueryRow row) => row.read<String>('name')).toSet();
}

Future<List<String>> _columns(AppDatabase db, String table) async {
  final List<QueryRow> rows = await db
      .customSelect('PRAGMA table_info($table)')
      .get();
  return rows.map((QueryRow row) => row.read<String>('name')).toList();
}
