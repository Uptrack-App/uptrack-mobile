import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/check.dart';
import 'package:uptrack_mobile/api/models/monitor.dart';
import 'package:uptrack_mobile/api/models/monitor_analytics.dart';
import 'package:uptrack_mobile/features/monitors/monitor_detail_controller.dart';
import 'package:uptrack_mobile/features/monitors/monitor_detail_screen.dart';
import 'package:uptrack_mobile/features/monitors/monitors_controller.dart';
import 'package:uptrack_mobile/features/monitors/monitors_screen.dart';
import 'package:uptrack_mobile/features/monitors/monitor_widgets.dart';

Monitor _monitor(
  String id,
  String name, {
  String status = 'up',
  double? uptime = 99.9,
  String regions = 'any',
}) => Monitor(
  id: id,
  name: name,
  url: 'https://$id.example.com',
  monitorType: 'http',
  status: status,
  interval: 60,
  timeout: 10,
  confirmationWindow: '1m',
  regionsRequired: regions,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-02T00:00:00Z',
  uptimePercentage: uptime,
);

MonitorAnalytics _analytics() => const MonitorAnalytics(
  monitorId: 'm1',
  periodDays: 7,
  responseTimes: <ResponseTimePoint>[
    ResponseTimePoint(timestamp: 1729900000, responseTime: 123.5),
    ResponseTimePoint(timestamp: 1729903600, responseTime: 140.0),
  ],
  percentiles: ResponsePercentiles(p50: 120, p95: 300, p99: 500),
);

MonitorDetailData _detail({bool noAnalytics = false, bool offline = false}) =>
    MonitorDetailData(
      monitor: _monitor('m1', 'Homepage'),
      checks: const <MonitorCheck>[
        MonitorCheck(
          status: 'up',
          responseTime: 120,
          statusCode: 200,
          checkedAt: '2026-09-26T00:00:00Z',
        ),
        MonitorCheck(
          status: 'down',
          responseTime: 5000,
          statusCode: 503,
          checkedAt: '2026-09-25T23:55:00Z',
          errorMessage: 'connection refused',
        ),
      ],
      analytics: noAnalytics ? null : _analytics(),
      offline: offline,
    );

class FakeMonitorsRepository implements MonitorsRepository {
  FakeMonitorsRepository({required this.onLoad});

  Future<MonitorsData> Function() onLoad;

  @override
  Future<MonitorsData> load() => onLoad();
}

class FakeMonitorDetailRepository implements MonitorDetailRepository {
  FakeMonitorDetailRepository({required this.onLoad});

  Future<MonitorDetailData> Function(String id, int days) onLoad;
  final List<int> daysRequested = <int>[];

  @override
  Future<MonitorDetailData> load(String id, {required int days}) {
    daysRequested.add(days);
    return onLoad(id, days);
  }
}

DioException _boom() => DioException(
  requestOptions: RequestOptions(path: '/api/monitors'),
  message: 'Connection refused',
);

Future<void> pumpMonitors(
  WidgetTester tester,
  FakeMonitorsRepository repo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [monitorsRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: MonitorsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpDetail(
  WidgetTester tester,
  FakeMonitorDetailRepository repo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [monitorDetailRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: MonitorDetailScreen(monitorId: 'm1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('filterMonitors', () {
    final List<Monitor> rows = <Monitor>[
      _monitor('a', 'Homepage', status: 'up'),
      _monitor('b', 'API', status: 'down'),
      _monitor('c', 'Blog', status: 'paused', uptime: null),
    ];

    test('matches name or url case-insensitively', () {
      expect(
        filterMonitors(rows, query: 'API').map((Monitor m) => m.id),
        <String>['b'],
      );
      expect(
        filterMonitors(rows, query: 'B.EXAMPLE').map((Monitor m) => m.id),
        <String>['b'],
      );
      expect(
        filterMonitors(rows, query: '  ').map((Monitor m) => m.id),
        <String>['a', 'b', 'c'],
      );
    });

    test('status filter matches exact status strings', () {
      expect(
        filterMonitors(
          rows,
          status: MonitorStatusFilter.up,
        ).map((Monitor m) => m.id),
        <String>['a'],
      );
      expect(
        filterMonitors(
          rows,
          status: MonitorStatusFilter.down,
        ).map((Monitor m) => m.id),
        <String>['b'],
      );
      expect(filterMonitors(rows), hasLength(3));
    });

    test('query and status combine', () {
      expect(
        filterMonitors(
          rows,
          query: 'example',
          status: MonitorStatusFilter.down,
        ).map((Monitor m) => m.id),
        <String>['b'],
      );
      expect(
        filterMonitors(
          rows,
          query: 'Homepage',
          status: MonitorStatusFilter.down,
        ),
        isEmpty,
      );
    });
  });

  group('MonitorsScreen', () {
    testWidgets('shows rows with status, uptime, and regions', (
      WidgetTester tester,
    ) async {
      await pumpMonitors(
        tester,
        FakeMonitorsRepository(
          onLoad: () async => MonitorsData(
            monitors: <Monitor>[
              _monitor('a', 'Homepage'),
              _monitor('b', 'API', status: 'down', uptime: 42.5),
            ],
            offline: false,
          ),
        ),
      );

      expect(find.text('Monitors'), findsOneWidget);
      expect(find.text('Homepage'), findsOneWidget);
      expect(find.text('API'), findsOneWidget);
      // Chip labels are capitalized like the web ("Up", not "up").
      expect(
        find.descendant(
          of: find.byType(MonitorStatusChip),
          matching: find.text('Up'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(MonitorStatusChip),
          matching: find.text('Down'),
        ),
        findsOneWidget,
      );
      expect(find.text('up'), findsNothing);
      expect(find.text('99.9% uptime'), findsOneWidget);
      expect(find.text('42.5% uptime'), findsOneWidget);
      expect(find.text('Regions: any'), findsNWidgets(2));
    });

    testWidgets('search narrows the list', (WidgetTester tester) async {
      await pumpMonitors(
        tester,
        FakeMonitorsRepository(
          onLoad: () async => MonitorsData(
            monitors: <Monitor>[
              _monitor('a', 'Homepage'),
              _monitor('b', 'API'),
            ],
            offline: false,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'api');
      await tester.pumpAndSettle();

      expect(find.text('API'), findsOneWidget);
      expect(find.text('Homepage'), findsNothing);
    });

    testWidgets('status filter narrows the list', (WidgetTester tester) async {
      await pumpMonitors(
        tester,
        FakeMonitorsRepository(
          onLoad: () async => MonitorsData(
            monitors: <Monitor>[
              _monitor('a', 'Homepage'),
              _monitor('b', 'API', status: 'down'),
            ],
            offline: false,
          ),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<MonitorStatusFilter>),
          matching: find.text('Down'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('API'), findsOneWidget);
      expect(find.text('Homepage'), findsNothing);
    });

    testWidgets('empty and no-match states', (WidgetTester tester) async {
      await pumpMonitors(
        tester,
        FakeMonitorsRepository(
          onLoad: () async =>
              const MonitorsData(monitors: <Monitor>[], offline: false),
        ),
      );
      expect(find.textContaining('No monitors yet.'), findsOneWidget);
    });

    testWidgets('offline banner for cached data', (WidgetTester tester) async {
      await pumpMonitors(
        tester,
        FakeMonitorsRepository(
          onLoad: () async => MonitorsData(
            monitors: <Monitor>[_monitor('a', 'Homepage')],
            offline: true,
          ),
        ),
      );

      expect(find.text('Offline — showing cached data'), findsOneWidget);
    });

    testWidgets('error state with retry that recovers', (
      WidgetTester tester,
    ) async {
      final FakeMonitorsRepository repo = FakeMonitorsRepository(
        onLoad: () async => throw _boom(),
      );
      await pumpMonitors(tester, repo);

      expect(
        find.text(
          'Could not load monitors. Check your connection and try again.',
        ),
        findsOneWidget,
      );

      repo.onLoad = () async => MonitorsData(
        monitors: <Monitor>[_monitor('a', 'Homepage')],
        offline: false,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Homepage'), findsOneWidget);
    });

    testWidgets('loading spinner while the repository is pending', (
      WidgetTester tester,
    ) async {
      final Completer<MonitorsData> gate = Completer<MonitorsData>();
      final FakeMonitorsRepository repo = FakeMonitorsRepository(
        onLoad: () => gate.future,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [monitorsRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: MonitorsScreen()),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete(
        MonitorsData(
          monitors: <Monitor>[_monitor('a', 'Homepage')],
          offline: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Homepage'), findsOneWidget);
    });
  });

  group('MonitorDetailScreen', () {
    testWidgets('shows header, chart, percentiles, and check history', (
      WidgetTester tester,
    ) async {
      await pumpDetail(
        tester,
        FakeMonitorDetailRepository(
          onLoad: (String id, int days) async => _detail(),
        ),
      );

      expect(find.text('Homepage'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MonitorStatusChip),
          matching: find.text('Up'),
        ),
        findsOneWidget,
      );
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.textContaining('p50 120 ms'), findsOneWidget);
      expect(find.textContaining('Last 7 days'), findsOneWidget);
      expect(find.textContaining('clamped'), findsOneWidget);
      // Check history is below the fold (ListView lazily builds it).
      await tester.scrollUntilVisible(find.textContaining('HTTP 503'), 200);
      expect(find.textContaining('HTTP 200'), findsOneWidget);
      expect(find.textContaining('HTTP 503'), findsOneWidget);
      expect(find.text('connection refused'), findsOneWidget);
    });

    testWidgets('range switch refetches with the selected window', (
      WidgetTester tester,
    ) async {
      final FakeMonitorDetailRepository repo = FakeMonitorDetailRepository(
        onLoad: (String id, int days) async => _detail(),
      );
      await pumpDetail(tester, repo);
      expect(repo.daysRequested, <int>[7]);

      await tester.tap(find.text('24H'));
      await tester.pumpAndSettle();

      expect(repo.daysRequested, <int>[7, 1]);
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('unavailable chart state when analytics is null', (
      WidgetTester tester,
    ) async {
      await pumpDetail(
        tester,
        FakeMonitorDetailRepository(
          onLoad: (String id, int days) async =>
              _detail(noAnalytics: true, offline: true),
        ),
      );

      expect(find.text('Offline — showing cached data'), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
      expect(find.textContaining('chart unavailable'), findsOneWidget);
      // Checks still render from the cache (below the fold).
      await tester.scrollUntilVisible(find.textContaining('HTTP 200'), 200);
      expect(find.textContaining('HTTP 200'), findsOneWidget);
    });

    testWidgets('error state with retry that recovers', (
      WidgetTester tester,
    ) async {
      final FakeMonitorDetailRepository repo = FakeMonitorDetailRepository(
        onLoad: (String id, int days) async => throw _boom(),
      );
      await pumpDetail(tester, repo);

      expect(
        find.text(
          'Could not load this monitor. Check your connection and try again.',
        ),
        findsOneWidget,
      );

      repo.onLoad = (String id, int days) async => _detail();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Homepage'), findsOneWidget);
    });
  });
}
