import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uptrack_mobile/app.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_controller.dart';
import 'package:uptrack_mobile/features/monitors/monitors_controller.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/push/push_providers.dart';
import 'package:uptrack_mobile/push/push_service.dart';
import 'package:uptrack_mobile/theme/app_theme.dart';

/// The dashboard loads over HTTP + Drift (background isolate), which never
/// settles under fake-async `pumpAndSettle` — so the shell test swaps in a
/// canned repository (dashboard content itself is covered in
/// `test/features/dashboard/dashboard_test.dart`).
class _StubDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardData> load() async => const DashboardData(
    totalMonitors: 1,
    countsByStatus: <String, int>{'up': 1},
    averageUptime: 100,
    recentIncidents: [],
    offline: false,
  );
}

/// The monitors list loads over HTTP + Drift (background isolate), which
/// never settles under fake-async `pumpAndSettle` — so the shell test swaps
/// in a canned repository (list content itself is covered in
/// `test/features/monitors/monitors_test.dart`).
class _StubMonitorsRepository implements MonitorsRepository {
  @override
  Future<MonitorsData> load() async =>
      const MonitorsData(monitors: [], offline: false);
}

/// Push touches native method channels + the local-notifications plugin, so
/// the shell test swaps in a service with inert seams (push flows themselves
/// are covered in `test/push/push_test.dart` with fake channels).
class _NoopNotifier implements LocalNotifier {
  @override
  Future<void> initialize({
    required void Function(PushMessage message) onTap,
  }) async {}

  @override
  Future<PushMessage?> initialNotification() async => null;

  @override
  Future<void> showForeground(PushMessage message) async {}
}

PushService _stubPushService() {
  return PushService(
    registerToken: ({
      required String platform,
      required String token,
      String? environment,
    }) async {},
    onNavigate: (_) {},
    notifier: _NoopNotifier(),
  );
}

void main() {
  testWidgets('dark app theme builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: Text('Dark theme')),
      ),
    );

    expect(find.text('Dark theme'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Dark theme'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('app shell shows dashboard and navigates to monitors', (
    WidgetTester tester,
  ) async {
    final GoRouter router = createRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routerProvider.overrideWithValue(router),
          dashboardRepositoryProvider.overrideWithValue(
            _StubDashboardRepository(),
          ),
          monitorsRepositoryProvider.overrideWithValue(
            _StubMonitorsRepository(),
          ),
          pushServiceProvider.overrideWithValue(_stubPushService()),
        ],
        child: const UptrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);

    router.go('/monitors');
    await tester.pumpAndSettle();

    expect(find.text('Monitors'), findsOneWidget);
  });
}
