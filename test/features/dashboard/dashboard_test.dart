import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Tristate;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/api/models/monitor.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/app.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_controller.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_screen.dart';
import 'package:uptrack_mobile/features/incidents/incidents_controller.dart';

/// `2026-09-26T00:00:00Z` plus [hours], so ordering tests read as times rather
/// than as string literals.
String at(int hours) {
  final DateTime base = DateTime.utc(2026, 9, 26);
  return base.add(Duration(hours: hours)).toIso8601String();
}

Incident _incident(
  String id,
  String monitorName, {
  String? startedAt = '2026-09-26T00:00:00Z',
  String? insertedAt = '2026-09-26T00:00:00Z',
  String? acknowledgedAt,
  String? resolvedAt,
}) => Incident(
  id: id,
  monitorId: 'monitor-$id',
  status: 'ongoing',
  insertedAt: insertedAt ?? at(0),
  monitorName: monitorName,
  startedAt: startedAt,
  acknowledgedAt: acknowledgedAt,
  resolvedAt: resolvedAt,
);

/// Ongoing and unacknowledged: the response queue.
///
/// A null [hours] builds a row with **no usable date at all** — the model
/// requires `inserted_at`, so "absent" is expressed as a blank value the client
/// cannot parse, which is exactly how the ordering rules see it.
Incident _outstanding(String id, String monitorName, {int? hours}) => _incident(
  id,
  monitorName,
  startedAt: hours == null ? null : at(hours),
  insertedAt: hours == null ? '' : at(hours),
);

/// Ongoing and acknowledged: the acknowledgement is on record.
Incident _owned(String id, String monitorName, {int? hours = 1}) => _incident(
  id,
  monitorName,
  startedAt: hours == null ? '' : at(hours),
  insertedAt: hours == null ? '' : at(hours),
  acknowledgedAt: at(1),
);

/// Resolved: history.
Incident _resolved(String id, String monitorName, {int? hours = 1}) =>
    _incident(
      id,
      monitorName,
      startedAt: hours == null ? '' : at(hours),
      insertedAt: hours == null ? '' : at(hours),
      resolvedAt: at((hours ?? 0) + 1),
    );

DashboardData _data({
  Map<String, int>? counts,
  int total = 3,
  int loaded = 3,
  bool totalKnown = true,
  double? uptime = 99.9,
  List<Incident>? incidents,
  bool offline = false,
}) => DashboardData(
  totalMonitors: total,
  loadedMonitors: loaded,
  totalMonitorsKnown: totalKnown,
  countsByStatus: counts ?? <String, int>{'up': 2, 'down': 1},
  averageUptime: uptime,
  incidents: incidents == null
      ? DashboardIncidents.empty
      : partitionIncidents(incidents),
  offline: offline,
);

/// Fake [DashboardRepository] returning canned data or throwing on demand.
class FakeDashboardRepository implements DashboardRepository {
  FakeDashboardRepository({required this.onLoad});

  Future<DashboardData> Function() onLoad;
  int loads = 0;

  @override
  Future<DashboardData> load() async {
    loads++;
    return onLoad();
  }
}

DioException _boom() => DioException(
  requestOptions: RequestOptions(path: '/api/monitors'),
  message: 'Connection refused',
);

/// Serves dashboard loads from canned bodies, recording every request so a
/// test can prove the incidents endpoint is read exactly once.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.bodies);

  final Map<String, Object?> bodies;
  final List<String> requests = <String>[];
  bool offline = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add('${options.method} ${options.path}');
    if (offline) {
      throw DioException(
        requestOptions: options,
        message: 'Connection refused',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(
        bodies[options.path] ?? <String, Object?>{'data': <Object?>[]},
      ),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A [CacheRepository] that can hold an incident read open, so a test can land a
/// logout in the window between reading the cached rows and reading their sync
/// time.
///
/// The hold is released by [release] and entered at most once, so the test can
/// wait for the load to actually be inside it.
class _MetadataHoldingCache extends CacheRepository {
  _MetadataHoldingCache(super.db);

  /// When set, the next [getIncidents] waits for [release] after signalling
  /// [held].
  Completer<void>? held;
  Completer<void>? release;

  @override
  Future<CachedList<CachedIncident>> getIncidents() async {
    final Completer<void>? entered = held;
    final Completer<void>? gate = release;
    if (entered != null && gate != null) {
      held = null;
      entered.complete();
      await gate.future;
    }
    return super.getIncidents();
  }
}

/// Canned feed rows for the router test that follows a dashboard link.
class _FakeIncidentsRepository implements IncidentsRepository {
  _FakeIncidentsRepository(this.incidents);

  final List<Incident> incidents;

  @override
  Future<IncidentsData> load() async =>
      IncidentsData(incidents: incidents, offline: false);
}

Future<void> pumpDashboard(
  WidgetTester tester,
  FakeDashboardRepository repo, {
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dashboardRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: const DashboardScreen(),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls the dashboard list until [finder] is on screen, so a section below
/// the fold is asserted as rendered rather than merely present in the tree.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

/// One `GET /api/incidents` envelope.
Map<String, Object?> incidentsBody(List<Map<String, Object?>> rows) =>
    <String, Object?>{'data': rows};

Map<String, Object?> incidentRow(
  String id, {
  String monitorName = 'Homepage',
  String? startedAt,
  String? insertedAt,
  String? acknowledgedAt,
  String? resolvedAt,
}) => <String, Object?>{
  'id': id,
  'monitor_id': 'monitor-$id',
  'monitor_name': monitorName,
  'status': resolvedAt == null ? 'ongoing' : 'resolved',
  'inserted_at': insertedAt ?? at(0),
  'started_at': startedAt,
  'acknowledged_at': acknowledgedAt,
  'resolved_at': resolvedAt,
};

/// `GET /api/monitors` envelope whose meta total can disagree with its rows, the
/// way a real page of 100 out of 137 does.
Map<String, Object?> monitorsBody({
  required int rows,
  required int total,
  String status = 'up',
  double? uptime = 99.9,
}) => <String, Object?>{
  'data': <Object?>[
    for (int i = 0; i < rows; i++)
      <String, Object?>{
        'id': 'm$i',
        'name': 'Monitor $i',
        'url': 'https://m$i.example.com',
        'monitor_type': 'http',
        'status': status,
        'interval': 60,
        'timeout': 10,
        'confirmation_window': 'immediate',
        'regions_required': 'any',
        'created_at': at(0),
        'updated_at': at(1),
        'uptime_percentage': uptime,
      },
  ],
  'meta': <String, Object?>{'total': total, 'page': 1, 'per_page': 100},
};

void main() {
  group('dashboard pure helpers', () {
    test('countByStatus groups by exact status', () {
      expect(
        countByStatus(const <String>['up', 'down', 'up', 'paused']),
        <String, int>{'up': 2, 'down': 1, 'paused': 1},
      );
      expect(countByStatus(const <String>[]), isEmpty);
    });

    test('averageUptime skips nulls; null when all missing', () {
      expect(averageUptime(const <double?>[100, 90, null]), 95);
      expect(averageUptime(const <double?>[null]), isNull);
      expect(averageUptime(const <double?>[]), isNull);
    });

    test('incident displayName falls back to the id', () {
      expect(_incident('i1', 'Homepage').displayName, 'Homepage');
      expect(_incident('i9', '').displayName, 'Incident i9');
    });
  });

  group('partitionIncidents', () {
    test('splits the queue, the owned incidents and the history', () {
      final DashboardIncidents sections = partitionIncidents(<Incident>[
        _outstanding('a', 'A', hours: 1),
        _owned('b', 'B', hours: 2),
        _resolved('c', 'C', hours: 3),
        _outstanding('d', 'D', hours: 4),
      ]);

      expect(sections.needsAcknowledgement.map((Incident i) => i.id), <String>[
        'a',
        'd',
      ], reason: 'ongoing and unacknowledged, oldest first');
      expect(sections.acknowledgedOngoing.map((Incident i) => i.id), <String>[
        'b',
      ]);
      expect(sections.recentResolved.map((Incident i) => i.id), <String>['c']);
      expect(sections.outstandingCount, 2);
    });

    test('an acknowledged incident is never in the response queue', () {
      final DashboardIncidents sections = partitionIncidents(<Incident>[
        _owned('owned', 'Owned'),
      ]);

      expect(sections.needsAcknowledgement, isEmpty);
      expect(sections.acknowledgedOngoing, hasLength(1));
    });

    test('missing and unparseable dates sort last, then by id', () {
      final DashboardIncidents sections = partitionIncidents(<Incident>[
        _outstanding('zzz-undated', 'Z'),
        _outstanding('bbb-undated', 'B'),
        _outstanding('dated', 'D', hours: 9),
        // Same as missing: a value the client cannot parse must not be guessed
        // at, and must not throw either.
        _incident(
          'aaa-garbage',
          'G',
          startedAt: 'not-a-date',
          insertedAt: 'not-a-date',
        ),
      ]);

      expect(
        sections.needsAcknowledgement.map((Incident i) => i.id),
        <String>['dated', 'aaa-garbage', 'bbb-undated', 'zzz-undated'],
        reason:
            'dated incidents come first; an undated row is never presented as '
            'the oldest outstanding one, and rows without a usable date keep a '
            'stable order instead of following the response order',
      );
    });

    test('a missing start falls back to inserted_at and interleaves', () {
      final DashboardIncidents sections = partitionIncidents(<Incident>[
        _incident(
          'started-20',
          'Started 20h',
          startedAt: at(20),
          insertedAt: at(20),
        ),
        _incident(
          'inserted-10',
          'Inserted 10h',
          startedAt: null,
          insertedAt: at(10),
        ),
        _incident(
          'started-5',
          'Started 5h',
          startedAt: at(5),
          insertedAt: at(5),
        ),
        // Same as missing: a start the client cannot parse must not be guessed
        // at, so the row competes on the insert time it does have.
        _incident(
          'garbage-start',
          'Garbage start',
          startedAt: 'not-a-date',
          insertedAt: at(15),
        ),
        // Wholly undated: no usable date at all, so there is nothing to
        // place it by and it goes last.
        _incident('undated', 'Undated', startedAt: null, insertedAt: ''),
      ]);

      expect(
        sections.needsAcknowledgement.map((Incident i) => i.id),
        <String>[
          'started-5',
          'inserted-10',
          'garbage-start',
          'started-20',
          'undated',
        ],
        reason:
            'a row with only an insert time is ordered by it, so an older insert '
            'is not buried below every valid start; the undated row is last',
      );
    });

    test('a wholly undated row is last in the queue and in the history', () {
      final List<Incident> undated = <Incident>[
        _outstanding('q-undated', 'Q undated'),
        _resolved('r-undated', 'R undated', hours: null),
      ];
      // Also empty strings, which parse to nothing rather than to a date.
      final List<Incident> blank = <Incident>[
        _incident('q-blank', 'Q blank', startedAt: '   ', insertedAt: ''),
        _incident(
          'r-blank',
          'R blank',
          startedAt: '',
          insertedAt: '   ',
          resolvedAt: at(3),
        ),
      ];

      final DashboardIncidents sections = partitionIncidents(<Incident>[
        ...undated,
        ...blank,
        _outstanding('q-dated', 'Q dated', hours: 1),
        _resolved('r-dated', 'R dated', hours: 2),
        _resolved('r-dated-newer', 'R newer', hours: 9),
      ]);

      expect(
        sections.needsAcknowledgement.map((Incident i) => i.id),
        <String>['q-dated', 'q-blank', 'q-undated'],
        reason:
            'ascending: an undated row is never presented as the oldest '
            'outstanding one',
      );
      expect(
        sections.recentResolved.map((Incident i) => i.id),
        <String>['r-dated-newer', 'r-dated', 'r-blank', 'r-undated'],
        reason:
            'descending, and still undated-last: negating the ascending order '
            'would otherwise put an undated row at the top as if it were the '
            'most recent',
      );
    });

    test('equivalent instants in different offsets tie by id', () {
      // The same instant written two ways. A start that is only *textually*
      // earlier must not win, and the tiebreak has to be stable.
      final DashboardIncidents sections = partitionIncidents(<Incident>[
        _incident(
          'b-offset',
          'B offset',
          startedAt: '2026-09-26T01:00:00+01:00',
          insertedAt: '2026-09-26T00:00:00Z',
        ),
        _incident(
          'a-zulu',
          'A zulu',
          startedAt: '2026-09-26T00:00:00Z',
          insertedAt: '2026-09-26T00:00:00Z',
        ),
        _incident(
          'd-offset',
          'D offset',
          startedAt: '2026-09-26T01:00:00+01:00',
          insertedAt: '2026-09-26T00:00:00Z',
          resolvedAt: '2026-09-26T01:00:00Z',
        ),
        _incident(
          'c-zulu',
          'C zulu',
          startedAt: '2026-09-26T00:00:00Z',
          insertedAt: '2026-09-26T00:00:00Z',
          resolvedAt: '2026-09-26T01:00:00Z',
        ),
      ]);

      expect(sections.needsAcknowledgement.map((Incident i) => i.id), <String>[
        'a-zulu',
        'b-offset',
      ], reason: 'equal instants, so the stable id decides in both directions');
      expect(sections.recentResolved.map((Incident i) => i.id), <String>[
        'c-zulu',
        'd-offset',
      ]);
    });

    test('shuffled input produces an identical order', () {
      final List<Incident> rows = <Incident>[
        _outstanding('q1', 'Q1', hours: 3),
        _outstanding('q2', 'Q2'),
        _outstanding('q3', 'Q3', hours: 1),
        _outstanding('q4', 'Q4'),
        _resolved('r1', 'R1', hours: 4),
        _resolved('r2', 'R2', hours: 2),
        _resolved('r3', 'R3', hours: null),
        _owned('a1', 'A1', hours: 5),
        _owned('a2', 'A2', hours: null),
      ];

      final List<List<String>> orders = <List<String>>[];
      for (final List<Incident> shuffled in <List<Incident>>[
        rows,
        rows.reversed.toList(),
        <Incident>[...rows.sublist(3), ...rows.sublist(0, 3).reversed],
      ]) {
        final DashboardIncidents sections = partitionIncidents(shuffled);
        orders.add(<String>[
          ...sections.needsAcknowledgement.map((Incident i) => i.id),
          ...sections.acknowledgedOngoing.map((Incident i) => i.id),
          ...sections.recentResolved.map((Incident i) => i.id),
        ]);
      }

      expect(orders[1], orders[0]);
      expect(orders[2], orders[0]);
      expect(
        orders.first,
        <String>['q3', 'q1', 'q2', 'q4', 'a1', 'a2', 'r1', 'r2', 'r3'],
        reason:
            'undated rows keep a stable position regardless of the order the '
            'API returned them in',
      );
    });

    test('resolution history is newest first and bounded', () {
      final DashboardIncidents sections = partitionIncidents(<Incident>[
        for (int i = 0; i < 8; i++) _resolved('r$i', 'R$i', hours: i),
      ]);

      expect(sections.recentResolved, hasLength(maxResolvedHistory));
      expect(sections.recentResolved.map((Incident i) => i.id), <String>[
        'r7',
        'r6',
        'r5',
        'r4',
        'r3',
      ], reason: 'history is truncated, never the queue');
    });

    test('the response queue is never truncated', () {
      final List<Incident> queue = <Incident>[
        for (int i = 0; i < 40; i++) _outstanding('q$i', 'Q$i', hours: i),
      ];
      expect(partitionIncidents(queue).needsAcknowledgement, hasLength(40));
    });
  });

  group('DashboardData.emptyCopy', () {
    test('a server-confirmed empty account gets the onboarding line', () {
      final DashboardEmptyCopy? copy = _data(
        counts: <String, int>{},
        total: 0,
        loaded: 0,
        uptime: null,
        incidents: const <Incident>[],
      ).emptyCopy;

      expect(copy, isNotNull);
      expect(copy!.headline, 'No monitors yet.');
      expect(copy.detail, contains('web dashboard'));
      expect(
        copy.showRefresh,
        isFalse,
        reason: 'retrying cannot create a monitor',
      );
    });

    test('no copy at all once there is content', () {
      expect(_data(incidents: <Incident>[]).emptyCopy, isNull);
      expect(
        _data(
          loaded: 0,
          incidents: <Incident>[_outstanding('q1', 'Outstanding', hours: 1)],
        ).emptyCopy,
        isNull,
        reason: 'an incident with nobody to answer it is content',
      );
      expect(
        _data(
          total: 137,
          loaded: 0,
          incidents: <Incident>[_owned('a1', 'Acknowledged', hours: 1)],
        ).emptyCopy,
        isNull,
        reason: 'an open incident is content even with no monitor rows',
      );
    });

    test('monitors in the account but none loaded reads as missing data', () {
      final DashboardEmptyCopy copy = _data(
        counts: <String, int>{},
        total: 137,
        loaded: 0,
        uptime: null,
        incidents: const <Incident>[],
      ).emptyCopy!;

      expect(copy.headline, 'Monitor data unavailable');
      expect(copy.detail, contains('137'));
      expect(copy.showRefresh, isTrue);
      expect(
        copy.detail,
        isNot(contains('No monitors')),
        reason: 'the account is known not to be empty',
      );
    });

    test('an empty offline cache says nothing about the account', () {
      final DashboardEmptyCopy copy = _data(
        counts: <String, int>{},
        total: 0,
        loaded: 0,
        totalKnown: false,
        uptime: null,
        offline: true,
        incidents: const <Incident>[],
      ).emptyCopy!;

      expect(copy.headline, 'No cached monitor data');
      expect(copy.showRefresh, isTrue);
      expect(copy.detail.toLowerCase(), contains('offline'));
      expect(
        copy.headline,
        isNot(contains('No monitors yet')),
        reason: 'an empty cache is not an empty account',
      );
    });

    test('an unknown total never becomes a whole-account claim', () {
      for (final bool offline in <bool>[false, true]) {
        final DashboardEmptyCopy copy = _data(
          counts: <String, int>{},
          total: 0,
          loaded: 0,
          totalKnown: false,
          uptime: null,
          offline: offline,
          incidents: const <Incident>[],
        ).emptyCopy!;

        expect(copy.headline, isNot('No monitors yet.'));
        expect(copy.detail, isNot(contains('web dashboard')));
        expect(copy.detail, contains('unknown'));
      }
    });
  });

  group('ApiDashboardRepository', () {
    late AppDatabase db;
    late CacheRepository cache;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      cache = CacheRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'an old unacknowledged incident outranks five newer resolutions',
      () async {
        final _Adapter adapter = _Adapter(<String, Object?>{
          kListMonitorsPath: monitorsBody(rows: 2, total: 2),
          kIncidentsPath: incidentsBody(<Map<String, Object?>>[
            for (int i = 0; i < 5; i++)
              incidentRow(
                'resolved-$i',
                monitorName: 'Resolved $i',
                startedAt: at(10 + i),
                resolvedAt: at(11 + i),
              ),
            incidentRow('old-open', monitorName: 'Old open', startedAt: at(1)),
          ]),
        });
        addTearDown(adapter.close);

        final DashboardData data = await ApiDashboardRepository(
          api: UptrackApi(dio: Dio()..httpClientAdapter = adapter),
          cache: cache,
        ).load();

        expect(
          data.incidents.recentResolved,
          hasLength(5),
          reason:
              'the five newest rows are the history a recency list would show',
        );
        expect(
          data.incidents.needsAcknowledgement.map(
            (Incident i) => i.displayName,
          ),
          <String>['Old open'],
          reason:
              'the newest five rows are all resolved, so truncating before '
              'partitioning would hide the only incident awaiting a response',
        );
        expect(
          adapter.requests.where((String r) => r.contains('incidents')).length,
          1,
          reason: 'one unfiltered list response is enough; no second fetch',
        );
      },
    );

    test('the response queue is ordered oldest outstanding first', () async {
      final _Adapter adapter = _Adapter(<String, Object?>{
        kListMonitorsPath: monitorsBody(rows: 1, total: 1),
        kIncidentsPath: incidentsBody(<Map<String, Object?>>[
          incidentRow('newest', monitorName: 'Newest', startedAt: at(9)),
          incidentRow('oldest', monitorName: 'Oldest', startedAt: at(1)),
          incidentRow('middle', monitorName: 'Middle', startedAt: at(5)),
        ]),
      });
      addTearDown(adapter.close);

      final DashboardData data = await ApiDashboardRepository(
        api: UptrackApi(dio: Dio()..httpClientAdapter = adapter),
        cache: cache,
      ).load();

      expect(
        data.incidents.needsAcknowledgement.map((Incident i) => i.id),
        <String>['oldest', 'middle', 'newest'],
      );
    });

    test('acknowledging moves an incident out of the queue', () async {
      final _Adapter adapter = _Adapter(<String, Object?>{
        kListMonitorsPath: monitorsBody(rows: 1, total: 1),
        kIncidentsPath: incidentsBody(<Map<String, Object?>>[
          incidentRow('i1', monitorName: 'Oldest', startedAt: at(1)),
          incidentRow('i2', monitorName: 'Newer', startedAt: at(5)),
        ]),
      });
      addTearDown(adapter.close);
      final ApiDashboardRepository repo = ApiDashboardRepository(
        api: UptrackApi(dio: Dio()..httpClientAdapter = adapter),
        cache: cache,
      );

      expect(
        (await repo.load()).incidents.needsAcknowledgement.map(
          (Incident i) => i.id,
        ),
        <String>['i1', 'i2'],
      );

      // The next response has the server's acknowledgement for i1.
      adapter.bodies[kIncidentsPath] = incidentsBody(<Map<String, Object?>>[
        incidentRow(
          'i1',
          monitorName: 'Oldest',
          startedAt: at(1),
          acknowledgedAt: at(2),
        ),
        incidentRow('i2', monitorName: 'Newer', startedAt: at(5)),
      ]);

      final DashboardData after = await repo.load();
      expect(
        after.incidents.needsAcknowledgement.map((Incident i) => i.id),
        <String>['i2'],
      );
      expect(
        after.incidents.acknowledgedOngoing.map((Incident i) => i.id),
        <String>['i1'],
      );
    });

    test('a bounded monitor page reports the real total', () async {
      final _Adapter adapter = _Adapter(<String, Object?>{
        kListMonitorsPath: monitorsBody(rows: 100, total: 137, status: 'down'),
        kIncidentsPath: incidentsBody(<Map<String, Object?>>[]),
      });
      addTearDown(adapter.close);

      final DashboardData data = await ApiDashboardRepository(
        api: UptrackApi(dio: Dio()..httpClientAdapter = adapter),
        cache: cache,
      ).load();

      expect(data.totalMonitors, 137);
      expect(data.loadedMonitors, 100);
      expect(data.totalMonitorsKnown, isTrue);
      expect(data.hasMoreMonitors, isTrue);
      expect(data.downCount, 100, reason: 'counts cover the loaded page');
      expect(data.otherCount, 0);
      expect(data.monitorScopeSummary, contains('Showing 100 of 137 monitors'));
    });

    test('a single full page reports no remainder', () async {
      final _Adapter adapter = _Adapter(<String, Object?>{
        kListMonitorsPath: monitorsBody(rows: 100, total: 100),
        kIncidentsPath: incidentsBody(<Map<String, Object?>>[]),
      });
      addTearDown(adapter.close);

      final DashboardData data = await ApiDashboardRepository(
        api: UptrackApi(dio: Dio()..httpClientAdapter = adapter),
        cache: cache,
      ).load();

      expect(data.hasMoreMonitors, isFalse);
      expect(data.monitorScopeSummary, 'Showing all 100 monitors.');
    });

    test('the offline cache never passes its row count off as a total', () async {
      final _Adapter adapter = _Adapter(<String, Object?>{
        kListMonitorsPath: monitorsBody(rows: 100, total: 137),
        kIncidentsPath: incidentsBody(<Map<String, Object?>>[
          incidentRow('old-open', monitorName: 'Old open', startedAt: at(1)),
          incidentRow('acked', monitorName: 'Owned', acknowledgedAt: at(2)),
          incidentRow('done', monitorName: 'Done', resolvedAt: at(5)),
        ]),
      });
      addTearDown(adapter.close);
      final UptrackApi api = UptrackApi(
        dio: Dio()..httpClientAdapter = adapter,
      );
      await ApiDashboardRepository(api: api, cache: cache).load();

      // Offline: the cached page is all that is left, and it carries no total.
      adapter.offline = true;
      final DashboardData offline = await ApiDashboardRepository(
        api: api,
        cache: cache,
      ).load();

      expect(offline.offline, isTrue);
      expect(offline.totalMonitorsKnown, isFalse);
      expect(offline.hasMoreMonitors, isFalse);
      expect(
        offline.totalMonitors,
        100,
        reason: 'only the cached rows are known, not the account total',
      );
      expect(offline.monitorScopeSummary, contains('total is unknown'));
      // The queue survives the offline path, so the response work stays visible.
      expect(
        offline.incidents.needsAcknowledgement.map((Incident i) => i.id),
        <String>['old-open'],
      );
      expect(
        offline.incidents.acknowledgedOngoing.map((Incident i) => i.id),
        <String>['acked'],
      );
      expect(offline.incidents.recentResolved, hasLength(1));
    });

    test(
      'the full response is cached, not just the dashboard sections',
      () async {
        final _Adapter adapter = _Adapter(<String, Object?>{
          kListMonitorsPath: monitorsBody(rows: 1, total: 1),
          kIncidentsPath: incidentsBody(<Map<String, Object?>>[
            for (int i = 0; i < 12; i++)
              incidentRow(
                'i$i',
                monitorName: 'M$i',
                startedAt: at(i),
                resolvedAt: at(i + 1),
              ),
          ]),
        });
        addTearDown(adapter.close);
        final ApiDashboardRepository repo = ApiDashboardRepository(
          api: UptrackApi(dio: Dio()..httpClientAdapter = adapter),
          cache: cache,
        );

        final DashboardData data = await repo.load();
        expect(data.incidents.recentResolved, hasLength(maxResolvedHistory));
        expect(
          (await cache.getIncidents()).data,
          hasLength(12),
          reason:
              'the cache is the offline history; storing only the visible '
              'sections would wipe the other rows from it',
        );
      },
    );

    test('a logout during the load still fences the response', () async {
      final _Adapter adapter = _Adapter(<String, Object?>{
        kListMonitorsPath: monitorsBody(rows: 1, total: 1),
        kIncidentsPath: incidentsBody(<Map<String, Object?>>[
          incidentRow('i1'),
        ]),
      });
      addTearDown(adapter.close);
      final ApiDashboardRepository repo = ApiDashboardRepository(
        api: UptrackApi(dio: Dio()..httpClientAdapter = adapter),
        cache: cache,
      );

      final Future<DashboardData> load = repo.load();
      await cache.clearAll();
      await expectLater(load, throwsA(isA<SessionEndedException>()));
      expect((await cache.getIncidents()).data, isEmpty);
    });

    test('an unknown half makes the page sync time unknown, not borrowed', () async {
      // A real repository, a real cache, a real fallback, and the state a real
      // device reaches: the monitor list synced, and the incident rows came from
      // a *detail* read, which writes summary rows without ever marking the
      // incident collection fresh. So the offline page is half-dated.
      //
      // It must then claim no time at all. The timestamp describes the page as a
      // whole, so borrowing the monitors' date would date incident rows whose
      // age nobody knows — and the screen already has honest copy for that.
      await cache.saveMonitors(<Monitor>[
        Monitor(
          id: 'm1',
          name: 'Monitor 1',
          url: 'https://m1.example.com',
          monitorType: 'http',
          status: 'up',
          interval: 60,
          timeout: 10,
          confirmationWindow: 'immediate',
          regionsRequired: 'any',
          createdAt: at(0),
          updatedAt: at(1),
          uptimePercentage: 99.9,
        ),
      ]);
      expect(
        await cache.saveIncidentDetail(
          const IncidentSnapshot(
            id: 'from-a-detail-read',
            monitorId: 'm1',
            monitorName: 'Homepage',
            status: 'ongoing',
            insertedAt: '2026-09-27T10:00:00Z',
          ),
          const <IncidentUpdate>[],
          session: cache.sessionEpoch,
          revision: cache.incidentRevision,
          syncedAt: DateTime.utc(2026, 9, 27, 10, 6),
        ),
        isTrue,
      );
      expect((await cache.getIncidents()).data, hasLength(1));
      expect(
        await cache.lastSynced(kIncidentsCacheKey),
        isNull,
        reason:
            'sanity: a detail read is not an incident list sync, so the '
            'collection genuinely has no sync time',
      );
      expect(await cache.lastSynced(kMonitorsCacheKey), isNotNull);

      final _Adapter adapter = _Adapter(<String, Object?>{});
      addTearDown(adapter.close);
      adapter.offline = true;

      final DashboardData offline = await ApiDashboardRepository(
        api: UptrackApi(dio: Dio()..httpClientAdapter = adapter),
        cache: cache,
      ).load();

      expect(offline.offline, isTrue);
      expect(
        offline.syncedAt,
        isNull,
        reason:
            'the incident half has no known age, so the page as a whole has no '
            'date: borrowing the monitors\' time would date data nobody dated',
      );
      // Both halves are still served — an unknown timestamp is not missing data.
      expect(
        offline.incidents.needsAcknowledgement.map((Incident i) => i.id),
        <String>['from-a-detail-read'],
      );
      expect(offline.loadedMonitors, 1);
      expect(offline.monitorScopeSummary, contains('total is unknown'));
    });

    test('a logout between the cached rows and the page metadata rejects', () async {
      // The window that had no check of its own: the rows were read and checked,
      // and the sync time was fetched by a *second* await with nothing verifying
      // the session afterwards. A logout landing between them could therefore
      // finish the load and hand the previous session's page to the screen.
      //
      // Reproduced by holding the metadata read open, logging out while it waits,
      // and requiring the load to reject rather than answer.
      final _Adapter adapter = _Adapter(<String, Object?>{
        kListMonitorsPath: monitorsBody(rows: 1, total: 1),
        kIncidentsPath: incidentsBody(<Map<String, Object?>>[
          incidentRow('i1', monitorName: 'Old open', startedAt: at(1)),
        ]),
      });
      addTearDown(adapter.close);
      final UptrackApi api = UptrackApi(
        dio: Dio()..httpClientAdapter = adapter,
      );
      // Seed the previous session's rows, so there is something a leak would
      // actually expose.
      await ApiDashboardRepository(api: api, cache: cache).load();
      expect((await cache.getIncidents()).data, hasLength(1));

      // This repository both holds the incident read open and holds the epoch the
      // logout advances, which is what makes the window reachable: the load reads
      // the rows through it, waits inside the read, and is released *after* the
      // epoch moved.
      final _MetadataHoldingCache holding = _MetadataHoldingCache(db);
      holding.held = Completer<void>();
      holding.release = Completer<void>();

      final Future<DashboardData> load = ApiDashboardRepository(
        api: api,
        cache: holding,
      ).load();
      // A newer write bumps the revision, so the load's own incident write is
      // fenced and it falls back to the cached rows — the branch under test.
      await holding.upsertIncident(
        const IncidentSnapshot(
          id: 'newer',
          monitorId: 'm1',
          status: 'ongoing',
          insertedAt: '2026-09-27T10:00:00Z',
        ),
        session: holding.sessionEpoch,
      );
      await holding.held!.future;

      await holding.clearAll();
      holding.release!.complete();

      await expectLater(
        load,
        throwsA(isA<SessionEndedException>()),
        reason:
            'the rows were checked, but the metadata read that followed had no '
            'check of its own; a logout in that window must not answer with the '
            'previous session\'s page',
      );
    });
  });

  group('DashboardScreen', () {
    testWidgets('orders the response queue first, then owned, then metrics', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDashboard(
        tester,
        FakeDashboardRepository(
          onLoad: () async => _data(
            incidents: <Incident>[
              _outstanding('newer', 'Needs attention newer', hours: 5),
              _resolved('done', 'Recently resolved', hours: 2),
              _outstanding('older', 'Needs attention older', hours: 1),
              _owned('owned', 'Acknowledged open', hours: 3),
            ],
          ),
        ),
      );

      // Section order, as the user reads it top to bottom.
      expect(find.text('Needs acknowledgement (2)'), findsOneWidget);
      expect(find.text('Acknowledged open incidents (1)'), findsOneWidget);
      expect(find.text('Recently resolved (1)'), findsOneWidget);
      expect(find.text('Monitor status'), findsOneWidget);
      double topOf(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(
        topOf('Needs acknowledgement (2)'),
        lessThan(topOf('Acknowledged open incidents (1)')),
      );
      expect(
        topOf('Acknowledged open incidents (1)'),
        lessThan(topOf('Monitor status')),
      );
      expect(topOf('Monitor status'), lessThan(topOf('Recently resolved (1)')));

      // Oldest outstanding first inside the queue.
      expect(
        topOf('Needs attention older'),
        lessThan(topOf('Needs attention newer')),
      );
      expect(find.text('Acknowledged open'), findsOneWidget);

      // Metrics and shortcuts are still there.
      expect(find.text('Average uptime'), findsOneWidget);
      expect(find.text('99.9%'), findsOneWidget);
      expect(find.text('View monitors'), findsOneWidget);
      expect(find.text('View incidents'), findsOneWidget);
    });

    testWidgets('counts and neutral copy when nothing needs a response', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(
        tester,
        FakeDashboardRepository(
          onLoad: () async => _data(
            incidents: <Incident>[
              _owned('owned', 'Acknowledged open'),
              _resolved('done', 'Recently resolved'),
            ],
          ),
        ),
      );

      expect(find.text('Needs acknowledgement (0)'), findsOneWidget);
      expect(find.text('No incidents need acknowledgement.'), findsOneWidget);
      expect(find.text('Acknowledged open incidents (1)'), findsOneWidget);
      // The queue is empty but an open incident exists: the empty copy must not
      // claim there are no open incidents.
      expect(find.text('No open incidents.'), findsNothing);
      expect(find.text('No incidents need acknowledgement.'), findsOneWidget);
    });

    testWidgets('the queue links through to the matching feed filter', (
      WidgetTester tester,
    ) async {
      // Through the real router, so the link, the query and the feed's own
      // filter handling are all exercised together: tapping a section link must
      // open the feed already filtered to that section, not on All.
      final GoRouter router = createRouter();
      addTearDown(router.dispose);
      // Enabled before the first frame, which is when the tree is annotated.
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            dashboardRepositoryProvider.overrideWithValue(
              FakeDashboardRepository(
                onLoad: () async => _data(
                  incidents: <Incident>[
                    _outstanding('q1', 'Needs attention', hours: 1),
                    _owned('owned', 'Acknowledged open', hours: 2),
                  ],
                ),
              ),
            ),
            incidentsRepositoryProvider.overrideWithValue(
              _FakeIncidentsRepository(<Incident>[
                _outstanding('q1', 'Needs attention', hours: 1),
                _owned('owned', 'Acknowledged open', hours: 2),
                _resolved('r1', 'Recently resolved', hours: 3),
              ]),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('View all needing acknowledgement'));
      await tester.tap(find.text('View all needing acknowledgement'));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/incidents');
      expect(
        router.routeInformationProvider.value.uri.queryParameters['filter'],
        'needs-acknowledgement',
      );
      // The feed opened on the queue, not on every row: the control for it
      // announces itself as selected, and the owned/resolved rows are gone.
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Needs acknowledgement'))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Acknowledged open'), findsNothing);
      expect(find.text('Recently resolved'), findsNothing);
      handle.dispose();
    });

    testWidgets('a bounded monitor page says which part is on screen', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(
        tester,
        FakeDashboardRepository(
          onLoad: () async => _data(
            counts: <String, int>{'down': 100},
            total: 137,
            loaded: 100,
            incidents: <Incident>[_outstanding('q1', 'Needs attention')],
          ),
        ),
      );

      await scrollTo(
        tester,
        find.textContaining('Showing 100 of 137 monitors'),
      );
      expect(
        find.textContaining('Showing 100 of 137 monitors.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Status counts and uptime cover the 100 shown.'),
        findsOneWidget,
      );
      expect(find.text('of 137 in account'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('137'), findsOneWidget, reason: 'the server total');
    });

    testWidgets('an offline page does not claim to be the whole account', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(
        tester,
        FakeDashboardRepository(
          onLoad: () async => _data(
            total: 100,
            loaded: 100,
            totalKnown: false,
            offline: true,
            incidents: <Incident>[_outstanding('q1', 'Needs attention')],
          ),
        ),
      );

      expect(find.text('Offline — showing cached data'), findsOneWidget);
      await scrollTo(
        tester,
        find.textContaining('Showing 100 cached monitors'),
      );
      expect(find.text('Cached'), findsOneWidget);
      // The tile is labelled as cached, never as an account total.
      final SemanticsHandle handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Cached monitors: 100'), findsOneWidget);
      handle.dispose();
      expect(
        find.textContaining(
          'Showing 100 cached monitors. The account total is unknown while '
          'offline.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Showing 100 of'), findsNothing);
    });

    testWidgets('empty state when no monitors and no incidents', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(
        tester,
        FakeDashboardRepository(
          onLoad: () async => _data(
            counts: <String, int>{},
            total: 0,
            loaded: 0,
            uptime: null,
            incidents: const <Incident>[],
          ),
        ),
      );

      expect(find.text('No monitors yet.'), findsOneWidget);
      expect(find.text('Needs acknowledgement'), findsNothing);
      expect(
        find.text('Monitor data unavailable'),
        findsNothing,
        reason: 'the server confirmed zero monitors, so onboarding is true',
      );
      expect(find.text('Refresh'), findsNothing);
    });

    testWidgets(
      'a known total with no loaded monitors is not an empty account',
      (WidgetTester tester) async {
        final FakeDashboardRepository repo = FakeDashboardRepository(
          onLoad: () async => _data(
            counts: <String, int>{},
            total: 137,
            loaded: 0,
            uptime: null,
            incidents: const <Incident>[],
          ),
        );
        await pumpDashboard(tester, repo);

        // The account has 137 monitors, so a blank page is missing data — not a
        // zero that was never reported.
        expect(find.text('Monitor data unavailable'), findsOneWidget);
        expect(find.text('No monitors yet.'), findsNothing);
        expect(
          find.text(
            'This account has 137 monitors, but this response carried none. '
            'Refresh to try again.',
          ),
          findsOneWidget,
        );
        expect(find.text('Needs acknowledgement (0)'), findsNothing);

        // A refresh is offered, and it actually reloads.
        repo.onLoad = () async =>
            _data(incidents: <Incident>[_outstanding('q1', 'Needs attention')]);
        await tester.tap(find.text('Refresh'));
        await tester.pumpAndSettle();

        expect(find.text('Needs attention'), findsOneWidget);
        expect(repo.loads, 2);
      },
    );

    testWidgets('an empty offline cache keeps the offline indicator', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(
        tester,
        FakeDashboardRepository(
          onLoad: () async => _data(
            counts: <String, int>{},
            total: 0,
            loaded: 0,
            totalKnown: false,
            uptime: null,
            offline: true,
            incidents: const <Incident>[],
          ),
        ),
      );

      expect(find.text('No cached monitor data'), findsOneWidget);
      expect(
        find.text('Offline — showing cached data'),
        findsOneWidget,
        reason: 'the empty state must not drop the offline banner',
      );
      expect(find.text('No monitors yet.'), findsNothing);
      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('every empty state survives 200% text', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final List<(String, DashboardData)> states = <(String, DashboardData)>[
        (
          'No monitors yet.',
          _data(
            counts: <String, int>{},
            total: 0,
            loaded: 0,
            uptime: null,
            incidents: const <Incident>[],
          ),
        ),
        (
          'Monitor data unavailable',
          _data(
            counts: <String, int>{},
            total: 137,
            loaded: 0,
            uptime: null,
            incidents: const <Incident>[],
          ),
        ),
        (
          'No cached monitor data',
          _data(
            counts: <String, int>{},
            total: 0,
            loaded: 0,
            totalKnown: false,
            uptime: null,
            offline: true,
            incidents: const <Incident>[],
          ),
        ),
      ];

      for (final (String headline, DashboardData data) in states) {
        await pumpDashboard(
          tester,
          FakeDashboardRepository(onLoad: () async => data),
          textScaler: const TextScaler.linear(2),
        );
        expect(find.text(headline), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: '"$headline" must not overflow at 200% text',
        );
      }
    });

    testWidgets('the acknowledged hint claims no ownership or assignment', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDashboard(
        tester,
        FakeDashboardRepository(
          onLoad: () async => _data(
            incidents: <Incident>[
              _owned('owned', 'Acknowledged open', hours: 2),
            ],
          ),
        ),
      );

      final Finder hint = find.textContaining('Still open.');
      expect(hint, findsOneWidget);
      expect(find.textContaining('assign'), findsOneWidget);
      expect(find.textContaining('owns'), findsNothing);
      expect(find.textContaining('owner'), findsNothing);
      expect(find.textContaining('assigned'), findsNothing);
      expect(find.textContaining('on call'), findsNothing);
    });

    testWidgets('shows an offline banner for cached data', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(
        tester,
        FakeDashboardRepository(
          onLoad: () async => _data(
            offline: true,
            incidents: <Incident>[_outstanding('q1', 'Needs attention')],
          ),
        ),
      );

      expect(find.text('Offline — showing cached data'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
    });

    testWidgets('error state with retry that recovers', (
      WidgetTester tester,
    ) async {
      final FakeDashboardRepository repo = FakeDashboardRepository(
        onLoad: () async => throw _boom(),
      );
      await pumpDashboard(tester, repo);

      expect(
        find.text(
          'Could not load the dashboard. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      repo.onLoad = () async =>
          _data(incidents: <Incident>[_outstanding('q1', 'Needs attention')]);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Needs attention'), findsOneWidget);
      expect(repo.loads, 2);
    });

    testWidgets('loading spinner while the repository is pending', (
      WidgetTester tester,
    ) async {
      final Completer<DashboardData> gate = Completer<DashboardData>();
      final FakeDashboardRepository repo = FakeDashboardRepository(
        onLoad: () => gate.future,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dashboardRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: DashboardScreen()),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete(
        _data(incidents: <Incident>[_outstanding('q1', 'Needs attention')]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Needs attention'), findsOneWidget);
    });
  });
}
