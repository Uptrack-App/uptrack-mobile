import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uptrack_mobile/api/models/check.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/api/models/monitor.dart';
import 'package:uptrack_mobile/api/models/monitor_analytics.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_controller.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_screen.dart';
import 'package:uptrack_mobile/features/incidents/incidents_controller.dart';
import 'package:uptrack_mobile/features/incidents/incidents_screen.dart';
import 'package:uptrack_mobile/features/monitors/monitor_detail_controller.dart';
import 'package:uptrack_mobile/features/monitors/monitor_detail_screen.dart';
import 'package:uptrack_mobile/features/settings/settings_screen.dart';

/// Store screenshots (T050): renders dashboard, monitor detail, incidents,
/// and settings with stubbed data and captures a screenshot of each.
///
/// Runs in two modes:
/// * host (`flutter test`): screens are pumped and content-asserted; the
///   capture is best-effort and skipped when the platform channel has no
///   host implementation (MissingPluginException).
/// * device (`flutter test <this file> -d <emulator>`): screenshots are
///   written to `<cache>/uptrack_screenshots/<name>.png` on the device;
///   the host then pulls them with
///   `adb exec-out run-as <package> cat cache/uptrack_screenshots/<n>.png`
///   into `store/screenshots/en-US/`.

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

/// Fake [HttpClientAdapter] returning canned JSON without network access
/// (same pattern as `test/features/settings/settings_sections_test.dart`).
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, Object?> json) => ResponseBody.fromString(
  jsonEncode(json),
  200,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>[Headers.jsonContentType],
  },
);

Future<ResponseBody> _settingsHandler(RequestOptions options) async {
  final String path = options.path;
  if (path == kGetMePath) {
    return _json(<String, Object?>{
      'user': <String, Object?>{
        'id': 'u1',
        'name': 'Ada Lovelace',
        'email': 'ada@example.com',
        'provider': null,
        'role': 'owner',
        'is_admin': true,
        'preferred_locale': null,
        'inserted_at': '2026-01-01T00:00:00Z',
      },
      'organization': <String, Object?>{
        'id': 'o1',
        'name': 'Acme',
        'slug': 'acme',
        'plan': 'pro',
        'features_enabled': true,
      },
    });
  }
  if (path == kNotificationPreferencesPath) {
    return _json(<String, Object?>{
      'user_id': 'u1',
      'severity_overrides': <String, Object?>{},
      'quiet_hours_start': null,
      'quiet_hours_end': null,
      'mobile_push_enabled': true,
      'digest_p3': true,
    });
  }
  if (path == kBillingSubscriptionPath) {
    return _json(<String, Object?>{'data': null, 'plan': 'pro'});
  }
  if (path == kDeviceTokensPath) {
    return _json(<String, Object?>{'data': <Object?>[]});
  }
  return _json(<String, Object?>{'ok': true});
}

ProviderContainer _settingsContainer() {
  final AuthTokenHolder holder = AuthTokenHolder()..token = 'udt_test';
  return ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
      authTokenHolderProvider.overrideWithValue(holder),
      dioProvider.overrideWithValue(
        buildAppDio(
          holder: holder,
          onUnauthorized: () {},
          adapter: _FakeAdapter(_settingsHandler),
        ),
      ),
    ],
  );
}

Future<void> _pumpShot(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  Widget home,
  String name,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dashboardRepositoryProvider.overrideWithValue(_DashboardRepo()),
        monitorDetailRepositoryProvider.overrideWithValue(_MonitorDetailRepo()),
        incidentsRepositoryProvider.overrideWithValue(_IncidentsRepo()),
      ],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
  try {
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    final List<int> bytes = await binding.takeScreenshot(name);
    final Directory dir = Directory(
      '${Directory.systemTemp.path}/uptrack_screenshots',
    );
    await dir.create(recursive: true);
    debugPrint('SHOT_DIR ${dir.path}');
    await File('${dir.path}/$name.png').writeAsBytes(bytes, flush: true);
    debugPrint('SCREENSHOT_SAVED $name ${bytes.length}');
  } on Exception catch (e) {
    // Host `flutter test` run: no platform implementation — assert the
    // content only and let the device run produce the PNGs.
    debugPrint('SCREENSHOT_SKIPPED $name $e');
  }
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('store screenshots', () {
    testWidgets('dashboard', (WidgetTester tester) async {
      await _pumpShot(tester, binding, const DashboardScreen(), 'dashboard');
      expect(find.byType(DashboardScreen), findsOneWidget);
    }, timeout: const Timeout(Duration(minutes: 5)));

    testWidgets('monitor detail', (WidgetTester tester) async {
      await _pumpShot(
        tester,
        binding,
        const MonitorDetailScreen(monitorId: 'm1'),
        'monitor-detail',
      );
      expect(find.byType(MonitorDetailScreen), findsOneWidget);
    }, timeout: const Timeout(Duration(minutes: 5)));

    testWidgets('incidents', (WidgetTester tester) async {
      await _pumpShot(tester, binding, const IncidentsScreen(), 'incidents');
      expect(find.byType(IncidentsScreen), findsOneWidget);
    }, timeout: const Timeout(Duration(minutes: 5)));

    testWidgets('settings', (WidgetTester tester) async {
      final ProviderContainer container = _settingsContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      try {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        final List<int> bytes = await binding.takeScreenshot('settings');
        final Directory dir = Directory(
          '${Directory.systemTemp.path}/uptrack_screenshots',
        );
        await dir.create(recursive: true);
        debugPrint('SHOT_DIR ${dir.path}');
        await File('${dir.path}/settings.png').writeAsBytes(bytes, flush: true);
        debugPrint('SCREENSHOT_SAVED settings ${bytes.length}');
      } on Exception catch (e) {
        debugPrint('SCREENSHOT_SKIPPED settings $e');
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    // Device-only hold-open: `flutter test -d` uninstalls the test app as
    // soon as the suite finishes, which races the host-side `adb run-as`
    // pull. This trailing test keeps the app (and its cached PNGs)
    // installed for ~2 minutes so the host can pull them. Skipped on the
    // host (CI runs on macOS/windows/linux, never Android).
    testWidgets('hold open for host pull (device only)', (
      WidgetTester tester,
    ) async {
      if (!Platform.isAndroid) {
        return;
      }
      debugPrint('HOLD_OPEN');
      await Future<void>.delayed(const Duration(seconds: 150));
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
