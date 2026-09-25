import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_controller.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_screen.dart';

Incident _incident(String id, String monitorName, {String status = 'open'}) =>
    Incident(
      id: id,
      monitorId: 'monitor-$id',
      status: status,
      insertedAt: '2026-09-26T00:00:00Z',
      monitorName: monitorName,
    );

DashboardData _data({
  Map<String, int>? counts,
  int total = 3,
  double? uptime = 99.9,
  List<Incident>? incidents,
  bool offline = false,
}) => DashboardData(
  totalMonitors: total,
  countsByStatus: counts ?? <String, int>{'up': 2, 'down': 1},
  averageUptime: uptime,
  recentIncidents:
      incidents ??
      <Incident>[_incident('i1', 'Homepage'), _incident('i2', 'API')],
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

Future<void> pumpDashboard(
  WidgetTester tester,
  FakeDashboardRepository repo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dashboardRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: DashboardScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

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

  group('DashboardScreen', () {
    testWidgets('shows counts, uptime summary, and recent incidents', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(
        tester,
        FakeDashboardRepository(onLoad: () async => _data()),
      );

      expect(find.text('Dashboard'), findsOneWidget);
      // Status counts.
      expect(find.text('Up'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Down'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // Uptime summary.
      expect(find.text('Average uptime'), findsOneWidget);
      expect(find.text('99.9%'), findsOneWidget);
      // Recent incidents.
      expect(find.text('Recent incidents'), findsOneWidget);
      expect(find.text('Homepage'), findsOneWidget);
      expect(find.text('API'), findsOneWidget);
      // Navigation shortcuts.
      expect(find.text('View monitors'), findsOneWidget);
      expect(find.text('View incidents'), findsOneWidget);
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
            uptime: null,
            incidents: <Incident>[],
          ),
        ),
      );

      expect(find.text('No monitors yet.'), findsOneWidget);
      expect(find.text('Recent incidents'), findsNothing);
    });

    testWidgets('shows an offline banner for cached data', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(
        tester,
        FakeDashboardRepository(onLoad: () async => _data(offline: true)),
      );

      expect(find.text('Offline — showing cached data'), findsOneWidget);
      expect(find.text('Homepage'), findsOneWidget);
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

      repo.onLoad = () async => _data();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Homepage'), findsOneWidget);
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

      gate.complete(_data());
      await tester.pumpAndSettle();
      expect(find.text('Homepage'), findsOneWidget);
    });
  });
}
