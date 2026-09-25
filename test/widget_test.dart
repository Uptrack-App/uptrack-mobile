import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uptrack_mobile/app.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_controller.dart';
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
