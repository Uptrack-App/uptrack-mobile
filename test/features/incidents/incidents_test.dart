import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/features/incidents/incident_detail_screen.dart';
import 'package:uptrack_mobile/features/incidents/incidents_controller.dart';
import 'package:uptrack_mobile/features/incidents/incidents_screen.dart';

Incident _incident(
  String id,
  String monitorName, {
  String status = 'open',
  String? resolvedAt,
  String? acknowledgedAt,
}) => Incident(
  id: id,
  monitorId: 'monitor-$id',
  status: status,
  insertedAt: '2026-09-26T00:00:00Z',
  monitorName: monitorName,
  startedAt: '2026-09-26T00:00:00Z',
  resolvedAt: resolvedAt,
  acknowledgedAt: acknowledgedAt,
);

IncidentUpdate _update(int id, String title) => IncidentUpdate(
  id: id,
  status: 'investigating',
  title: title,
  postedAt: '2026-09-26T00:05:00Z',
);

IncidentDetailData _detail({
  Incident? incident,
  List<IncidentUpdate>? updates,
  bool offline = false,
}) => IncidentDetailData(
  incident: incident ?? _incident('i1', 'Homepage'),
  updates: updates ?? <IncidentUpdate>[_update(7, 'Looking into it')],
  offline: offline,
);

class FakeIncidentsRepository implements IncidentsRepository {
  FakeIncidentsRepository({required this.onLoad});

  Future<IncidentsData> Function() onLoad;

  @override
  Future<IncidentsData> load() => onLoad();
}

class FakeIncidentDetailRepository implements IncidentDetailRepository {
  FakeIncidentDetailRepository({required this.onLoad, required this.onAck});

  Future<IncidentDetailData> Function(String id) onLoad;
  Future<IncidentDetailData> Function(String id) onAck;
  int acknowledges = 0;

  @override
  Future<IncidentDetailData> load(String id) => onLoad(id);

  @override
  Future<IncidentDetailData> acknowledge(String id) {
    acknowledges++;
    return onAck(id);
  }
}

DioException _boom() => DioException(
  requestOptions: RequestOptions(path: '/api/incidents'),
  message: 'Connection refused',
);

Future<void> pumpFeed(WidgetTester tester, FakeIncidentsRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [incidentsRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: IncidentsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpDetail(
  WidgetTester tester,
  FakeIncidentDetailRepository repo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [incidentDetailRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: IncidentDetailScreen(incidentId: 'i1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('filterIncidents', () {
    final List<Incident> rows = <Incident>[
      _incident('a', 'Homepage'),
      _incident('b', 'API', resolvedAt: '2026-09-26T01:00:00Z'),
    ];

    test('all returns everything, open only ongoing', () {
      expect(filterIncidents(rows), hasLength(2));
      expect(
        filterIncidents(
          rows,
          status: IncidentStatusFilter.open,
        ).map((Incident i) => i.id),
        <String>['a'],
      );
    });
  });

  group('optimisticAcknowledge', () {
    test('marks the incident acknowledged, keeps other fields', () {
      final IncidentDetailData before = _detail();
      final IncidentDetailData after = optimisticAcknowledge(
        before,
        now: DateTime.utc(2026, 9, 26, 0, 10),
      );

      expect(before.incident.isAcknowledged, isFalse);
      expect(after.incident.isAcknowledged, isTrue);
      expect(after.incident.acknowledgedAt, '2026-09-26T00:10:00.000Z');
      expect(after.incident.id, before.incident.id);
      expect(after.updates, same(before.updates));
    });

    test('leaves already-acknowledged incidents untouched', () {
      final IncidentDetailData before = _detail(
        incident: _incident('i1', 'Homepage', acknowledgedAt: 'old'),
      );
      expect(identical(optimisticAcknowledge(before), before), isTrue);
    });
  });

  group('IncidentsScreen', () {
    testWidgets('shows rows with open/resolved states', (
      WidgetTester tester,
    ) async {
      await pumpFeed(
        tester,
        FakeIncidentsRepository(
          onLoad: () async => IncidentsData(
            incidents: <Incident>[
              _incident('a', 'Homepage'),
              _incident(
                'b',
                'API',
                status: 'resolved',
                resolvedAt: '2026-09-26T01:00:00Z',
              ),
            ],
            offline: false,
          ),
        ),
      );

      expect(find.text('Incidents'), findsOneWidget);
      expect(find.text('Homepage'), findsOneWidget);
      expect(find.text('API'), findsOneWidget);
      expect(find.text('Open'), findsNWidgets(2));
      expect(find.text('Resolved'), findsOneWidget);
    });

    testWidgets('open filter hides resolved incidents', (
      WidgetTester tester,
    ) async {
      await pumpFeed(
        tester,
        FakeIncidentsRepository(
          onLoad: () async => IncidentsData(
            incidents: <Incident>[
              _incident('a', 'Homepage'),
              _incident(
                'b',
                'API',
                status: 'resolved',
                resolvedAt: '2026-09-26T01:00:00Z',
              ),
            ],
            offline: false,
          ),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<IncidentStatusFilter>),
          matching: find.text('Open'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Homepage'), findsOneWidget);
      expect(find.text('API'), findsNothing);
    });

    testWidgets('empty, offline, and error states', (
      WidgetTester tester,
    ) async {
      await pumpFeed(
        tester,
        FakeIncidentsRepository(
          onLoad: () async =>
              const IncidentsData(incidents: <Incident>[], offline: false),
        ),
      );
      expect(
        find.text('No incidents. Your monitors are quiet.'),
        findsOneWidget,
      );
    });

    testWidgets('offline banner for cached data', (WidgetTester tester) async {
      await pumpFeed(
        tester,
        FakeIncidentsRepository(
          onLoad: () async => IncidentsData(
            incidents: <Incident>[_incident('a', 'Homepage')],
            offline: true,
          ),
        ),
      );

      expect(find.text('Offline — showing cached data'), findsOneWidget);
    });

    testWidgets('error state with retry that recovers', (
      WidgetTester tester,
    ) async {
      final FakeIncidentsRepository repo = FakeIncidentsRepository(
        onLoad: () async => throw _boom(),
      );
      await pumpFeed(tester, repo);

      expect(
        find.text(
          'Could not load incidents. Check your connection and try again.',
        ),
        findsOneWidget,
      );

      repo.onLoad = () async => IncidentsData(
        incidents: <Incident>[_incident('a', 'Homepage')],
        offline: false,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Homepage'), findsOneWidget);
    });

    testWidgets('loading spinner while the repository is pending', (
      WidgetTester tester,
    ) async {
      final Completer<IncidentsData> gate = Completer<IncidentsData>();
      final FakeIncidentsRepository repo = FakeIncidentsRepository(
        onLoad: () => gate.future,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [incidentsRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: IncidentsScreen()),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete(
        IncidentsData(
          incidents: <Incident>[_incident('a', 'Homepage')],
          offline: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Homepage'), findsOneWidget);
    });
  });

  group('IncidentDetailScreen', () {
    testWidgets('shows header, acknowledge action, and updates', (
      WidgetTester tester,
    ) async {
      final FakeIncidentDetailRepository repo = FakeIncidentDetailRepository(
        onLoad: (String id) async => _detail(),
        onAck: (String id) async => _detail(
          incident: _incident(
            'i1',
            'Homepage',
            acknowledgedAt: '2026-09-26T00:10:00Z',
          ),
        ),
      );
      await pumpDetail(tester, repo);

      expect(find.text('Homepage'), findsOneWidget);
      expect(find.text('Acknowledge'), findsOneWidget);
      expect(find.text('Updates'), findsOneWidget);
      expect(find.text('Looking into it'), findsOneWidget);
    });

    testWidgets('acknowledge applies the optimistic update', (
      WidgetTester tester,
    ) async {
      final Completer<IncidentDetailData> gate =
          Completer<IncidentDetailData>();
      final FakeIncidentDetailRepository repo = FakeIncidentDetailRepository(
        onLoad: (String id) async => _detail(),
        onAck: (String id) => gate.future,
      );
      await pumpDetail(tester, repo);

      await tester.tap(find.text('Acknowledge'));
      await tester.pump();

      // The request is in flight and the optimistic state is visible.
      expect(repo.acknowledges, 1);
      expect(find.text('Acknowledge'), findsNothing);
      expect(find.textContaining('Acknowledged'), findsWidgets);

      gate.complete(
        _detail(
          incident: _incident(
            'i1',
            'Homepage',
            acknowledgedAt: '2026-09-26T00:10:00Z',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Acknowledge'), findsNothing);
      expect(find.textContaining('Acknowledged'), findsWidgets);
    });

    testWidgets('acknowledge failure rolls back and shows a SnackBar', (
      WidgetTester tester,
    ) async {
      final FakeIncidentDetailRepository repo = FakeIncidentDetailRepository(
        onLoad: (String id) async => _detail(),
        onAck: (String id) async => throw _boom(),
      );
      await pumpDetail(tester, repo);

      await tester.tap(find.text('Acknowledge'));
      await tester.pumpAndSettle();

      // Rolled back: the action is available again and the error surfaces.
      expect(find.text('Acknowledge'), findsOneWidget);
      expect(find.textContaining('Acknowledged'), findsNothing);
      expect(
        find.text('Could not acknowledge this incident. Try again.'),
        findsOneWidget,
      );
    });

    testWidgets('no acknowledge action when already acknowledged', (
      WidgetTester tester,
    ) async {
      await pumpDetail(
        tester,
        FakeIncidentDetailRepository(
          onLoad: (String id) async => _detail(
            incident: _incident(
              'i1',
              'Homepage',
              acknowledgedAt: '2026-09-26T00:10:00Z',
            ),
          ),
          onAck: (String id) async => _detail(),
        ),
      );

      expect(find.text('Acknowledge'), findsNothing);
      expect(find.textContaining('Acknowledged'), findsWidgets);
    });

    testWidgets('offline detail hides the action and notes updates', (
      WidgetTester tester,
    ) async {
      await pumpDetail(
        tester,
        FakeIncidentDetailRepository(
          onLoad: (String id) async =>
              _detail(offline: true, updates: const <IncidentUpdate>[]),
          onAck: (String id) async => _detail(),
        ),
      );

      expect(find.text('Offline — showing cached data'), findsOneWidget);
      expect(find.text('Acknowledge'), findsNothing);
      expect(find.text('Updates unavailable offline.'), findsOneWidget);
    });

    testWidgets('error state with retry that recovers', (
      WidgetTester tester,
    ) async {
      final FakeIncidentDetailRepository repo = FakeIncidentDetailRepository(
        onLoad: (String id) async => throw _boom(),
        onAck: (String id) async => _detail(),
      );
      await pumpDetail(tester, repo);

      expect(
        find.text(
          'Could not load incidents. Check your connection and try again.',
        ),
        findsOneWidget,
      );

      repo.onLoad = (String id) async => _detail();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Homepage'), findsOneWidget);
    });
  });
}
