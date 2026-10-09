import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/app.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/database_providers.dart';
import 'package:uptrack_mobile/design/uptrack_design.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/demo_session.dart';
import 'package:uptrack_mobile/features/auth/social_login.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/features/monitors/monitors_controller.dart';
import 'package:uptrack_mobile/features/monitors/monitors_screen.dart';
import 'package:uptrack_mobile/features/incidents/incidents_controller.dart';
import 'package:uptrack_mobile/features/incidents/incidents_screen.dart';

Future<void> settleData(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
    () async => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'busy action retains label, exposes progress and blocks callback',
    (tester) async {
      var taps = 0;
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: UptrackButton(
              label: 'Save preferences',
              busy: true,
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      expect(find.text('Save preferences'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('In progress')), findsNothing);
      expect(
        tester.getSemantics(find.byType(UptrackButton)).value,
        'In progress',
      );
      await tester.tap(find.text('Save preferences'));
      expect(taps, 0);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: UptrackButton(
              label: 'Save preferences',
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Save preferences'));
      expect(taps, 1);
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(48),
      );
      handle.dispose();
    },
  );

  testWidgets(
    'health retains specific conditions and unrecognized means unknown',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Wrap(
              children: [
                UptrackStatusBadge(status: 'visual_regression'),
                UptrackStatusBadge(status: 'partial_outage'),
                UptrackStatusBadge(status: 'future_state'),
                UptrackLifecycleBadge(open: true, acknowledged: true),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Changed'), findsOneWidget);
      expect(find.text('Partial outage'), findsOneWidget);
      expect(find.text('Unknown'), findsOneWidget);
      expect(find.text('Open · Acknowledged'), findsOneWidget);
      expect(find.text('Resolved'), findsNothing);
    },
  );

  testWidgets(
    'chart has formatted time labels and exact samples, not epoch axis',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: UptrackResponseChart(
                period: 'Last hour',
                summary: 'p50 120 ms',
                points: [
                  UptrackChartPoint(
                    time: DateTime.utc(2026, 10, 4, 10),
                    milliseconds: 120,
                  ),
                  UptrackChartPoint(
                    time: DateTime.utc(2026, 10, 4, 11),
                    milliseconds: 140,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1.7B'), findsNothing);
      await tester.tap(find.text('View recorded samples'));
      await tester.pumpAndSettle();
      expect(find.text('120.0 ms'), findsOneWidget);
      expect(find.text('140.0 ms'), findsOneWidget);
      expect(find.textContaining('2026-10-04'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'production shell exposes settings, retains filters and clears them after logout',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var status = AuthStatus.signedIn;
      final refresh = ValueNotifier(0);
      addTearDown(refresh.dispose);
      final router = createRouter(
        authStatusOf: () => status,
        refreshListenable: refresh,
      );
      addTearDown(router.dispose);
      final dio = Dio()..httpClientAdapter = DemoAdapter();
      addTearDown(dio.close);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            uptrackApiProvider.overrideWithValue(UptrackApi(dio: dio)),
            appDatabaseProvider.overrideWithValue(database),
            tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
            socialProvidersProvider.overrideWith((ref) async => <String>{}),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await settleData(tester);
      await tester.tap(find.byKey(const ValueKey('destination-1')));
      await settleData(tester);
      await tester.enterText(find.byType(TextField).first, 'zz-no-match');
      await tester.pumpAndSettle();
      expect(find.text('No monitors match your search.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('destination-3')));
      await settleData(tester);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.byTooltip('View public status page'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('destination-1')));
      await settleData(tester);
      expect(find.text('No monitors match your search.'), findsOneWidget);
      status = AuthStatus.signedOut;
      refresh.value++;
      await settleData(tester);
      expect(find.text('Welcome to Uptrack'), findsOneWidget);
      status = AuthStatus.signedIn;
      refresh.value++;
      await settleData(tester);
      await tester.tap(find.byKey(const ValueKey('destination-1')));
      await settleData(tester);
      expect(find.text('No monitors match your search.'), findsNothing);
      expect(find.text('Marketing website'), findsOneWidget);
    },
  );

  testWidgets('cold incident detail selects Incidents and has parent Back', (
    tester,
  ) async {
    final router = createRouter(initialLocation: '/incidents/demo-incident');
    addTearDown(router.dispose);
    final dio = Dio()..httpClientAdapter = DemoAdapter();
    addTearDown(dio.close);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          uptrackApiProvider.overrideWithValue(UptrackApi(dio: dio)),
          appDatabaseProvider.overrideWithValue(database),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await settleData(tester);
    expect(
      tester
          .widget<UptrackAdaptiveScaffold>(find.byType(UptrackAdaptiveScaffold))
          .selectedIndex,
      2,
    );
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await settleData(tester);
    expect(router.routeInformationProvider.value.uri.path, '/incidents');
  });

  for (final width in [320.0, 768.0, 1024.0]) {
    testWidgets('adaptive navigation fits $width width at 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: UptrackAdaptiveScaffold(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            child: const Scaffold(
              body: UptrackMetricTile(label: 'Average uptime', value: '99.95%'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byType(width < 600 ? NavigationBar : NavigationRail),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'filter-empty monitor and incident cache keeps offline notice and refresh',
    (tester) async {
      final api = UptrackApi(dio: Dio()..httpClientAdapter = DemoAdapter());
      final monitors = (await tester.runAsync(api.listMonitors))!.data;
      final incidents = (await tester.runAsync(api.listIncidents))!.data;
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            monitorsProvider.overrideWith(
              (ref) async => MonitorsData(monitors: monitors, offline: true),
            ),
            incidentsProvider.overrideWith(
              (ref) async => IncidentsData(
                incidents: incidents.where((i) => !i.isOngoing).toList(),
                offline: true,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const MonitorsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'not-present');
      await tester.pumpAndSettle();
      expect(find.text('Offline — showing cached data'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            incidentsProvider.overrideWith(
              (ref) async => IncidentsData(
                incidents: incidents.where((i) => !i.isOngoing).toList(),
                offline: true,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const IncidentsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('No open incidents.'), findsOneWidget);
      expect(find.text('Offline — showing cached data'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
    },
  );
}
