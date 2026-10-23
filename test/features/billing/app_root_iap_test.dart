import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/app.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/database_providers.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/features/billing/app_store.dart';
import 'package:uptrack_mobile/features/billing/apple_purchase_controller.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_controller.dart';
import 'package:uptrack_mobile/features/monitors/monitors_controller.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/push/push_providers.dart';
import 'package:uptrack_mobile/push/push_service.dart';

import '../auth/auth_test.dart'
    show FakeAdapter, issuanceFixture, jsonResponse, meFixture;
import 'fake_app_store.dart';

// Plan step 5.12: the full app root, not only the controller. A
// transaction that an earlier launch left unfinished goes to the server
// when the user signs in, and StoreKit finishes it after the 200.

class _StubDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardData> load() async => DashboardData(
    totalMonitors: 0,
    loadedMonitors: 0,
    totalMonitorsKnown: true,
    countsByStatus: const <String, int>{},
    averageUptime: 100,
    offline: false,
  );
}

class _StubMonitorsRepository implements MonitorsRepository {
  @override
  Future<MonitorsData> load() async =>
      const MonitorsData(monitors: [], offline: false);
}

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

void main() {
  testWidgets('UptrackApp sends unfinished App Store transactions at sign-in', (
    WidgetTester tester,
  ) async {
    // A phone screen, so the whole login form fits.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final String orgId =
        (meFixture()['organization']! as Map<String, Object?>)['id']! as String;
    final FakeAppStore store = FakeAppStore(
      leftovers: <StoreTransaction>[
        purchased(
          'app.uptrack.mobile.pro.monthly',
          'tx-left',
          token: orgId.toUpperCase(),
        ),
      ],
    );
    final List<RequestOptions> posted = <RequestOptions>[];
    final AuthTokenHolder holder = AuthTokenHolder();
    final FakeAdapter adapter = FakeAdapter((RequestOptions o) async {
      switch ('${o.method} ${o.path}') {
        case 'GET /api/auth/providers':
          return jsonResponse(<String, Object?>{
            'providers': <String, Object?>{},
          });
        case 'POST $kMagicLinkPath':
          return jsonResponse(<String, Object?>{'ok': true});
        case 'POST $kMagicLinkVerifyPath':
          return jsonResponse(meFixture());
        case 'POST $kDeviceTokensPath':
          return jsonResponse(issuanceFixture(), 201);
        case 'GET $kGetMePath':
          return jsonResponse(meFixture());
        case 'POST $kAppleTransactionsPath':
          posted.add(o);
          return jsonResponse(<String, Object?>{
            'plan': 'pro',
            'data': <String, Object?>{
              'id': 's1',
              'plan': 'pro',
              'status': 'active',
              'provider': 'apple',
              'apple_product_id': 'app.uptrack.mobile.pro.monthly',
            },
          });
      }
      return jsonResponse(<String, Object?>{});
    });
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    late final ProviderContainer container;
    container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        authTokenHolderProvider.overrideWithValue(holder),
        dioProvider.overrideWithValue(
          buildAppDio(
            holder: holder,
            onUnauthorized: () => container
                .read(authControllerProvider.notifier)
                .handleUnauthorized(),
            adapter: adapter,
          ),
        ),
        appDatabaseProvider.overrideWithValue(db),
        dashboardRepositoryProvider.overrideWithValue(
          _StubDashboardRepository(),
        ),
        monitorsRepositoryProvider.overrideWithValue(_StubMonitorsRepository()),
        pushServiceProvider.overrideWithValue(
          PushService(
            registerToken: ({
              required String platform,
              required String token,
              String? environment,
            }) async {},
            onNavigate: (_) {},
            notifier: _NoopNotifier(),
          ),
        ),
        appStoreClientProvider.overrideWithValue(store),
        appleIapEnabledProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const UptrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Signed out: nothing goes to the server.
    expect(find.text('Email me a sign-in link'), findsOneWidget);
    expect(posted, isEmpty);

    // Sign in on the login screen (email link, code pasted).
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'ada@example.com',
    );
    await tester.ensureVisible(find.text('Email me a sign-in link'));
    await tester.tap(find.text('Email me a sign-in link'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Sign-in link or code'),
      'magic_code',
    );
    // The keyboard's submit key, as the user does after a paste.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(container.read(authControllerProvider).status, AuthStatus.signedIn);
    expect(posted, hasLength(1));
    expect(
      (posted.single.data as Map<dynamic, dynamic>)['signed_transaction'],
      'jws.tx-left',
    );
    // Sent with the device token of the new session.
    expect(
      posted.single.headers['Authorization'],
      'Bearer ${issuanceFixture()['token']}',
    );
    expect(store.finished, <String>['tx-left']);
  });
}
