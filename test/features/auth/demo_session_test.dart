import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/app.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/demo_session.dart';
import 'package:uptrack_mobile/features/auth/social_login.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';

void main() {
  test('demo data covers dashboard, detail, charts and settings without credentials', () async {
    final dio = Dio()..httpClientAdapter = DemoAdapter();
    addTearDown(dio.close);
    final api = UptrackApi(dio: dio);
    expect((await api.getMe()).organization.name, 'Uptrack Demo');
    final monitors = await api.listMonitors();
    expect(monitors.data.length, 3);
    expect((await api.getMonitor('demo-api')).status, 'down');
    expect((await api.listChecks('demo-api')).data.first.statusCode, 503);
    expect(
      (await api.getMonitorAnalytics('demo-api')).responseTimes.length,
      25,
    );
    expect((await api.listIncidents(status: 'ongoing')).data.length, 1);
    expect(
      (await api.getIncident('demo-incident')).incident.isAcknowledged,
      isFalse,
    );
    expect(
      (await api.acknowledgeIncident('demo-incident')).incident.isAcknowledged,
      isTrue,
    );
    expect(
      (await api.getIncident('demo-incident')).incident.isAcknowledged,
      isTrue,
    );
    await api.updateNotificationPreferences(<String, Object?>{
      'mobile_push_enabled': false,
    });
    expect((await api.getNotificationPreferences()).mobilePushEnabled, isFalse);
    expect((await api.getBillingSubscription()).plan, 'pro');
    expect(await api.listDeviceTokens(), isEmpty);
    expect(dio.options.headers['Authorization'], isNull);
    final fresh = UptrackApi(dio: Dio()..httpClientAdapter = DemoAdapter());
    expect(
      (await fresh.getIncident('demo-incident')).incident.isAcknowledged,
      isFalse,
    );
  });

  test(
    'demo rejects real-account, push and unknown operations locally',
    () async {
      final dio = Dio()..httpClientAdapter = DemoAdapter();
      addTearDown(dio.close);
      final api = UptrackApi(dio: dio);
      for (final operation in <Future<Object?> Function()>[
        () => api.deleteAccount(),
        () => api.registerPushDevice(platform: 'android', token: 'test-push'),
        () => api.createDeviceToken(),
        () => dio.get<Object?>('https://production.invalid/api/private'),
      ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<DioException>().having(
              (e) => e.response?.statusCode,
              'local status',
              403,
            ),
          ),
        );
      }
    },
  );

  testWidgets(
    'signed-out tester can enter sample dashboard and exit to login',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryTokenStore();
      final container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(store),
          socialProvidersProvider.overrideWith((ref) async => <String>{}),
        ],
      );
      addTearDown(container.dispose);
      final router = createRouter(
        authStatusOf: () => AuthStatus.signedOut,
        initialLocation: '/login',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('try-demo')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('try-demo')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(find.bySemanticsLabel('Exit demo'), findsOneWidget);
      expect(find.bySemanticsLabel('Demo · sample data'), findsOneWidget);
      semantics.dispose();
      expect(find.text('Demo · sample data'), findsOneWidget);
      expect(find.text('Public API'), findsOneWidget);
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedOut,
      );
      expect(await store.readDeviceToken(), isNull);
      await tester.tap(find.text('Monitors').last);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Marketing website'), findsOneWidget);
      await tester.tap(find.text('Marketing website'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Response time'), findsOneWidget);
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(find.text('Uptrack Demo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Exit demo'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Uptrack'), findsOneWidget);
      expect(find.text('Demo · sample data'), findsNothing);
      expect(await store.readDeviceToken(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets('iOS has normal login and cannot enter demo through a link', (
    tester,
  ) async {
    final router = createRouter(
      authStatusOf: () => AuthStatus.signedOut,
      initialLocation: '/demo',
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
          socialProvidersProvider.overrideWith((ref) async => <String>{}),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Uptrack'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('try-demo')), findsNothing);
    expect(find.text('Demo · sample data'), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/login');
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
