import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart'
    show
        BatchedStatements,
        InsertMode,
        QueryExecutor,
        QueryExecutorUser,
        SqlDialect,
        TransactionExecutor;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_controller.dart';
import 'package:uptrack_mobile/features/incidents/incident_detail_screen.dart';
import 'package:uptrack_mobile/features/incidents/incident_response.dart';
import 'package:uptrack_mobile/features/incidents/incidents_controller.dart';
import 'package:uptrack_mobile/theme/app_theme.dart';

/// R4: the bounded offline context.
///
/// What these tests hold the implementation to, all through the real controller
/// and the real widget tree (not the storage queue alone):
///
/// * a detail read persists the updates and the instant they were read, and a
///   later failed read serves that saved context with that timestamp;
/// * the timestamp is the write's time, never the fallback's;
/// * the cached summary wins over in-memory detail whenever it is newer, so a
///   resolution that arrived on a list read is not undone by a stale detail;
/// * an acknowledgement the server accepted survives a *failing cache write* —
///   as an acknowledgement, not as a failed mutation — while promising nothing
///   about offline or relaunch context;
/// * an older GET cannot undo that acknowledgement, and a logout still fences
///   both.
class _Adapter implements HttpClientAdapter {
  /// Responses released by the test, so the order of a read, a mutation and a
  /// logout is deterministic.
  final Map<String, Completer<ResponseBody>> _pending =
      <String, Completer<ResponseBody>>{};

  /// Requests seen, so a test can assert what the app did (and did not) ask the
  /// server for while offline.
  final List<String> requests = <String>[];

  Future<ResponseBody> _handle(RequestOptions options) {
    final String key = '${options.method} ${options.path}';
    requests.add(key);
    final Completer<ResponseBody> completer = Completer<ResponseBody>();
    _pending[key] = completer;
    return completer.future;
  }

  Future<void> release(String method, String path, Object? body) =>
      _complete(method, path, body, 200);

  /// Fails the request the way a device with no connection does.
  Future<void> offline(String method, String path) =>
      _complete(method, path, <String, Object?>{'error': 'offline'}, 503);

  Future<void> _complete(
    String method,
    String path,
    Object? body,
    int status,
  ) async {
    final Completer<ResponseBody> gate = await _gateFor(method, path);
    _pending.remove('$method $path');
    gate.complete(
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      ),
    );
  }

  Future<Completer<ResponseBody>> _gateFor(String method, String path) async {
    final String key = '$method $path';
    for (int attempt = 0; attempt < 200; attempt++) {
      final Completer<ResponseBody>? gate = _pending[key];
      if (gate != null) {
        return gate;
      }
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('no pending $key');
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => _handle(options);

  @override
  void close({bool force = false}) {}
}

/// Answers every incident request immediately from [detail], recording what it was
/// asked.
///
/// Used by the one widget test, where a gated adapter would need real timers to
/// resolve: ordering there comes from the cache-write seam, not from the network.
class _ImmediateApi implements HttpClientAdapter {
  /// The envelope the detail read and the acknowledgement both answer with.
  Object? detail;

  /// Every request seen, so a test can prove a refresh really happened.
  final List<String> requests = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add('${options.method} ${options.path}');
    return ResponseBody.fromString(
      jsonEncode(detail ?? _detailEnvelope('i1')),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Makes a detail write fail *inside* drift's transaction, the way a full or
/// locked volume does.
///
/// Distinct from [_WriteFailingCache] on purpose, and closer to reality. The real
/// repository advances the incident revision *before* it opens the transaction,
/// so a transaction that fails leaves the revision moved even though nothing was
/// stored. A pre-write failure does not: it leaves the revision where it was,
/// which is the case that makes the request sequencing in
/// [_ApiIncidentDetailRepository] load-bearing rather than incidental.
///
/// Done with a trigger that aborts the insert rather than by dropping the table:
/// the schema stays the real one, so the test can still read the table afterwards
/// to assert that nothing was written into it.
///
/// [AppDatabase] is the real one, so the repository's writes genuinely fail
/// against the real schema.
Future<void> failDetailInserts(AppDatabase db) async {
  await db.customStatement('''
CREATE TRIGGER r4_fail_detail_insert
BEFORE INSERT ON cached_incident_details
BEGIN
  SELECT RAISE(ABORT, 'disk full: the detail snapshot could not be written');
END;
''');
  // Belt and braces: a failed expectation must not leave the trigger behind for
  // whatever runs next against this database.
  addTearDown(() => restoreDetailInserts(db));
}

/// Removes [failDetailInserts]'s trigger, so a write attempted afterwards can
/// succeed again.
Future<void> restoreDetailInserts(AppDatabase db) async {
  await db.customStatement('DROP TRIGGER IF EXISTS r4_fail_detail_insert;');
}

/// Pauses a real SQL statement so a test can act while a write is genuinely
/// inside its transaction.
///
/// The point of this seam is that it fires *after* the statement has been
/// executed and before drift is told it finished — the only position left once
/// the queue-boundary checks have already passed. A repository-level seam could
/// not reach it, because there is no gap in the repository between "queued" and
/// "awaiting SQLite".
class _SqlGate implements QueryExecutor {
  _SqlGate(this._inner);

  final QueryExecutor _inner;

  Completer<void>? _staged;
  Completer<void>? _release;
  bool _armed = false;

  /// Arms the gate for the next `DELETE FROM cached_incidents`, signalling
  /// [staged] once it has been executed and waiting for [release] before letting
  /// drift continue.
  void pauseNextIncidentDelete(
    Completer<void> staged,
    Completer<void> release,
  ) {
    _staged = staged;
    _release = release;
    _armed = true;
  }

  /// Called after an armed statement has been executed but before drift is told
  /// it finished — inside the transaction, before the commit.
  Future<void> _holdIfArmed(String statement) async {
    final Completer<void>? staged = _staged;
    final Completer<void>? release = _release;
    if (!_armed || !_isIncidentDelete(statement)) {
      return;
    }
    _armed = false;
    _staged = null;
    _release = null;
    staged!.complete();
    await release!.future;
  }

  bool _isIncidentDelete(String statement) =>
      statement.toUpperCase().contains('CACHED_INCIDENTS');

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _inner.runSelect(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    final int id = await _inner.runInsert(statement, args);
    await _holdIfArmed(statement);
    return id;
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    final int rows = await _inner.runUpdate(statement, args);
    await _holdIfArmed(statement);
    return rows;
  }

  @override
  Future<int> runDelete(String statement, List<Object?> args) async {
    final int rows = await _inner.runDelete(statement, args);
    await _holdIfArmed(statement);
    return rows;
  }

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _inner.runCustom(statement, args);

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _inner.runBatched(statements);

  @override
  TransactionExecutor beginTransaction() =>
      _SqlGateTransaction(_inner.beginTransaction(), this);

  @override
  QueryExecutor beginExclusive() => _SqlGate(_inner.beginExclusive());

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _inner.ensureOpen(user);

  @override
  SqlDialect get dialect => _inner.dialect;

  @override
  Future<void> close() => _inner.close();
}

/// The transaction-scoped half of [_SqlGate], so a statement issued inside a
/// transaction is paused by the same gate as one issued outside it.
class _SqlGateTransaction implements TransactionExecutor {
  _SqlGateTransaction(this._inner, this._gate);

  final TransactionExecutor _inner;
  final _SqlGate _gate;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _inner.runSelect(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    final int id = await _inner.runInsert(statement, args);
    await _gate._holdIfArmed(statement);
    return id;
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    final int rows = await _inner.runUpdate(statement, args);
    await _gate._holdIfArmed(statement);
    return rows;
  }

  @override
  Future<int> runDelete(String statement, List<Object?> args) async {
    final int rows = await _inner.runDelete(statement, args);
    await _gate._holdIfArmed(statement);
    return rows;
  }

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _inner.runCustom(statement, args);

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _inner.runBatched(statements);

  @override
  TransactionExecutor beginTransaction() =>
      _SqlGateTransaction(_inner.beginTransaction(), _gate);

  @override
  QueryExecutor beginExclusive() => _SqlGate(_inner.beginExclusive());

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _inner.ensureOpen(user);

  @override
  SqlDialect get dialect => _inner.dialect;

  @override
  Future<void> close() => _inner.close();

  @override
  bool get supportsNestedTransactions => _inner.supportsNestedTransactions;

  @override
  Future<void> send() => _inner.send();

  @override
  Future<void> rollback() => _inner.rollback();
}

/// A [CacheRepository] whose detail write can be held, or failed, on demand.
///
/// Stands in for the storage behaviour that matters here: the API accepted the
/// acknowledgement and *then* the local write broke, or the write waited long
/// enough in the cache queue for a newer fact to be confirmed while it sat
/// there.
///
/// Two seams, deliberately separate because they model different orderings:
///
/// * [failDetailWrites] fails *before* the write reaches the cache queue, so the
///   repository's incident revision never moves — the case that makes the
///   request sequencing in [_ApiIncidentDetailRepository] load-bearing rather
///   than incidental;
/// * [holdNextWrite] holds a write on its way into the queue, so a test can
///   confirm a server action in between the caller's own decision and the write
///   it decided to make — the case the store-boundary fence exists for.
class _WriteFailingCache extends CacheRepository {
  _WriteFailingCache(super.db);

  bool failDetailWrites = false;

  /// When > 0, only the next [failCount] detail writes fail and then the seam
  /// disarms itself.
  ///
  /// A single transient failure is what makes the racing test meaningful: the
  /// rejected GET that lands afterwards still has to be able to write, so the
  /// protection being asserted cannot be "every write is failing".
  int failCount = 0;

  /// Detail writes attempted while [failDetailWrites] was set.
  int failedWrites = 0;

  /// Held by the next detail write before it is offered to the cache queue.
  Completer<void>? holdNextWrite;

  /// The hold a write is inside right now, so a test can wait for its own
  /// ordering instead of hoping the microtasks fell that way.
  Completer<void>? held;

  @override
  Future<bool> saveIncidentDetail(
    IncidentSnapshot incident,
    List<IncidentUpdate> updates, {
    required int session,
    int? revision,
    int? readGeneration,
    DateTime? syncedAt,
    bool Function()? fence,
  }) async {
    final Completer<void>? hold = holdNextWrite;
    if (hold != null) {
      holdNextWrite = null;
      held = hold;
      try {
        await hold.future;
      } finally {
        held = null;
      }
    }
    if (failDetailWrites) {
      failedWrites++;
      if (failCount > 0 && --failCount == 0) {
        failDetailWrites = false;
      }
      throw StateError('disk full: the detail snapshot could not be written');
    }
    return super.saveIncidentDetail(
      incident,
      updates,
      session: session,
      revision: revision,
      readGeneration: readGeneration,
      syncedAt: syncedAt,
      fence: fence,
    );
  }
}

/// Spins until [cache] is inside the given write hold, so a test's ordering is
/// established rather than assumed.
Future<void> _waitUntilHolding(
  _WriteFailingCache cache,
  Completer<void> hold,
) async {
  for (int attempt = 0; attempt < 200 && cache.held != hold; attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(
    cache.held,
    same(hold),
    reason: 'the detail write never reached its hold',
  );
}

Map<String, Object?> _incidentJson(
  String id, {
  String? acknowledgedAt,
  String? resolvedAt,
}) => <String, Object?>{
  'id': id,
  'monitor_id': 'm1',
  'monitor_name': 'Homepage',
  'status': resolvedAt == null ? 'ongoing' : 'resolved',
  'inserted_at': '2026-09-27T10:00:00Z',
  'started_at': '2026-09-27T10:00:00Z',
  'acknowledged_at': acknowledgedAt,
  'resolved_at': resolvedAt,
};

Map<String, Object?> _detailEnvelope(
  String id, {
  String? acknowledgedAt,
  String? resolvedAt,
  List<Object?> updates = const <Object?>[],
}) => <String, Object?>{
  'data': <String, Object?>{
    'incident': _incidentJson(
      id,
      acknowledgedAt: acknowledgedAt,
      resolvedAt: resolvedAt,
    ),
    'updates': updates,
  },
};

Map<String, Object?> _update(String title) => <String, Object?>{
  'id': 7,
  'status': 'investigating',
  'title': title,
  'description': 'Detail for $title',
  'posted_at': '2026-09-27T10:06:00Z',
};

void main() {
  late AppDatabase db;
  late CacheRepository cache;
  late _Adapter adapter;
  late Dio dio;
  late UptrackApi api;
  late _SqlGate sqlGate;

  setUp(() {
    // The database runs behind [_SqlGate], so a test can pause a real statement
    // without any repository-level seam: everything below is the production code
    // path against a real schema.
    sqlGate = _SqlGate(NativeDatabase.memory());
    db = AppDatabase.forTesting(sqlGate);
    cache = CacheRepository(db);
    adapter = _Adapter();
    dio = Dio()..httpClientAdapter = adapter;
    api = UptrackApi(dio: dio);
  });

  tearDown(() async {
    await db.close();
    dio.close(force: true);
  });

  /// Reads the detail once successfully, so a snapshot exists on disk.
  Future<IncidentDetailData> seedOnlineRead(
    ApiIncidentDetailRepository repo,
    String id, {
    String? resolvedAt,
    List<Object?> updates = const <Object?>[],
  }) async {
    final Future<IncidentDetailData> load = repo.load(id);
    await adapter.release(
      'GET',
      incidentDetailPath(id),
      _detailEnvelope(id, resolvedAt: resolvedAt, updates: updates),
    );
    return load;
  }

  group('offline context after a successful read', () {
    test('a failed read serves the saved updates and the real sync time', () async {
      final ApiIncidentDetailRepository repo = ApiIncidentDetailRepository(
        api: api,
        cache: cache,
      );
      await seedOnlineRead(
        repo,
        'i1',
        updates: <Object?>[_update('investigating the failure')],
      );
      final DateTime syncedAt = (await cache.getIncidentDetail('i1'))!.syncedAt;

      // The device goes offline and the user refreshes.
      final Future<IncidentDetailData> offlineLoad = repo.load('i1');
      await adapter.offline('GET', incidentDetailPath('i1'));
      final IncidentDetailData offline = await offlineLoad;

      expect(offline.offline, isTrue);
      expect(
        offline.updates.map((IncidentUpdate u) => u.displayTitle),
        <String>['investigating the failure'],
        reason:
            'the updates of the last successful read must be served offline',
      );
      expect(
        offline.updates.single.description,
        'Detail for investigating the failure',
      );
      expect(offline.updatesSyncedAt, syncedAt);
      expect(offline.hasSavedSnapshot, isTrue);

      // Repeated failures keep reporting the same instant: a fallback read must
      // never restamp the snapshot as freshly synced.
      final Future<IncidentDetailData> againLoad = repo.load('i1');
      await adapter.offline('GET', incidentDetailPath('i1'));
      final IncidentDetailData again = await againLoad;
      expect(again.updatesSyncedAt, syncedAt);
      expect((await cache.getIncidentDetail('i1'))!.syncedAt, syncedAt);
    });

    test('the summary timestamp is not refreshed by a fallback read', () async {
      final ApiIncidentDetailRepository repo = ApiIncidentDetailRepository(
        api: api,
        cache: cache,
      );
      await seedOnlineRead(repo, 'i1');
      final DateTime readAt = (await cache.getIncidentDetail('i1'))!.syncedAt;

      final Future<IncidentDetailData> firstLoad = repo.load('i1');
      await adapter.offline('GET', incidentDetailPath('i1'));
      final IncidentDetailData first = await firstLoad;
      expect(first.summarySyncedAt, readAt);

      // Nothing has re-read the network, so nothing may claim a later sync.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final Future<IncidentDetailData> secondLoad = repo.load('i1');
      await adapter.offline('GET', incidentDetailPath('i1'));
      final IncidentDetailData second = await secondLoad;
      expect(second.summarySyncedAt, readAt);
      expect(second.updatesSyncedAt, readAt);
      expect(
        await cache.lastSynced(kIncidentsCacheKey),
        isNull,
        reason: 'a detail read is not a list sync',
      );
    });

    test('a list refresh does not disturb the saved updates', () async {
      final ApiIncidentDetailRepository repo = ApiIncidentDetailRepository(
        api: api,
        cache: cache,
      );
      await seedOnlineRead(
        repo,
        'i1',
        updates: <Object?>[_update('before the list refresh')],
      );
      final DateTime detailSyncedAt = (await cache.getIncidentDetail('i1'))!
          .syncedAt;

      // The feed refreshes and the list no longer carries i1.
      final ApiIncidentsRepository feed = ApiIncidentsRepository(
        api: api,
        cache: cache,
      );
      final Future<IncidentsData> listLoad = feed.load();
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[_incidentJson('i2')],
      });
      await listLoad;

      final CachedIncidentDetailSnapshot? saved = await cache.getIncidentDetail(
        'i1',
      );
      expect(saved, isNotNull, reason: 'a list refresh is not a detail read');
      expect(saved!.updates.single.displayTitle, 'before the list refresh');
      expect(saved.syncedAt, detailSyncedAt);
    });

    test('an unreadable saved payload is not served as "no updates"', () async {
      final ApiIncidentDetailRepository repo = ApiIncidentDetailRepository(
        api: api,
        cache: cache,
      );
      await seedOnlineRead(
        repo,
        'i1',
        updates: <Object?>[_update('real update')],
      );
      // Corrupt the payload the way an outside write would.
      await db
          .into(db.cachedIncidentDetails)
          .insert(
            CachedIncidentDetailsCompanion.insert(
              incidentId: 'i1',
              updatesJson: 'not json',
              syncedAt: DateTime.now(),
            ),
            mode: InsertMode.insertOrReplace,
          );

      final Future<IncidentDetailData> unreadableLoad = repo.load('i1');
      await adapter.offline('GET', incidentDetailPath('i1'));
      final IncidentDetailData offline = await unreadableLoad;

      expect(offline.updates, isEmpty);
      expect(
        offline.hasSavedSnapshot,
        isFalse,
        reason:
            'undecodable content is not a saved snapshot, so the screen says the '
            'updates are unavailable rather than claiming there are none',
      );
      // The summary is still served: one unusable table is not a reason to
      // invent or hide the incident itself.
      expect(offline.incident.id, 'i1');
    });

    test('no cached summary row means no offline detail at all', () async {
      final ApiIncidentDetailRepository repo = ApiIncidentDetailRepository(
        api: api,
        cache: cache,
      );
      final Future<IncidentDetailData> neverRead = repo.load('never-read');
      await adapter.offline('GET', incidentDetailPath('never-read'));
      await expectLater(
        neverRead,
        throwsA(isA<DioException>()),
        reason:
            'the cache holds no row, so the failure is reported as a failure',
      );
    });
  });

  group('the newest summary wins', () {
    test(
      'a resolution read on the list is not undone by a stale detail',
      () async {
        final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
          api: api,
          cache: cache,
        );
        // t1: the detail is open.
        await seedOnlineRead(
          detail,
          'i1',
          updates: <Object?>[_update('still investigating')],
        );
        final DateTime detailSyncedAt = (await cache.getIncidentDetail('i1'))!
            .syncedAt;

        // t2: a list read resolves the incident.
        final ApiIncidentsRepository feed = ApiIncidentsRepository(
          api: api,
          cache: cache,
        );
        final Future<IncidentsData> listLoad = feed.load();
        await adapter.release('GET', kIncidentsPath, <String, Object?>{
          'data': <Object?>[
            _incidentJson('i1', resolvedAt: '2026-09-27T11:00:00Z'),
          ],
        });
        await listLoad;
        final DateTime listSyncedAt = (await cache.lastSynced(
          kIncidentsCacheKey,
        ))!;

        // t3: the detail read fails, and in-memory state still holds the open
        // incident from t1.
        final Future<IncidentDetailData> resolvedLoad = detail.load('i1');
        await adapter.offline('GET', incidentDetailPath('i1'));
        final IncidentDetailData offline = await resolvedLoad;

        expect(
          offline.incident.resolvedAt,
          '2026-09-27T11:00:00Z',
          reason:
              'the list read at t2 is the newest summary; the t1 detail read must '
              'not resurrect the open incident',
        );
        expect(offline.incident.isOngoing, isFalse);
        expect(
          offline.updates.map((IncidentUpdate u) => u.displayTitle),
          <String>['still investigating'],
          reason: 'the updates still come from the last successful detail read',
        );
        expect(
          offline.updatesSyncedAt,
          detailSyncedAt,
          reason: 'with their original detail sync time',
        );
        expect(offline.summarySyncedAt, listSyncedAt);
      },
    );

    test('an acknowledged action may still override the cached row', () async {
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: cache,
      );
      // The list is read first, so the cache genuinely holds an older row.
      final ApiIncidentsRepository feed = ApiIncidentsRepository(
        api: api,
        cache: cache,
      );
      final Future<IncidentsData> listLoad = feed.load();
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[_incidentJson('i1')],
      });
      await listLoad;

      // The acknowledgement is the newer fact and is persisted.
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope(
          'i1',
          acknowledgedAt: '2026-09-27T12:00:00Z',
          updates: <Object?>[_update('acknowledged by us')],
        ),
      );
      await ack;

      final Future<IncidentDetailData> ackOverrideLoad = detail.load('i1');
      await adapter.offline('GET', incidentDetailPath('i1'));
      final IncidentDetailData offline = await ackOverrideLoad;

      expect(offline.incident.isAcknowledged, isTrue);
      expect(offline.updates.single.displayTitle, 'acknowledged by us');
    });

    test('an old in-flight GET cannot undo a newer list resolution', () async {
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: cache,
      );
      // t1: a detail GET starts, and while it is in flight...
      final Future<IncidentDetailData> inFlight = detail.load('i1');

      // ...t2: an acknowledgement lands (the newest fact so far)...
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope(
          'i1',
          acknowledgedAt: '2026-09-27T12:00:00Z',
          updates: <Object?>[_update('acknowledged update')],
        ),
      );
      final IncidentDetailData acknowledged = await ack;

      // ...t3: a list read resolves the incident, superseding that row.
      final ApiIncidentsRepository feed = ApiIncidentsRepository(
        api: api,
        cache: cache,
      );
      final Future<IncidentsData> listLoad = feed.load();
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[
          _incidentJson(
            'i1',
            acknowledgedAt: '2026-09-27T12:00:00Z',
            resolvedAt: '2026-09-27T13:00:00Z',
          ),
        ],
      });
      await listLoad;
      final DateTime listSyncedAt = (await cache.lastSynced(
        kIncidentsCacheKey,
      ))!;
      final DateTime detailSyncedAt = (await cache.getIncidentDetail('i1'))!
          .syncedAt;

      // t4: the detail GET from t1 finally lands, carrying the pre-ack,
      // unresolved incident.
      await adapter.release(
        'GET',
        incidentDetailPath('i1'),
        _detailEnvelope('i1', updates: <Object?>[_update('older read')]),
      );
      final IncidentDetailData result = await inFlight;

      expect(
        result.incident.resolvedAt,
        '2026-09-27T13:00:00Z',
        reason:
            'the t3 list read is newer than the t4 in-flight GET, so its '
            'resolved summary is what the screen gets',
      );
      expect(result.incident.isAcknowledged, isTrue);
      expect(
        result.updates.map((IncidentUpdate u) => u.displayTitle),
        <String>['acknowledged update'],
        reason:
            'the updates keep the provenance of the last successful detail '
            'write (t2), not the rejected t4 response',
      );
      expect(
        result.updatesSyncedAt,
        detailSyncedAt,
        reason: 'with that write\'s own sync time',
      );
      expect(result.summarySyncedAt, listSyncedAt);
      expect(result.savedOffline, isTrue);

      // Sanity on the acknowledged state that had to survive all of this.
      expect(acknowledged.incident.isAcknowledged, isTrue);
    });

    test('an old in-flight GET cannot undo an unsaved acknowledgement', () async {
      // The harder ordering: a detail GET is already in flight when the
      // acknowledgement is confirmed, and the acknowledgement's local write
      // then fails. The failing seam is *pre-write*, so the cache revision
      // never moves — only the sequencing keeps the old read from winning.
      final _WriteFailingCache failing = _WriteFailingCache(db);
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: failing,
      );

      // t1: the old, unacknowledged detail GET starts and stays in flight.
      final Future<IncidentDetailData> staleGet = detail.load('i1');

      // t2: the server acknowledges, and that one write fails.
      failing.failDetailWrites = true;
      failing.failCount = 1;
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope(
          'i1',
          acknowledgedAt: '2026-10-27T12:00:00Z',
          updates: <Object?>[_update('acknowledged update')],
        ),
      );
      final IncidentDetailData acknowledged = await ack;
      expect(acknowledged.incident.isAcknowledged, isTrue);
      expect(acknowledged.savedOffline, isFalse);

      final int revisionAfterAck = failing.incidentRevision;

      // t3: the pre-acknowledgement GET finally lands.
      await adapter.release(
        'GET',
        incidentDetailPath('i1'),
        _detailEnvelope('i1', updates: <Object?>[_update('older read')]),
      );
      final IncidentDetailData result = await staleGet;
      final int revisionAfterGet = failing.incidentRevision;

      expect(
        result.incident.isAcknowledged,
        isTrue,
        reason:
            'the confirmed acknowledgement is the newer fact even though its '
            'write failed and the cache revision never moved',
      );
      expect(
        result.updates.single.displayTitle,
        'acknowledged update',
        reason: 'the old read must not replace the confirmed updates either',
      );
      expect(
        result.savedOffline,
        isFalse,
        reason:
            'the authoritative content was never written, so nothing may be '
            'promised about offline or relaunch context',
      );
      expect(
        revisionAfterAck,
        failing.incidentRevision,
        reason:
            'sanity: this seam fails before the write, so the revision is '
            'unchanged and the ordering is what protects the result',
      );
      expect(
        revisionAfterAck,
        revisionAfterGet,
        reason: 'and the rejected read did not move it either',
      );

      // The rejected read is refused outright: the open incident it carried
      // never reaches disk, so a relaunch cannot show an acknowledged incident
      // as still open — and nothing about it may be promised offline.
      expect(
        (await cache.getIncidents()).data,
        isEmpty,
        reason:
            'the pre-acknowledgement Open must not be persisted over the fact '
            'the server just recorded',
      );
      expect(await cache.countIncidentDetails(), 0, reason: 'nor its updates');
    });

    test('an action confirmed while the write was queued keeps the old read off '
        'disk', () async {
      // The ordering a post-write correction cannot fix: this GET's write has
      // already been decided and is waiting to reach the cache, and only then
      // does the server confirm an acknowledgement whose own write fails
      // before it moves the revision. Nothing of that is visible at the
      // decision point, and the disk revision never moves, so the old Open
      // must be stopped where the write actually lands.
      final _WriteFailingCache failing = _WriteFailingCache(db);
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: failing,
      );
      final int revisionBefore = failing.incidentRevision;

      // t1: the old, unacknowledged detail GET starts and lands.
      final Future<IncidentDetailData> staleGet = detail.load('i1');
      // Its write is held on the way into the cache queue.
      final Completer<void> heldRead = Completer<void>();
      failing.holdNextWrite = heldRead;
      await adapter.release(
        'GET',
        incidentDetailPath('i1'),
        _detailEnvelope('i1', updates: <Object?>[_update('older read')]),
      );
      await _waitUntilHolding(failing, heldRead);
      final int revisionAfterGet = failing.incidentRevision;

      // t2: while that write waits, the server acknowledges and that one write
      // fails before it touches the disk.
      failing.failDetailWrites = true;
      failing.failCount = 1;
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope(
          'i1',
          acknowledgedAt: '2026-10-27T12:00:00Z',
          updates: <Object?>[_update('acknowledged update')],
        ),
      );
      final IncidentDetailData acknowledged = await ack;
      expect(acknowledged.incident.isAcknowledged, isTrue);
      expect(acknowledged.savedOffline, isFalse);
      expect(
        failing.incidentRevision,
        revisionAfterGet,
        reason: 'sanity: the acknowledgement\'s write failed before the disk',
      );

      // t3: the held read is finally allowed to write — and must be refused at
      // the boundary, not merely corrected afterwards.
      heldRead.complete();
      final IncidentDetailData result = await staleGet;

      expect(
        result.incident.isAcknowledged,
        isTrue,
        reason:
            'the acknowledgement is the newer fact, and a write that never '
            'reached disk cannot make it look stale',
      );
      expect(result.updates.single.displayTitle, 'acknowledged update');
      expect(
        result.savedOffline,
        isFalse,
        reason: 'nothing was written, so nothing is promised offline',
      );
      expect(
        failing.incidentRevision,
        revisionBefore,
        reason:
            'a refused write leaves the revision alone; moving it here is what '
            'would make the authoritative acknowledgement look superseded',
      );
      expect(
        (await cache.getIncidents()).data,
        isEmpty,
        reason: 'the old Open must not be what a relaunch reads',
      );
      expect(await cache.countIncidentDetails(), 0, reason: 'nor its updates');
    });

    test('a confirmation recorded before its own write settles keeps the queued '
        'read off disk', () async {
      // The ordering a record-after-write implementation cannot survive: the
      // old read's write is already on its way, the server confirms the
      // acknowledgement, and *that* write is then failed inside its own
      // transaction. The confirmation has to be visible before the storage
      // await, or the older read is free to persist the pre-acknowledgement
      // incident while the newer fact waits for the disk.
      final _WriteFailingCache failing = _WriteFailingCache(db);
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: failing,
      );
      final int revisionBefore = failing.incidentRevision;

      // t1: the old, unacknowledged detail GET lands; its write is held on the
      // way into the cache queue.
      final Completer<void> heldRead = Completer<void>();
      failing.holdNextWrite = heldRead;
      final Future<IncidentDetailData> staleGet = detail.load('i1');
      await adapter.release(
        'GET',
        incidentDetailPath('i1'),
        _detailEnvelope('i1', updates: <Object?>[_update('older read')]),
      );
      await _waitUntilHolding(failing, heldRead);

      // t2: the server acknowledges, and that write is held too — still
      // unsaved, so nothing may claim it is on disk yet.
      final Completer<void> heldAction = Completer<void>();
      failing.holdNextWrite = heldAction;
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope(
          'i1',
          acknowledgedAt: '2026-10-27T12:00:00Z',
          updates: <Object?>[_update('acknowledged update')],
        ),
      );
      await _waitUntilHolding(failing, heldAction);

      final IncidentDetailData? pending = detail.confirmedDetail('i1');
      expect(
        pending,
        isNotNull,
        reason:
            'the server confirmed this before the write finished, so anything '
            'deciding about a queued write has to be able to see it now',
      );
      expect(pending!.incident.isAcknowledged, isTrue);
      expect(
        pending.savedOffline,
        isFalse,
        reason:
            'the store has not answered yet, so nothing about offline or '
            'relaunch context may be promised for it',
      );

      // t3: the acknowledgement's own write now runs — and fails for real,
      // inside the transaction, after the revision has moved.
      await failDetailInserts(db);
      heldAction.complete();
      final IncidentDetailData acknowledged = await ack;
      expect(acknowledged.incident.isAcknowledged, isTrue);
      expect(acknowledged.savedOffline, isFalse);
      final int revisionAfterAck = failing.incidentRevision;
      expect(
        revisionAfterAck,
        greaterThan(revisionBefore),
        reason:
            'this seam fails inside the transaction, so the revision really '
            'did advance — the refusal below cannot pass by accident',
      );
      expect(
        await failing.countIncidentDetails(),
        0,
        reason: 'the transaction rolled back: nothing was stored',
      );

      // t4: the old read is finally allowed to write, and must not become what
      // a relaunch reads.
      heldRead.complete();
      final IncidentDetailData result = await staleGet;

      expect(
        result.incident.isAcknowledged,
        isTrue,
        reason: 'the confirmation is still the newest fact',
      );
      expect(result.updates.single.displayTitle, 'acknowledged update');
      expect(result.savedOffline, isFalse, reason: 'nothing was written');
      expect(
        failing.incidentRevision,
        revisionAfterAck,
        reason:
            'the refused read left the revision alone, so it cannot make the '
            'authoritative acknowledgement look superseded',
      );
      expect(
        (await cache.getIncidents()).data,
        isEmpty,
        reason: 'the pre-acknowledgement Open must not be persisted',
      );
      expect(await cache.countIncidentDetails(), 0, reason: 'nor its updates');
    });

    test('an old feed and dashboard read cannot restore Open after an '
        'unsaved acknowledgement', () async {
      // The cross-surface case: the confirmation invalidates reads *everywhere*,
      // not just this screen's own. Both network responses are gated so the
      // acknowledgement lands while they are still in flight — and its cache
      // write then fails before the disk revision moves, which is exactly why
      // the revision cannot be the fence.
      final _WriteFailingCache failing = _WriteFailingCache(db);
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: failing,
      );
      final ApiIncidentsRepository feed = ApiIncidentsRepository(
        api: api,
        cache: failing,
      );
      final ApiDashboardRepository dashboard = ApiDashboardRepository(
        api: api,
        cache: failing,
      );

      // t1: the feed and the dashboard both start an Open list read.
      final Future<IncidentsData> feedLoad = feed.load();
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[_incidentJson('i1')],
      });
      final Future<DashboardData> dashboardLoad = dashboard.load();
      // The dashboard reads monitors first, then incidents. Its monitor page is
      // empty, which keeps the dashboard's own monitor write trivially out of
      // the way — the case under test is the incident list write.
      await adapter.release('GET', kListMonitorsPath, <String, Object?>{
        'data': <Object?>[],
        'meta': <String, Object?>{'total': 0, 'page': 1, 'per_page': 100},
      });
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[_incidentJson('i1')],
      });
      await feedLoad;
      await dashboardLoad;
      expect(
        (await cache.getIncidents()).data.single.acknowledgedAt,
        isNull,
        reason: 'sanity: the Open rows were stored before the action',
      );

      // t2: the server confirms an acknowledgement whose write fails before the
      // revision moves.
      failing.failDetailWrites = true;
      failing.failCount = 1;
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope('i1', acknowledgedAt: '2026-10-27T12:00:00Z'),
      );
      final IncidentDetailData acknowledged = await ack;
      expect(acknowledged.savedOffline, isFalse);
      final int revisionAfterAck = failing.incidentRevision;
      expect(
        revisionAfterAck,
        failing.incidentRevision,
        reason: 'sanity: the failed write left the revision where it was',
      );

      // t3: reads that started *before* the confirmation are now released with
      // the old Open list. Neither may persist it.
      final Future<IncidentsData> oldFeed = feed.load();
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[_incidentJson('i1')],
      });
      final Future<DashboardData> oldDashboard = dashboard.load();
      await adapter.release('GET', kListMonitorsPath, <String, Object?>{
        'data': <Object?>[],
        'meta': <String, Object?>{'total': 0, 'page': 1, 'per_page': 100},
      });
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[_incidentJson('i1')],
      });
      await oldFeed;
      await oldDashboard;

      expect(
        (await cache.getIncidents()).data.single.acknowledgedAt,
        isNull,
        reason:
            'the reads were released after the confirmation, so they are the '
            'older fact; nothing may undo the acknowledgement on disk',
      );

      // And the memory view still reports the confirmation truthfully.
      final IncidentDetailData? confirmed = detail.confirmedDetail('i1');
      expect(confirmed, isNotNull);
      expect(confirmed!.incident.isAcknowledged, isTrue);
      expect(confirmed.savedOffline, isFalse);
    });

    test('an already-staged list write rolls back when the action confirms', () async {
      // The window the queue-boundary check cannot cover: this write has
      // already passed it and is *inside* the real transaction, with its delete
      // and inserts already issued to SQLite. The acknowledgement confirms while
      // it is there, and its own cache write then fails, so the disk revision
      // never moves and nothing else would notice.
      //
      // Held with a real QueryExecutor interceptor rather than a repository
      // seam, so the pause is genuinely after the SQL — the only place the
      // remaining check can be.
      final _WriteFailingCache failing = _WriteFailingCache(db);
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: failing,
      );
      final ApiIncidentsRepository feed = ApiIncidentsRepository(
        api: api,
        cache: failing,
      );

      // Seed the list the held write will later try to replace, so "unchanged"
      // is an assertion about real content rather than about an empty cache.
      final Future<IncidentsData> seed = feed.load();
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[_incidentJson('seeded')],
      });
      await seed;
      final DateTime seededAt = (await cache.lastSynced(kIncidentsCacheKey))!;
      expect((await cache.getIncidents()).data.single.id, 'seeded');

      // Start a read whose rows are the older Open list, and pause it once its
      // delete has been issued.
      final Completer<void> staged = Completer<void>();
      final Completer<void> release = Completer<void>();
      sqlGate.pauseNextIncidentDelete(staged, release);
      final Future<IncidentsData> held = feed.load();
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[_incidentJson('i1')],
      });
      await staged.future;

      // The server confirms the acknowledgement; that write fails before the
      // disk, so the revision cannot be what stops the staged write.
      failing.failDetailWrites = true;
      failing.failCount = 1;
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope('i1', acknowledgedAt: '2026-10-27T12:00:00Z'),
      );
      final IncidentDetailData acknowledged = await ack;
      expect(acknowledged.savedOffline, isFalse);

      release.complete();
      await held;

      expect(
        (await cache.getIncidents()).data.single.id,
        'seeded',
        reason:
            'the staged Open rows were rolled back: an acknowledgement the '
            'server confirmed is newer than any list read already in SQL',
      );
      expect(
        await cache.lastSynced(kIncidentsCacheKey),
        seededAt,
        reason:
            'and the freshness marker rolled back with them, because a commit '
            'that kept the old write time would date rows that are not there',
      );

      // The queue is still usable: a read started after the confirmation writes.
      final Future<IncidentsData> later = feed.load();
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[_incidentJson('newer')],
      });
      await later;
      expect((await cache.getIncidents()).data.single.id, 'newer');

      // And the confirmation is still the truthful memory answer.
      expect(detail.confirmedDetail('i1')!.savedOffline, isFalse);
      expect(detail.confirmedDetail('i1')!.incident.isAcknowledged, isTrue);
    });

    test('a logout at the same boundary rolls the staged write back', () async {
      // The session fence on the same commit boundary: a logout while the delete
      // is in SQL must not leave the previous account's rows behind.
      final _WriteFailingCache failing = _WriteFailingCache(db);
      final ApiIncidentsRepository feed = ApiIncidentsRepository(
        api: api,
        cache: failing,
      );

      final Future<IncidentsData> seed = feed.load();
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[_incidentJson('seeded')],
      });
      await seed;
      final DateTime seededAt = (await cache.lastSynced(kIncidentsCacheKey))!;

      final Completer<void> staged = Completer<void>();
      final Completer<void> release = Completer<void>();
      sqlGate.pauseNextIncidentDelete(staged, release);
      final Future<IncidentsData> held = feed.load();
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[_incidentJson('i1')],
      });
      await staged.future;

      // Started but not awaited: `clearAll` advances the epoch synchronously and
      // then queues the wipe *behind* the staged write, so awaiting it here would
      // wait for the very write this test is holding.
      final Future<void> logout = failing.clearAll();
      expect(
        failing.sessionEpoch,
        greaterThan(0),
        reason: 'sanity: the epoch moved before the wipe could run',
      );
      // The expectation is attached before the write is released: a load that fails
      // while this test is still awaiting the wipe would otherwise surface as an
      // unhandled error rather than as the assertion it is.
      final Future<void> rejected = expectLater(
        held,
        throwsA(isA<SessionEndedException>()),
      );
      release.complete();
      await logout;
      await rejected;

      expect((await cache.getIncidents()).data, isEmpty);
      expect(
        await cache.lastSynced(kIncidentsCacheKey),
        isNull,
        reason:
            'the wipe took the freshness marker; the staged write did not '
            'put one back',
      );
      expect(seededAt, isNotNull, reason: 'sanity: the seed really did sync');
    });

    test('a list read started after the confirmation wins and persists', () async {
      // The other direction, so the shared fence is not just "always refuse": a
      // read that starts *after* the server confirmed is the newest fact, and it
      // is stored like any other read.
      final _WriteFailingCache failing = _WriteFailingCache(db);
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: failing,
      );
      final ApiIncidentsRepository feed = ApiIncidentsRepository(
        api: api,
        cache: failing,
      );

      failing.failDetailWrites = true;
      failing.failCount = 1;
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope('i1', acknowledgedAt: '2026-10-27T12:00:00Z'),
      );
      await ack;

      // This read begins after the confirmation, and resolves the incident.
      final Future<IncidentsData> later = feed.load();
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[
          _incidentJson(
            'i1',
            acknowledgedAt: '2026-10-27T12:00:00Z',
            resolvedAt: '2026-10-27T13:00:00Z',
          ),
        ],
      });
      final IncidentsData stored = await later;

      expect(
        stored.incidents.single.resolvedAt,
        '2026-10-27T13:00:00Z',
        reason: 'a read newer than the confirmation is served normally',
      );
      expect(
        (await cache.getIncidents()).data.single.resolvedAt,
        '2026-10-27T13:00:00Z',
        reason: 'and it is persisted, so a relaunch agrees with the screen',
      );
      expect(
        (await cache.getIncidents()).data.single.acknowledgedAt,
        '2026-10-27T12:00:00Z',
      );
    });

    test('a newer resolved list still supersedes the unsaved action', () async {
      // The counterpart to the test above: memory is not blanket precedence.
      // A list read that lands *after* the unsaved acknowledgement is newer, and
      // must be what the screen shows.
      final _WriteFailingCache failing = _WriteFailingCache(db);
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: failing,
      );
      await seedOnlineRead(
        detail,
        'i1',
        updates: <Object?>[_update('before the ack')],
      );

      failing.failDetailWrites = true;
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope('i1', acknowledgedAt: '2026-10-27T12:00:00Z'),
      );
      final IncidentDetailData acknowledged = await ack;
      expect(acknowledged.savedOffline, isFalse);

      // The list read lands after the action and resolves the incident.
      final ApiIncidentsRepository feed = ApiIncidentsRepository(
        api: api,
        cache: failing,
      );
      final Future<IncidentsData> listLoad = feed.load();
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[
          _incidentJson('i1', resolvedAt: '2026-10-27T13:00:00Z'),
        ],
      });
      await listLoad;

      final Future<IncidentDetailData> offlineLoad = detail.load('i1');
      await adapter.offline('GET', incidentDetailPath('i1'));
      final IncidentDetailData offline = await offlineLoad;

      expect(
        offline.incident.resolvedAt,
        '2026-10-27T13:00:00Z',
        reason:
            'the list read is newer than the unsaved action, so the cached row '
            'is the summary to show',
      );
      expect(
        offline.updates.map((IncidentUpdate u) => u.displayTitle),
        <String>['before the ack'],
        reason: 'and the updates keep the last persisted provenance',
      );
    });

    test('an old in-flight GET cannot undo an unsaved acknowledgement after a '
        'transaction failure', () async {
      // Same race, but the write fails *inside* the transaction, after the
      // revision moved — the real ordering. The outcome must not depend on
      // which seam failed.
      final CacheRepository failing = CacheRepository(db);
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: failing,
      );

      final Future<IncidentDetailData> staleGet = detail.load('i1');
      final int revisionBefore = failing.incidentRevision;

      // The insert inside drift's transaction now fails for real, after the
      // revision has advanced and with the schema itself intact.
      await failDetailInserts(db);
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope(
          'i1',
          acknowledgedAt: '2026-10-27T12:00:00Z',
          updates: <Object?>[_update('acknowledged update')],
        ),
      );
      final IncidentDetailData acknowledged = await ack;
      expect(acknowledged.savedOffline, isFalse);
      expect(
        failing.incidentRevision,
        greaterThan(revisionBefore),
        reason:
            'this seam fails inside the transaction, so the revision really '
            'did advance — the ordering below cannot pass by accident',
      );
      expect(
        await failing.countIncidentDetails(),
        0,
        reason: 'the transaction rolled back: nothing was stored',
      );

      await adapter.release(
        'GET',
        incidentDetailPath('i1'),
        _detailEnvelope('i1', updates: <Object?>[_update('older read')]),
      );
      final IncidentDetailData result = await staleGet;

      expect(
        result.incident.isAcknowledged,
        isTrue,
        reason:
            'the confirmation is still the newer fact, and its content is '
            'what the screen gets even though the disk write failed',
      );
      expect(
        result.savedOffline,
        isFalse,
        reason: 'nothing reached storage, so nothing is promised for offline',
      );
    });

    test('an older GET cannot undo a confirmed acknowledgement', () async {
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: cache,
      );
      // A GET starts first and is still in flight.
      final Future<IncidentDetailData> staleGet = detail.load('i1');

      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope(
          'i1',
          acknowledgedAt: '2026-09-27T12:00:00Z',
          updates: <Object?>[_update('acknowledged first')],
        ),
      );
      await ack;

      // The pre-acknowledgement GET now lands with the open incident.
      await adapter.release(
        'GET',
        incidentDetailPath('i1'),
        _detailEnvelope('i1', updates: <Object?>[_update('older read')]),
      );
      final IncidentDetailData result = await staleGet;

      expect(result.incident.isAcknowledged, isTrue);
      expect(
        result.updates.single.displayTitle,
        'acknowledged first',
        reason: 'the confirmed action is the newer fact for updates too',
      );
      // And it is what is on disk, so a relaunch agrees with the screen.
      final CachedIncidentDetailSnapshot saved = (await cache.getIncidentDetail(
        'i1',
      ))!;
      expect(saved.updates.single.displayTitle, 'acknowledged first');
      expect(
        (await cache.getIncidents()).data.single.acknowledgedAt,
        '2026-09-27T12:00:00Z',
      );
    });
  });

  group('acknowledged, but not saved offline', () {
    test('a failing cache write does not become a failed mutation', () async {
      final _WriteFailingCache failing = _WriteFailingCache(db);
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: failing,
      );
      // A detail read first, so there is something to fail to update.
      await seedOnlineRead(
        detail,
        'i1',
        updates: <Object?>[_update('before the ack')],
      );

      failing.failDetailWrites = true;
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope(
          'i1',
          acknowledgedAt: '2026-09-27T12:00:00Z',
          updates: <Object?>[_update('acknowledged but unsaved')],
        ),
      );

      // The mutation did *not* fail: the server accepted it. Only the local
      // write threw, so the acknowledgement comes back as an outcome rather than
      // as an error — reporting "could not acknowledge" here would invite a
      // second acknowledgement of an already-acknowledged incident.
      final IncidentDetailData outcome = await ack;
      expect(failing.failedWrites, greaterThan(0));
      expect(
        outcome.incident.isAcknowledged,
        isTrue,
        reason: 'the server acknowledged; the local write is what failed',
      );
      expect(outcome.updates.single.displayTitle, 'acknowledged but unsaved');
      expect(
        outcome.savedOffline,
        isFalse,
        reason: 'nothing reached the cache, so nothing may be promised offline',
      );
      expect(
        interpretAcknowledge(outcome),
        isA<IncidentAcknowledgedNotSaved>(),
        reason: 'the screen reads this as acknowledged-but-unsaved',
      );
      expect(
        api.acknowledgeIncident,
        isNotNull,
        reason: 'sanity: the API surface the mutation used',
      );

      // The server's acknowledgement is what the screen shows, and it is
      // remembered for this session.
      final IncidentDetailData? confirmed = detail.confirmedDetail('i1');
      expect(confirmed, isNotNull);
      expect(confirmed!.incident.isAcknowledged, isTrue);
      expect(confirmed.updates.single.displayTitle, 'acknowledged but unsaved');
      expect(
        confirmed.savedOffline,
        isFalse,
        reason:
            'nothing was written, so no offline or relaunch promise is made',
      );
      expect(
        interpretAcknowledge(confirmed),
        isA<IncidentAcknowledgedNotSaved>(),
        reason: 'reported as acknowledged-but-unsaved, not as a failure',
      );

      // A failed refresh still shows the acknowledgement in this session.
      final Future<IncidentDetailData> unsavedAckRefresh = detail.load('i1');
      await adapter.offline('GET', incidentDetailPath('i1'));
      final IncidentDetailData offline = await unsavedAckRefresh;
      expect(offline.incident.isAcknowledged, isTrue);
      expect(offline.updates.single.displayTitle, 'acknowledged but unsaved');

      // What is on disk is untouched: the older snapshot, honestly dated.
      final CachedIncidentDetailSnapshot saved = (await cache.getIncidentDetail(
        'i1',
      ))!;
      expect(saved.updates.single.displayTitle, 'before the ack');
      expect((await cache.getIncidents()).data.single.acknowledgedAt, isNull);
    });

    test('a winning unsaved action keeps savedOffline false and its time', () async {
      final _WriteFailingCache failing = _WriteFailingCache(db);
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: failing,
      );
      await seedOnlineRead(
        detail,
        'i1',
        updates: <Object?>[_update('before the ack')],
      );
      final DateTime earlierReadAt = (await cache.getIncidentDetail('i1'))!
          .syncedAt;

      failing.failDetailWrites = true;
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope(
          'i1',
          acknowledgedAt: '2026-09-27T12:00:00Z',
          updates: <Object?>[_update('acknowledged but unsaved')],
        ),
      );
      await ack;
      final DateTime acknowledgedAt = detail
          .confirmedDetail('i1')!
          .summarySyncedAt!;

      // No newer write has landed, so the action legitimately wins over the
      // older cached row — and must bring its own truth with it rather than
      // inheriting the older snapshot's.
      final Future<IncidentDetailData> offlineLoad = detail.load('i1');
      await adapter.offline('GET', incidentDetailPath('i1'));
      final IncidentDetailData offline = await offlineLoad;

      expect(offline.incident.isAcknowledged, isTrue);
      expect(offline.updates.single.displayTitle, 'acknowledged but unsaved');
      expect(
        offline.updatesSyncedAt,
        acknowledgedAt,
        reason:
            'the winning action reports its own read time, not the older '
            'snapshot\'s',
      );
      expect(offline.summarySyncedAt, acknowledgedAt);
      expect(
        offline.savedOffline,
        isFalse,
        reason:
            'nothing was written, so serving this from cache must not claim it '
            'was saved',
      );
      expect(
        earlierReadAt.isBefore(acknowledgedAt),
        isTrue,
        reason: 'the acknowledged read is the later of the two',
      );
    });

    test('a later list read supersedes the unsaved action in memory', () async {
      final _WriteFailingCache failing = _WriteFailingCache(db);
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: failing,
      );
      await seedOnlineRead(detail, 'i1');

      failing.failDetailWrites = true;
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope('i1', acknowledgedAt: '2026-09-27T12:00:00Z'),
      );
      final IncidentDetailData acknowledged = await ack;
      expect(acknowledged.savedOffline, isFalse);

      // A list read lands afterwards: it is the newer summary, so it wins over
      // the unsaved in-memory action rather than being ignored.
      final ApiIncidentsRepository feed = ApiIncidentsRepository(
        api: api,
        cache: failing,
      );
      final Future<IncidentsData> listLoad = feed.load();
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[
          _incidentJson('i1', resolvedAt: '2026-09-27T13:00:00Z'),
        ],
      });
      await listLoad;

      final Future<IncidentDetailData> supersededLoad = detail.load('i1');
      await adapter.offline('GET', incidentDetailPath('i1'));
      final IncidentDetailData offline = await supersededLoad;

      expect(
        offline.incident.resolvedAt,
        '2026-09-27T13:00:00Z',
        reason:
            'the list read is newer than the unsaved action, so the row on disk '
            'is the summary to show',
      );
    });
  });

  group('the screen after a real storage failure', () {
    // The end-to-end claim, through the real screen, the real controller and the
    // real cache: the server accepted the acknowledgement and the local write
    // then failed, so the screen has to report it truthfully and must not dress a
    // successful mutation up as a failed one.
    //
    // Network answers are immediate rather than gated here. A gated response
    // needs real timers, and a widget test only advances those from
    // `runAsync`; the ordering this test cares about is the *cache* write failing
    // after the API accepted, which `_WriteFailingCache` controls precisely.
    testWidgets('acknowledged, disabled, refreshed, and never a generic failure', (
      WidgetTester tester,
    ) async {
      final _ImmediateApi server = _ImmediateApi();
      final _WriteFailingCache failing = _WriteFailingCache(db);
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: UptrackApi(dio: Dio()..httpClientAdapter = server),
        cache: failing,
      );

      // The first read, from the server: open, with one update.
      server.detail = _detailEnvelope(
        'i1',
        updates: <Object?>[_update('investigating')],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            incidentDetailRepositoryProvider.overrideWithValue(detail),
            // The success path invalidates the feed and the dashboard too, so
            // they are overridden rather than left to build a real API client in
            // a widget test.
            incidentsProvider.overrideWith(
              (Ref ref) async =>
                  const IncidentsData(incidents: <Incident>[], offline: false),
            ),
            dashboardProvider.overrideWith(
              (Ref ref) async => const DashboardData(
                totalMonitors: 0,
                loadedMonitors: 0,
                totalMonitorsKnown: false,
                countsByStatus: <String, int>{},
                averageUptime: 0,
                offline: false,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const IncidentDetailScreen(incidentId: 'i1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Acknowledge'), findsOneWidget);

      // The acknowledgement is accepted by the server; only the local write fails.
      failing.failDetailWrites = true;
      failing.failCount = 1;
      server.detail = _detailEnvelope(
        'i1',
        acknowledgedAt: '2026-09-27T12:00:00Z',
        updates: <Object?>[_update('acknowledged by us')],
      );
      await tester.tap(find.text('Acknowledge'));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not acknowledge this incident. Try again.'),
        findsNothing,
        reason:
            'the server accepted the action, so this failure copy would be a lie '
            'and would invite a second acknowledgement of an already '
            'acknowledged incident',
      );
      expect(
        find.text(
          'Acknowledged. Escalation is paused. This device could not save the '
          'update offline, so it may not be here without a connection.',
        ),
        findsOneWidget,
        reason:
            'the truthful outcome: acknowledged, with the save problem stated',
      );
      expect(find.widgetWithText(Chip, 'Acknowledged'), findsOneWidget);

      // The controls follow the state the server now has.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Acknowledge'),
            )
            .onPressed,
        isNull,
        reason: 'a second acknowledgement must not be offered',
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Escalate'),
            )
            .onPressed,
        isNull,
        reason: 'escalation is a server no-op once acknowledged',
      );

      // The success path really did refresh the surfaces: the invalidation it
      // performs re-ran the detail read, which this adapter recorded.
      expect(
        server.requests.where(
          (String r) => r == 'GET ${incidentDetailPath('i1')}',
        ),
        hasLength(2),
        reason: 'one read before the action, one from the refresh after it',
      );

      // The refresh that followed the failed write succeeded, so the
      // acknowledgement genuinely reached the disk by the end of this test. The
      // screen still reported the failed save, because that is what happened when
      // the action completed — the outcome describes the action, not the state
      // minutes later.
      final IncidentDetailData? shown = detail.confirmedDetail('i1');
      expect(shown, isNotNull);
      expect(shown!.incident.isAcknowledged, isTrue);
      final List<CachedIncident> rows = (await failing.getIncidents()).data;
      expect(rows.single.acknowledgedAt, '2026-09-27T12:00:00Z');
      expect(
        await failing.countIncidentDetails(),
        1,
        reason: 'the updates too',
      );
    });
  });

  group('session fences still hold', () {
    test('a logout drops an unsaved acknowledgement', () async {
      final _WriteFailingCache failing = _WriteFailingCache(db);
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: failing,
      );
      await seedOnlineRead(detail, 'i1');

      failing.failDetailWrites = true;
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope('i1', acknowledgedAt: '2026-09-27T12:00:00Z'),
      );
      final IncidentDetailData acknowledged = await ack;
      expect(acknowledged.incident.isAcknowledged, isTrue);
      expect(acknowledged.savedOffline, isFalse);
      expect(detail.confirmedDetail('i1'), isNotNull);

      await failing.clearAll();

      expect(
        detail.confirmedDetail('i1'),
        isNull,
        reason:
            'an acknowledgement from an ended session must not leak to the '
            'next account',
      );
      // And the next account gets nothing from the cache either.
      final Future<IncidentDetailData> nextSession = detail.load('i1');
      await adapter.offline('GET', incidentDetailPath('i1'));
      await expectLater(nextSession, throwsA(isA<DioException>()));
    });

    test(
      'an acknowledge whose write lands after a logout is rejected',
      () async {
        final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
          api: api,
          cache: cache,
        );
        final Future<IncidentDetailData> ack = detail.acknowledge('i1');

        await cache.clearAll();
        await adapter.release(
          'POST',
          incidentAcknowledgePath('i1'),
          _detailEnvelope('i1', acknowledgedAt: '2026-09-27T12:00:00Z'),
        );

        await expectLater(ack, throwsA(isA<SessionEndedException>()));
        expect(await cache.countIncidentDetails(), 0);
      },
    );
  });
}
