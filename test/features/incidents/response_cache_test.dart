import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/api/models/monitor.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_controller.dart';
import 'package:uptrack_mobile/features/incidents/incidents_controller.dart';

/// Fake adapter whose responses are released by the test, so ordering
/// between a request, an acknowledgement and a logout is deterministic.
class _GatedAdapter implements HttpClientAdapter {
  /// Pending requests keyed by `METHOD path`, each completed by the test so
  /// the order of requests, mutations and a logout is fully controlled.
  final Map<String, Completer<ResponseBody>> _pending =
      <String, Completer<ResponseBody>>{};

  Future<ResponseBody> _handle(RequestOptions options) {
    final String key = '${options.method} ${options.path}';
    final Completer<ResponseBody> completer = Completer<ResponseBody>();
    _pending[key] = completer;
    return completer.future;
  }

  /// Completes the pending request for `METHOD path` with [body].
  Future<void> release(String method, String path, Object? body) =>
      _complete(method, path, body, 200);

  /// Completes it with a failure status instead.
  Future<void> fail(String method, String path, int status, Object? body) =>
      _complete(method, path, body, status);

  Future<void> _complete(
    String method,
    String path,
    Object? body,
    int status,
  ) async {
    // Dio reaches the adapter asynchronously, so the gate may not exist yet.
    final Completer<ResponseBody> gate = await _gateFor(method, path);
    // Dropped once answered, so a later release/fail for the same path parks a
    // fresh request instead of completing a finished one.
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

  /// Waits for the request to reach the adapter, then returns its gate.
  Future<Completer<ResponseBody>> _gateFor(String method, String path) async {
    final String key = '$method $path';
    for (int attempt = 0; attempt < 100; attempt++) {
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

/// [CacheRepository] whose reads can be parked, so a test can end the session
/// *while* cached rows are being read.
///
/// This is the window a session check made only before the read cannot see:
/// the epoch still matches when the read starts and no longer matches when it
/// completes, so only a recheck after the await rejects the load.
///
/// The rows are captured *before* the park on purpose. Parking first would
/// let `clearAll` delete the rows, so the released read would return nothing
/// and the test would only prove that the wipe happened — the same outcome
/// whether or not the post-read fence exists. Capturing first means the
/// snapshot handed back after the release is the recognisable pre-logout
/// content, so the test fails as a *visible leak* when the fence is missing.
class _GatedCache extends CacheRepository {
  _GatedCache(super.db);

  /// Armed until a read captures its rows, then disarmed so later reads are
  /// not parked again.
  Completer<void>? _monitorGate;
  Completer<void>? _incidentGate;

  /// The gate a captured read is parked on. Kept separately because the
  /// capture disarms [_monitorGate]/[_incidentGate] before parking, and the
  /// test still has to be able to release that read.
  Completer<void>? _parkedMonitorRead;
  Completer<void>? _parkedIncidentRead;

  /// The snapshot the last captured read will hand back, so a test can assert
  /// the old rows really were in flight when the session ended.
  CachedList<CachedMonitor>? capturedMonitors;
  CachedList<CachedIncident>? capturedIncidents;

  final Completer<void> _monitorReadStarted = Completer<void>();
  final Completer<void> _incidentReadStarted = Completer<void>();

  /// Parks the next [getMonitors] until [releaseMonitorRead] is called.
  void gateMonitorRead() => _monitorGate = Completer<void>();

  /// Parks the next [getIncidents] until [releaseIncidentRead] is called.
  void gateIncidentRead() => _incidentGate = Completer<void>();

  /// Completes once a parked monitor read has captured its rows.
  Future<void> get monitorReadStarted => _monitorReadStarted.future;

  /// Completes once a parked incident read has captured its rows.
  Future<void> get incidentReadStarted => _incidentReadStarted.future;

  void releaseMonitorRead() {
    final Completer<void>? gate = _parkedMonitorRead ?? _monitorGate;
    _monitorGate = null;
    _parkedMonitorRead = null;
    gate?.complete();
  }

  void releaseIncidentRead() {
    final Completer<void>? gate = _parkedIncidentRead ?? _incidentGate;
    _incidentGate = null;
    _parkedIncidentRead = null;
    gate?.complete();
  }

  @override
  Future<CachedList<CachedMonitor>> getMonitors() async {
    final Completer<void>? gate = _monitorGate;
    if (gate == null) {
      return super.getMonitors();
    }
    final CachedList<CachedMonitor> captured = await super.getMonitors();
    // Disarmed before parking, so the read that resumes (and any later read)
    // is not parked again; the gate it waits on is the one released above.
    _monitorGate = null;
    _parkedMonitorRead = gate;
    capturedMonitors = captured;
    _monitorReadStarted.complete();
    await gate.future;
    return captured;
  }

  @override
  Future<CachedList<CachedIncident>> getIncidents() async {
    final Completer<void>? gate = _incidentGate;
    if (gate == null) {
      return super.getIncidents();
    }
    final CachedList<CachedIncident> captured = await super.getIncidents();
    _incidentGate = null;
    _parkedIncidentRead = gate;
    capturedIncidents = captured;
    _incidentReadStarted.complete();
    await gate.future;
    return captured;
  }
}

IncidentSnapshot _snapshot(String id, {String? acknowledgedAt}) =>
    IncidentSnapshot(
      id: id,
      monitorId: 'm1',
      monitorName: 'Homepage',
      status: 'ongoing',
      insertedAt: '2026-09-27T10:00:00Z',
      acknowledgedAt: acknowledgedAt,
    );

Monitor _monitor(String id) => Monitor(
  id: id,
  name: 'Homepage',
  url: 'https://example.com',
  monitorType: 'http',
  status: 'up',
  interval: 60,
  timeout: 10,
  confirmationWindow: 'immediate',
  regionsRequired: 'any',
  createdAt: '2026-09-01T00:00:00Z',
  updatedAt: '2026-09-27T10:00:00Z',
);

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

/// One recognisable posted update, so a test can tell *whose* detail the
/// screen was handed.
Map<String, Object?> _update(String title) => <String, Object?>{
  'id': 7,
  'status': title,
  'title': title,
  'posted_at': '2026-09-27T10:06:00Z',
};

/// Asserts that [load], whose cache read captured rows before the session
/// ended, hands the screen nothing and reports the ended session instead.
///
/// The content check runs *before* the error check on purpose: a load that
/// completes with pre-logout rows is a visible leak, and reporting that as a
/// missing or differently-typed exception would understate it.
Future<void> expectLogoutServesNothing(
  Future<Object?> load, {
  required String reason,
}) async {
  Object? served = 'nothing served';
  Object? error;
  await load.then<void>(
    (Object? data) {
      served = data;
    },
    onError: (Object err) {
      error = err;
    },
  );
  expect(served, 'nothing served', reason: reason);
  expect(
    error,
    isA<SessionEndedException>(),
    reason: 'a load that withholds the rows must report the ended session',
  );
}

void main() {
  late AppDatabase db;
  late CacheRepository cache;
  late _GatedAdapter adapter;
  late Dio dio;
  late UptrackApi api;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    cache = CacheRepository(db);
    adapter = _GatedAdapter();
    dio = Dio()..httpClientAdapter = adapter;
    api = UptrackApi(dio: dio);
  });

  tearDown(() async {
    await db.close();
    dio.close(force: true);
  });

  group('acknowledge persists the authoritative detail', () {
    test('a failed refresh keeps the acknowledgement', () async {
      final ApiIncidentDetailRepository repo = ApiIncidentDetailRepository(
        api: api,
        cache: cache,
      );

      final Future<IncidentDetailData> ack = repo.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope('i1', acknowledgedAt: '2026-09-27T10:05:00Z'),
      );
      final IncidentDetailData acknowledged = await ack;
      expect(acknowledged.incident.isAcknowledged, isTrue);

      // Now the refresh fails (device went offline).
      adapter.fail('GET', incidentDetailPath('i1'), 503, <String, Object?>{
        'error': 'unavailable',
      });
      final IncidentDetailData offline = await repo.load('i1');

      expect(offline.offline, isTrue);
      expect(
        offline.incident.isAcknowledged,
        isTrue,
        reason: 'a confirmed acknowledgement must survive a failed refresh',
      );
    });

    test('an older GET that lands after the ack cannot undo it', () async {
      final ApiIncidentDetailRepository repo = ApiIncidentDetailRepository(
        api: api,
        cache: cache,
      );

      // A GET starts first and is still in flight.
      final Future<IncidentDetailData> staleGet = repo.load('i1');

      final Future<IncidentDetailData> ack = repo.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope('i1', acknowledgedAt: '2026-09-27T10:05:00Z'),
      );
      expect((await ack).incident.isAcknowledged, isTrue);

      // The pre-ack GET now returns the unacknowledged incident.
      await adapter.release(
        'GET',
        incidentDetailPath('i1'),
        _detailEnvelope('i1'),
      );
      final IncidentDetailData result = await staleGet;

      expect(
        result.incident.isAcknowledged,
        isTrue,
        reason: 'a GET that started before the ack must not overwrite it',
      );
    });

    test('a list response that lands after the ack cannot undo it', () async {
      final ApiIncidentsRepository feed = ApiIncidentsRepository(
        api: api,
        cache: cache,
      );

      // Feed load starts first.
      final Future<IncidentsData> feedLoad = feed.load();

      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: cache,
      );
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope('i1', acknowledgedAt: '2026-09-27T10:05:00Z'),
      );
      await ack;

      // The older list response arrives with the pre-ack row.
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[_incidentJson('i1')],
      });
      final IncidentsData data = await feedLoad;

      expect(data.incidents.single.isAcknowledged, isTrue);
      expect(
        (await cache.getIncidents()).data.single.acknowledgedAt,
        '2026-09-27T10:05:00Z',
      );
    });
  });

  group('logout fences in-flight responses', () {
    test('a list response after clearAll is rejected', () async {
      final ApiIncidentsRepository feed = ApiIncidentsRepository(
        api: api,
        cache: cache,
      );
      final Future<IncidentsData> load = feed.load();

      await cache.clearAll();
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[_incidentJson('i1')],
      });

      await expectLater(load, throwsA(isA<SessionEndedException>()));
      expect(
        (await cache.getIncidents()).data,
        isEmpty,
        reason: 'a pre-logout response must not reach the cache',
      );
    });

    test('a detail response after clearAll is rejected', () async {
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: cache,
      );
      final Future<IncidentDetailData> load = detail.load('i1');

      await cache.clearAll();
      await adapter.release(
        'GET',
        incidentDetailPath('i1'),
        _detailEnvelope('i1'),
      );

      await expectLater(load, throwsA(isA<SessionEndedException>()));
    });

    test(
      'a failed detail load after clearAll does not use the old session',
      () async {
        final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
          api: api,
          cache: cache,
        );
        // Confirm an acknowledgement first, so a stale in-memory row exists.
        final Future<IncidentDetailData> ack = detail.acknowledge('i1');
        await adapter.release(
          'POST',
          incidentAcknowledgePath('i1'),
          _detailEnvelope('i1', acknowledgedAt: '2026-09-27T10:05:00Z'),
        );
        await ack;

        final Future<IncidentDetailData> load = detail.load('i1');
        await cache.clearAll();
        adapter.fail('GET', incidentDetailPath('i1'), 503, <String, Object?>{
          'error': 'unavailable',
        });

        await expectLater(load, throwsA(isA<SessionEndedException>()));
      },
    );

    test('an acknowledge response after clearAll is rejected', () async {
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: cache,
      );
      final Future<IncidentDetailData> ack = detail.acknowledge('i1');

      await cache.clearAll();
      await adapter.release(
        'POST',
        incidentAcknowledgePath('i1'),
        _detailEnvelope('i1', acknowledgedAt: '2026-09-27T10:05:00Z'),
      );

      await expectLater(ack, throwsA(isA<SessionEndedException>()));
      expect(
        (await cache.getIncidents()).data,
        isEmpty,
        reason: 'a pre-logout mutation must not repopulate the wiped cache',
      );
    });

    test('the dashboard does not repopulate monitors after clearAll', () async {
      final ApiDashboardRepository dashboard = ApiDashboardRepository(
        api: api,
        cache: cache,
      );
      final Future<DashboardData> load = dashboard.load();

      await cache.clearAll();
      await adapter.release('GET', kListMonitorsPath, <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': 'm1',
            'name': 'Homepage',
            'url': 'https://example.com',
            'monitor_type': 'http',
            'status': 'up',
            'interval': 60,
            'timeout': 10,
            'confirmation_window': 'immediate',
            'regions_required': 'any',
            'created_at': '2026-09-01T00:00:00Z',
            'updated_at': '2026-09-27T10:00:00Z',
          },
        ],
        'meta': <String, Object?>{'total': 1, 'page': 1, 'per_page': 100},
      });
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[_incidentJson('i1')],
      });

      await expectLater(load, throwsA(isA<SessionEndedException>()));
      expect((await cache.getMonitors()).data, isEmpty);
      expect((await cache.getIncidents()).data, isEmpty);
    });
  });

  group('confirmed detail is scoped to its session', () {
    // The detail repository is a provider singleton, so it is reused after a
    // logout. Its in-memory confirmation is scoped by the cache's session
    // epoch: without that, the next account's failed GET for an incident id
    // the previous account had confirmed falls back straight to the previous
    // account's content, because the cache rows are gone but the map is not.
    test(
      'a confirmation from an ended session is neither exposed nor served',
      () async {
        final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
          api: api,
          cache: cache,
        );

        // Session A: a successful load, then an acknowledgement, both with
        // recognisable updates.
        final Future<IncidentDetailData> loadA = detail.load('i1');
        await adapter.release(
          'GET',
          incidentDetailPath('i1'),
          _detailEnvelope('i1', updates: <Object?>[_update('session-a-load')]),
        );
        expect((await loadA).updates.single.displayTitle, 'session-a-load');

        final Future<IncidentDetailData> ackA = detail.acknowledge('i1');
        await adapter.release(
          'POST',
          incidentAcknowledgePath('i1'),
          _detailEnvelope(
            'i1',
            acknowledgedAt: '2026-09-27T10:05:00Z',
            updates: <Object?>[_update('session-a-ack')],
          ),
        );
        expect((await ackA).updates.single.displayTitle, 'session-a-ack');
        expect(
          detail.confirmedDetail('i1')?.updates.single.displayTitle,
          'session-a-ack',
        );

        await cache.clearAll();

        expect(
          detail.confirmedDetail('i1'),
          isNull,
          reason: 'a confirmation from an ended session must not be exposed',
        );

        // The next session's request captures the *current* epoch, so every
        // session fence passes; only the epoch-scoped confirmation can still
        // leak here. Nothing may be served, so the failure must be reported.
        adapter.fail('GET', incidentDetailPath('i1'), 503, <String, Object?>{
          'error': 'unavailable',
        });
        await expectLater(detail.load('i1'), throwsA(isA<DioException>()));
      },
    );

    test(
      'a new session confirms and falls back only to its own content',
      () async {
        final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
          api: api,
          cache: cache,
        );

        // Session A leaves a confirmation behind.
        final Future<IncidentDetailData> loadA = detail.load('i1');
        await adapter.release(
          'GET',
          incidentDetailPath('i1'),
          _detailEnvelope('i1', updates: <Object?>[_update('session-a-load')]),
        );
        await loadA;
        await cache.clearAll();

        // Session B confirms the same incident id with its own updates.
        final Future<IncidentDetailData> loadB = detail.load('i1');
        await adapter.release(
          'GET',
          incidentDetailPath('i1'),
          _detailEnvelope('i1', updates: <Object?>[_update('session-b-load')]),
        );
        expect((await loadB).updates.single.displayTitle, 'session-b-load');

        // Its failed refresh falls back to session B's confirmation only.
        adapter.fail('GET', incidentDetailPath('i1'), 503, <String, Object?>{
          'error': 'unavailable',
        });
        final IncidentDetailData offline = await detail.load('i1');

        expect(offline.offline, isTrue);
        expect(
          offline.updates.map((IncidentUpdate u) => u.displayTitle),
          <String>['session-b-load'],
          reason:
              'the offline fallback must be the current session content only',
        );
      },
    );
  });

  group('logout during a cache read', () {
    // A session check made only before an awaited cache read cannot see a
    // logout that lands while the read is in flight (TOCTOU). Each test below
    // captures the cache rows, parks the read, ends the session, then releases
    // it. The captured snapshot is asserted NON-empty *before* the wipe, so
    // the released read genuinely holds pre-logout rows: without the post-read
    // fence those rows reach the screen (a visible leak) instead of merely
    // changing which exception is thrown.
    test('an offline feed fallback that spans the logout returns nothing', () async {
      final _GatedCache gated = _GatedCache(db);
      await gated.saveIncidents(
        <IncidentSnapshot>[_snapshot('i-old-session')],
        session: gated.sessionEpoch,
        revision: gated.incidentRevision,
      );
      final ApiIncidentsRepository feed = ApiIncidentsRepository(
        api: api,
        cache: gated,
      );

      gated.gateIncidentRead();
      final Future<IncidentsData> load = feed.load();
      await adapter.fail('GET', kIncidentsPath, 503, <String, Object?>{
        'error': 'unavailable',
      });
      // The read has captured the old rows and is now parked; the logout lands.
      await gated.incidentReadStarted;
      expect(
        gated.capturedIncidents?.data.map((CachedIncident row) => row.id),
        <String>['i-old-session'],
        reason: 'the parked read must be holding the pre-logout rows',
      );
      await gated.clearAll();
      gated.releaseIncidentRead();

      await expectLogoutServesNothing(
        load,
        reason: 'rows captured across the logout must not reach the screen',
      );
    });

    test(
      'an offline detail fallback that spans the logout returns nothing',
      () async {
        final _GatedCache gated = _GatedCache(db);
        await gated.saveIncidents(
          <IncidentSnapshot>[_snapshot('i-old-session')],
          session: gated.sessionEpoch,
          revision: gated.incidentRevision,
        );
        final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
          api: api,
          cache: gated,
        );

        gated.gateIncidentRead();
        final Future<IncidentDetailData> load = detail.load('i-old-session');
        await adapter.fail(
          'GET',
          incidentDetailPath('i-old-session'),
          503,
          <String, Object?>{'error': 'unavailable'},
        );
        await gated.incidentReadStarted;
        expect(
          gated.capturedIncidents?.data.map((CachedIncident row) => row.id),
          <String>['i-old-session'],
          reason: 'the parked read must be holding the pre-logout row',
        );
        await gated.clearAll();
        gated.releaseIncidentRead();

        await expectLogoutServesNothing(
          load,
          reason: 'the cached row belongs to the session the logout ended',
        );
      },
    );

    test('a fenced list reload that spans the logout returns nothing', () async {
      final _GatedCache gated = _GatedCache(db);
      await gated.saveIncidents(
        <IncidentSnapshot>[_snapshot('i-old-session')],
        session: gated.sessionEpoch,
        revision: gated.incidentRevision,
      );
      final ApiIncidentsRepository feed = ApiIncidentsRepository(
        api: api,
        cache: gated,
      );

      gated.gateIncidentRead();
      final Future<IncidentsData> load = feed.load();
      // A confirmed mutation bumps the revision, so the in-flight list write is
      // fenced and the repository reloads from the cache instead.
      await gated.upsertIncident(
        _snapshot('i-ack'),
        session: gated.sessionEpoch,
      );
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[_incidentJson('i1')],
      });
      // The fenced reload has captured the old rows and is parked.
      await gated.incidentReadStarted;
      expect(
        gated.capturedIncidents?.data.map((CachedIncident row) => row.id),
        isNotEmpty,
        reason: 'the parked reload must be holding pre-logout rows',
      );
      await gated.clearAll();
      gated.releaseIncidentRead();

      await expectLogoutServesNothing(
        load,
        reason: 'the fenced reload must not serve pre-logout rows',
      );
    });

    test(
      'a dashboard fallback that spans the logout returns nothing',
      () async {
        final _GatedCache gated = _GatedCache(db);
        await gated.saveMonitors(<Monitor>[
          _monitor('m-old-session'),
        ], session: gated.sessionEpoch);
        final ApiDashboardRepository dashboard = ApiDashboardRepository(
          api: api,
          cache: gated,
        );

        gated.gateMonitorRead();
        final Future<DashboardData> load = dashboard.load();
        await adapter.fail('GET', kListMonitorsPath, 503, <String, Object?>{
          'error': 'unavailable',
        });
        await gated.monitorReadStarted;
        expect(
          gated.capturedMonitors?.data.map((CachedMonitor row) => row.id),
          <String>['m-old-session'],
          reason: 'the parked read must be holding the pre-logout monitors',
        );
        await gated.clearAll();
        gated.releaseMonitorRead();

        await expectLogoutServesNothing(
          load,
          reason:
              'monitors captured across the logout must not reach the screen',
        );
      },
    );
  });

  group('response mutations reach the API seam', () {
    test('escalate and snooze use the existing client paths', () async {
      final ApiIncidentDetailRepository detail = ApiIncidentDetailRepository(
        api: api,
        cache: cache,
      );

      final Future<EscalateResult> escalate = detail.escalate('i1');
      await adapter.release(
        'POST',
        incidentEscalatePath('i1'),
        <String, Object?>{'escalated': true, 'steps_fired': 2},
      );
      final EscalateResult escalated = await escalate;
      expect(escalated.escalated, isTrue);
      expect(escalated.stepsFired, 2);

      final Future<SnoozeResult> snooze = detail.snooze('m1');
      await adapter.release('POST', monitorSnoozePath('m1'), <String, Object?>{
        'snoozed_until': '2026-09-27T11:00:00Z',
      });
      expect((await snooze).snoozedUntil, '2026-09-27T11:00:00Z');
    });
  });
}
