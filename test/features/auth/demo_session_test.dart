import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/app.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/demo_session.dart';
import 'package:uptrack_mobile/features/auth/social_login.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';

void main() {
  group('demo banner layout', () {
    /// The banner chooses its layout from a measurement of the scaled text, so
    /// both outcomes are worth pinning down: the one-row banner where the text
    /// and the action fit side by side, and — on a phone at 200%, in
    /// `demo_chip_acceptance_test.dart` — the stacked one where they do not.
    ///
    /// The default test surface is 800dp wide, which is where the row fits: the
    /// explanation and "Exit demo" together need less than that at normal text.
    testWidgets('keeps one compact row where the text and action fit', (
      tester,
    ) async {
      await tester.pumpWidget(DemoSessionScreen(onExit: () {}));
      await tester.pumpAndSettle();

      final Rect message = tester.getRect(find.text('Demo · sample data'));
      final Rect action = tester.getRect(
        find.widgetWithText(TextButton, 'Exit demo'),
      );
      final Rect banner = tester.getRect(
        find.ancestor(
          of: find.text('Demo · sample data'),
          matching: find.byType(Material),
        ),
      );

      expect(
        message.top,
        lessThan(action.bottom),
        reason: 'the explanation and the action share the row when it fits',
      );
      expect(
        action.top,
        lessThan(message.bottom),
        reason: 'the explanation and the action share the row when it fits',
      );
      // One line, not a wrap: the height the row gave the text is the height
      // that text needs on a single line at the width it was given.
      final Finder explanation = find.text('Demo · sample data');
      final BuildContext context = tester.element(explanation);
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: 'Demo · sample data',
          style: DefaultTextStyle.of(context).style
              .merge(tester.widget<Text>(explanation).style),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: message.width);
      addTearDown(painter.dispose);
      expect(
        message.height,
        lessThanOrEqualTo(painter.height + 0.5),
        reason: 'the explanation must stay on one line in the row',
      );
      expect(
        painter.didExceedMaxLines,
        isFalse,
        reason: 'the explanation must not be clipped or ellipsised',
      );
      expect(
        banner.height,
        lessThanOrEqualTo(80),
        reason: 'one row of text and the action must stay a short banner',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('stacks the action below the text where the row cannot fit', (
      tester,
    ) async {
      // A phone-width window at 200% text: the row cannot hold both without
      // squeezing the explanation, so the banner goes vertical instead of
      // wrapping the explanation over most of the screen.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(DemoSessionScreen(onExit: () {}));
      await tester.pumpAndSettle();

      final Rect message = tester.getRect(find.text('Demo · sample data'));
      final Rect action = tester.getRect(
        find.widgetWithText(TextButton, 'Exit demo'),
      );
      final Rect banner = tester.getRect(
        find.ancestor(
          of: find.text('Demo · sample data'),
          matching: find.byType(Material),
        ),
      );

      expect(
        message.bottom,
        lessThanOrEqualTo(action.top),
        reason: 'at 200% the text gets the full width above the action',
      );
      expect(
        message.width,
        closeTo(banner.width - 32, 1),
        reason: 'the text is not squeezed into a narrow column',
      );
      expect(
        banner.height,
        lessThanOrEqualTo(844 * 0.25),
        reason: 'a few lines at most, not the screen',
      );
      expect(
        action.height,
        greaterThanOrEqualTo(48),
        reason: 'the stacked action keeps its 48dp target',
      );
      expect(tester.takeException(), isNull);
    });
  });

  test(
    'demo exercises all three response actions in isolated fake state',
    () async {
      final dio = Dio()..httpClientAdapter = DemoAdapter();
      addTearDown(dio.close);
      final api = UptrackApi(dio: dio);

      // 1. Escalate: fires the sample policy steps on an open incident.
      final escalate = await api.escalateIncident('demo-incident');
      expect(escalate.escalated, isTrue);
      expect(escalate.stepsFired, DemoAdapter.demoEscalationSteps);

      // 2. Snooze: monitor-scoped, this user only, with a returned expiry.
      final snooze = await api.snoozeMonitor(DemoAdapter.snoozedMonitorId);
      expect(
        DateTime.parse(snooze.snoozedUntil).isAfter(DateTime.now().toUtc()),
        isTrue,
        reason: 'the demo snooze must return a future expiry',
      );

      // 3. Acknowledge: reflected in the feed and the dashboard, not just the
      // detail the action returned.
      expect(
        (await api.acknowledgeIncident('demo-incident'))
            .incident
            .isAcknowledged,
        isTrue,
      );
      final ongoing = (await api.listIncidents(status: 'ongoing')).data;
      expect(
        ongoing
            .where((Incident i) => i.isAcknowledged)
            .map((Incident i) => i.id),
        <String>[
          DemoAdapter.openIncidentId,
          DemoAdapter.acknowledgedIncidentId,
        ],
        reason:
            'the acknowledged row and the one that was already '
            'acknowledged are the only acknowledged ones',
      );
      expect(
        ongoing
            .where((Incident i) => i.id == DemoAdapter.unattendedIncidentId)
            .single
            .isAcknowledged,
        isFalse,
        reason:
            'the endpoint addresses one row: acknowledging one incident '
            'must not acknowledge the others',
      );

      // Acknowledging makes escalation a no-op, matching the backend.
      expect((await api.escalateIncident('demo-incident')).escalated, isFalse);
      expect((await api.escalateIncident('demo-incident')).stepsFired, 0);

      // A resolved incident cannot be escalated at all.
      expect((await api.escalateIncident('demo-resolved')).escalated, isFalse);

      // No live mutation: a second workspace starts unacknowledged, unescalated
      // and unsnoozed.
      final fresh = UptrackApi(dio: Dio()..httpClientAdapter = DemoAdapter());
      expect(
        (await fresh.getIncident('demo-incident')).incident.isAcknowledged,
        isFalse,
      );
      expect((await fresh.escalateIncident('demo-incident')).escalated, isTrue);
    },
  );

  test(
    'demo refuses unknown monitors for snooze without touching state',
    () async {
      final dio = Dio()..httpClientAdapter = DemoAdapter();
      addTearDown(dio.close);
      final api = UptrackApi(dio: dio);

      await expectLater(
        api.snoozeMonitor('not-a-demo-monitor'),
        throwsA(
          isA<DioException>().having(
            (DioException e) => e.response?.statusCode,
            'local status',
            404,
          ),
        ),
      );
      expect((await api.listMonitors()).data, hasLength(3));
    },
  );

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
    // The journey needs both an open incident nobody answered and one already
    // acknowledged, so every dashboard section has something to show.
    final ongoing = (await api.listIncidents(status: 'ongoing')).data;
    expect(
      ongoing
          .where((Incident i) => i.id == DemoAdapter.openIncidentId)
          .single
          .isAcknowledged,
      isFalse,
    );
    expect(
      ongoing
          .where((Incident i) => i.id == DemoAdapter.acknowledgedIncidentId)
          .single
          .isAcknowledged,
      isTrue,
    );
    expect(
      ongoing
          .where((Incident i) => i.id == DemoAdapter.unattendedIncidentId)
          .single
          .isAcknowledged,
      isFalse,
    );
    expect(
      (await api.listIncidents()).data,
      hasLength(ongoing.length + 1),
      reason: 'plus one resolved row for the history section',
    );
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
