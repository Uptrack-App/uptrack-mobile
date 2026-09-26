import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/check.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/api/models/monitor.dart';
import 'package:uptrack_mobile/api/models/monitor_analytics.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_controller.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_screen.dart';
import 'package:uptrack_mobile/features/incidents/incident_detail_screen.dart';
import 'package:uptrack_mobile/features/incidents/incidents_controller.dart';
import 'package:uptrack_mobile/features/incidents/incidents_screen.dart';
import 'package:uptrack_mobile/features/monitors/monitor_detail_controller.dart';
import 'package:uptrack_mobile/features/monitors/monitor_detail_screen.dart';
import 'package:uptrack_mobile/features/monitors/monitors_controller.dart';
import 'package:uptrack_mobile/features/monitors/monitors_screen.dart';

Monitor _monitor(String id, String name, {String status = 'up'}) => Monitor(
  id: id,
  name: name,
  url: 'https://$id.example.com',
  monitorType: 'http',
  status: status,
  interval: 60,
  timeout: 10,
  confirmationWindow: '1m',
  regionsRequired: 'any',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-02T00:00:00Z',
  uptimePercentage: 99.9,
);

Incident _incident(String id, String monitorName, {String status = 'open'}) =>
    Incident(
      id: id,
      monitorId: 'monitor-$id',
      status: status,
      insertedAt: '2026-09-26T00:00:00Z',
      monitorName: monitorName,
      startedAt: '2026-09-26T00:00:00Z',
    );

class _DashboardRepo implements DashboardRepository {
  @override
  Future<DashboardData> load() async => DashboardData(
    totalMonitors: 3,
    countsByStatus: const <String, int>{'up': 2, 'down': 1},
    averageUptime: 99.9,
    recentIncidents: <Incident>[
      _incident('i1', 'Homepage'),
      _incident('i2', 'API'),
    ],
    offline: false,
  );
}

class _MonitorsRepo implements MonitorsRepository {
  @override
  Future<MonitorsData> load() async => MonitorsData(
    monitors: <Monitor>[
      _monitor('m1', 'Homepage'),
      _monitor('m2', 'API', status: 'down'),
    ],
    offline: false,
  );
}

class _MonitorDetailRepo implements MonitorDetailRepository {
  @override
  Future<MonitorDetailData> load(String id, {required int days}) async =>
      MonitorDetailData(
        monitor: _monitor('m1', 'Homepage'),
        checks: const <MonitorCheck>[
          MonitorCheck(
            status: 'up',
            responseTime: 120,
            statusCode: 200,
            checkedAt: '2026-09-26T00:00:00Z',
          ),
        ],
        analytics: const MonitorAnalytics(
          monitorId: 'm1',
          periodDays: 7,
          responseTimes: <ResponseTimePoint>[
            ResponseTimePoint(timestamp: 1729900000, responseTime: 123.5),
            ResponseTimePoint(timestamp: 1729903600, responseTime: 140.0),
          ],
          percentiles: ResponsePercentiles(p50: 120, p95: 300, p99: 500),
        ),
        offline: false,
      );
}

class _IncidentsRepo implements IncidentsRepository {
  @override
  Future<IncidentsData> load() async => IncidentsData(
    incidents: <Incident>[
      _incident('i1', 'Homepage'),
      _incident('i2', 'API', status: 'resolved'),
    ],
    offline: false,
  );
}

class _IncidentDetailRepo implements IncidentDetailRepository {
  @override
  Future<IncidentDetailData> load(String id) async => IncidentDetailData(
    incident: _incident('i1', 'Homepage'),
    updates: <IncidentUpdate>[
      IncidentUpdate(
        id: 7,
        status: 'investigating',
        title: 'Looking into it',
        postedAt: '2026-09-26T00:05:00Z',
      ),
    ],
    offline: false,
  );

  @override
  Future<IncidentDetailData> acknowledge(String id) => load(id);
}

Future<void> _pumpGolden(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dashboardRepositoryProvider.overrideWithValue(_DashboardRepo()),
        monitorsRepositoryProvider.overrideWithValue(_MonitorsRepo()),
        monitorDetailRepositoryProvider.overrideWithValue(_MonitorDetailRepo()),
        incidentsRepositoryProvider.overrideWithValue(_IncidentsRepo()),
        incidentDetailRepositoryProvider.overrideWithValue(
          _IncidentDetailRepo(),
        ),
      ],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('golden: dashboard', (WidgetTester tester) async {
    await _pumpGolden(tester, const DashboardScreen());
    await expectLater(
      find.byType(DashboardScreen),
      matchesGoldenFile('goldens/dashboard.png'),
    );
  });

  testWidgets('golden: monitor list', (WidgetTester tester) async {
    await _pumpGolden(tester, const MonitorsScreen());
    await expectLater(
      find.byType(MonitorsScreen),
      matchesGoldenFile('goldens/monitor_list.png'),
    );
  });

  testWidgets('golden: monitor detail', (WidgetTester tester) async {
    await _pumpGolden(tester, const MonitorDetailScreen(monitorId: 'm1'));
    await expectLater(
      find.byType(MonitorDetailScreen),
      matchesGoldenFile('goldens/monitor_detail.png'),
    );
  });

  testWidgets('golden: incidents feed', (WidgetTester tester) async {
    await _pumpGolden(tester, const IncidentsScreen());
    await expectLater(
      find.byType(IncidentsScreen),
      matchesGoldenFile('goldens/incidents.png'),
    );
  });

  testWidgets('golden: incident detail', (WidgetTester tester) async {
    await _pumpGolden(tester, const IncidentDetailScreen(incidentId: 'i1'));
    await expectLater(
      find.byType(IncidentDetailScreen),
      matchesGoldenFile('goldens/incident_detail.png'),
    );
  });
}
