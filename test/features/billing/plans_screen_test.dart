import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/billing_subscription.dart';
import 'package:uptrack_mobile/api/models/current_user.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/billing/app_store.dart';
import 'package:uptrack_mobile/features/billing/apple_plans.dart';
import 'package:uptrack_mobile/features/billing/apple_purchase_controller.dart';
import 'package:uptrack_mobile/features/billing/plans_screen.dart';
import 'package:uptrack_mobile/features/settings/billing_section.dart';
import 'package:uptrack_mobile/features/settings/danger_zone_section.dart';
import 'package:uptrack_mobile/features/settings/profile_section.dart';

import '../auth/auth_test.dart' show FakeAdapter, jsonResponse, meFixture;
import 'fake_app_store.dart';

CurrentUserResponse _me({String role = 'owner', String plan = 'free'}) {
  final Map<String, Object?> json = meFixture();
  (json['user']! as Map<String, Object?>)['role'] = role;
  (json['organization']! as Map<String, Object?>)['plan'] = plan;
  return CurrentUserResponse.fromJson(json);
}

BillingSubscriptionInfo _billing({
  String? provider,
  String plan = 'free',
  String status = 'active',
  String? productId,
}) => BillingSubscriptionInfo.fromJson(<String, Object?>{
  'plan': plan,
  'data': provider == null
      ? null
      : <String, Object?>{
          'id': 's1',
          'plan': plan,
          'status': status,
          'current_period_end': '2026-11-23T00:00:00Z',
          'provider': provider,
          'apple_product_id': productId,
        },
});

class _Setup {
  _Setup({
    FakeAppStore? store,
    this.role = 'owner',
    BillingSubscriptionInfo? billing,
    this.iapEnabled = true,
  }) : store = store ?? FakeAppStore(),
       billing = billing ?? _billing();

  final FakeAppStore store;
  final String role;
  final BillingSubscriptionInfo billing;
  final bool iapEnabled;
  final List<String> posted = <String>[];

  ProviderScope wrap(Widget child) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:4000'));
    dio.httpClientAdapter = FakeAdapter((RequestOptions o) async {
      if (o.path == kGetMePath) {
        final Map<String, Object?> json = meFixture();
        (json['user']! as Map<String, Object?>)['role'] = role;
        return jsonResponse(json);
      }
      if (o.path == kAppleTransactionsPath) {
        posted.add(
          (o.data as Map<dynamic, dynamic>)['signed_transaction'] as String,
        );
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
      return jsonResponse(<String, Object?>{'ok': true});
    });
    return ProviderScope(
      overrides: [
        appStoreClientProvider.overrideWithValue(store),
        appleIapEnabledProvider.overrideWithValue(iapEnabled),
        uptrackApiProvider.overrideWithValue(UptrackApi(dio: dio)),
        settingsProfileProvider.overrideWith(
          (Ref ref) async => _me(role: role, plan: billing.plan),
        ),
        settingsBillingProvider.overrideWith((Ref ref) async => billing),
      ],
      child: MaterialApp(home: child),
    );
  }
}

Future<void> _scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 300,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey<String>('plans-list')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Widget _settingsBody() => Scaffold(
  body: ListView(
    key: const ValueKey<String>('plans-list'),
    children: const <Widget>[BillingSection(), DangerZoneSection()],
  ),
);

void main() {
  group('PlansScreen (3.1.2)', () {
    testWidgets('shows App Store prices, periods and plan facts', (
      WidgetTester tester,
    ) async {
      final _Setup s = _Setup();
      await tester.pumpWidget(s.wrap(const PlansScreen()));
      await tester.pumpAndSettle();

      // Prices come from the store, never from the app.
      expect(find.text('€3.49 / month'), findsOneWidget);
      expect(find.text('\$2.99 / month'), findsNothing);
      expect(find.text('Pro'), findsOneWidget);
      expect(find.text('For serious monitoring on a budget.'), findsOneWidget);
      expect(find.text('50 monitors — all at 30s'), findsOneWidget);
      expect(find.text('Not included: Custom domain'), findsOneWidget);
      expect(
        find.text('Auto-renewing subscription. Period: 1 month.'),
        findsWidgets,
      );

      await tester.tap(find.text('Yearly'));
      await tester.pumpAndSettle();
      expect(find.text('€34.99 / year'), findsOneWidget);
      await _scrollTo(
        tester,
        find.byKey(const ValueKey<String>('plan-business')),
      );
      // The store has no Business yearly here: the plan text stays (D3).
      await _scrollTo(
        tester,
        find.text('Not available in the App Store right now.'),
      );
      expect(find.text('SSO / SAML'), findsOneWidget);
    });

    testWidgets('Terms of Use, Privacy Policy and Restore Purchases work', (
      WidgetTester tester,
    ) async {
      final _Setup s = _Setup(
        store: FakeAppStore(
          restored: <StoreTransaction>[
            restoredTx(
              'app.uptrack.mobile.pro.monthly',
              'tx-r',
              token: '22222222-2222-4222-8222-222222222222',
            ),
          ],
        ),
      );
      await tester.pumpWidget(s.wrap(const PlansScreen()));
      await tester.pumpAndSettle();

      final Finder terms = find.byKey(const ValueKey<String>('terms-of-use'));
      await _scrollTo(tester, terms);
      await tester.tap(terms);
      await tester.tap(find.byKey(const ValueKey<String>('privacy-policy')));
      await tester.pumpAndSettle();
      expect(s.store.opened, <Uri>[kTermsOfUseUrl, kPrivacyPolicyUrl]);
      expect(kTermsOfUseUrl.toString(), 'https://uptrack.app/terms');
      expect(kPrivacyPolicyUrl.toString(), 'https://uptrack.app/privacy');

      final Finder restore = find.byKey(
        const ValueKey<String>('restore-purchases'),
      );
      await _scrollTo(tester, restore);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(s.store.restores, 1);
      expect(s.posted, <String>['jws.tx-r']);
      expect(s.store.finished, <String>['tx-r']);
      await _scrollTo(
        tester,
        find.byKey(const ValueKey<String>('purchase-notice')),
        delta: -300,
      );
      expect(
        find.text('Purchases restored. Your plan is Pro.'),
        findsOneWidget,
      );
    });

    testWidgets('the owner buys a plan', (WidgetTester tester) async {
      final _Setup s = _Setup();
      await tester.pumpWidget(s.wrap(const PlansScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Subscribe to Pro'));
      await tester.pumpAndSettle();
      expect(s.store.buys.single.productId, 'app.uptrack.mobile.pro.monthly');
      expect(s.store.finished, <String>['tx-app.uptrack.mobile.pro.monthly']);
      expect(find.text('Thank you. Your plan is now Pro.'), findsOneWidget);
    });

    testWidgets('with an Apple plan, other plans switch (5.8)', (
      WidgetTester tester,
    ) async {
      final _Setup s = _Setup(
        billing: _billing(
          provider: 'apple',
          plan: 'pro',
          productId: 'app.uptrack.mobile.pro.monthly',
        ),
      );
      await tester.pumpWidget(s.wrap(const PlansScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Current plan'), findsOneWidget);
      expect(find.text('Switch to Team'), findsOneWidget);
    });

    testWidgets('a member sees the plans read-only (D8)', (
      WidgetTester tester,
    ) async {
      final _Setup s = _Setup(role: 'member');
      await tester.pumpWidget(s.wrap(const PlansScreen()));
      await tester.pumpAndSettle();
      expect(
        find.text('Only the organization owner can buy or change the plan.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Subscribe to Pro'));
      await tester.pumpAndSettle();
      expect(s.store.buys, isEmpty);
    });

    testWidgets('a Paddle organization cannot buy here (D7)', (
      WidgetTester tester,
    ) async {
      final _Setup s = _Setup(
        billing: _billing(provider: 'paddle', plan: 'team'),
      );
      await tester.pumpWidget(s.wrap(const PlansScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Your plan is managed on the web.'), findsOneWidget);
      await tester.tap(find.text('Subscribe to Pro'));
      await tester.pumpAndSettle();
      expect(s.store.buys, isEmpty);
    });

    testWidgets('a product query error offers a retry', (
      WidgetTester tester,
    ) async {
      final FakeAppStore store = FakeAppStore()..productsError = Exception('x');
      final _Setup s = _Setup(store: store);
      await tester.pumpWidget(s.wrap(const PlansScreen()));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not load the prices from the App Store'),
        findsOneWidget,
      );
      expect(find.text('Pro'), findsOneWidget);
      store.productsError = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('€3.49 / month'), findsOneWidget);
    });
  });

  group('BillingSection by provider (5.7)', () {
    testWidgets('no subscription: the owner opens the Plans screen', (
      WidgetTester tester,
    ) async {
      final _Setup s = _Setup();
      await tester.pumpWidget(s.wrap(_settingsBody()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('billing-see-plans')));
      await tester.pumpAndSettle();
      expect(find.byType(PlansScreen), findsOneWidget);
    });

    testWidgets('no subscription: a member sees no Plans button', (
      WidgetTester tester,
    ) async {
      final _Setup s = _Setup(role: 'member');
      await tester.pumpWidget(s.wrap(_settingsBody()));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('billing-see-plans')),
        findsNothing,
      );
      expect(
        find.text('Only the organization owner can buy a plan.'),
        findsOneWidget,
      );
    });

    testWidgets('Paddle: managed on the web, with no link', (
      WidgetTester tester,
    ) async {
      final _Setup s = _Setup(
        billing: _billing(provider: 'paddle', plan: 'pro'),
      );
      await tester.pumpWidget(s.wrap(_settingsBody()));
      await tester.pumpAndSettle();
      expect(find.text('Your plan is managed on the web.'), findsOneWidget);
      expect(find.textContaining('https://'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('billing-see-plans')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('delete-apple-subscription')),
        findsNothing,
      );
    });

    testWidgets('Apple: Manage subscription opens the Apple sheet', (
      WidgetTester tester,
    ) async {
      final _Setup s = _Setup(
        billing: _billing(
          provider: 'apple',
          plan: 'pro',
          productId: 'app.uptrack.mobile.pro.monthly',
        ),
      );
      await tester.pumpWidget(s.wrap(_settingsBody()));
      await tester.pumpAndSettle();
      expect(find.text('Managed by the App Store.'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('billing-manage-apple')),
      );
      await tester.pumpAndSettle();
      expect(s.store.manageSheets, 1);
      expect(
        find.byKey(const ValueKey<String>('billing-change-plan')),
        findsOneWidget,
      );
    });

    testWidgets('IAP off: read-only, as in build 1', (
      WidgetTester tester,
    ) async {
      final _Setup s = _Setup(iapEnabled: false);
      await tester.pumpWidget(s.wrap(_settingsBody()));
      await tester.pumpAndSettle();
      expect(find.text('Current plan'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('billing-see-plans')),
        findsNothing,
      );
      expect(find.text('Your plan is managed on the web.'), findsNothing);
    });
  });

  group('DangerZoneSection (5.9, D2)', () {
    testWidgets('Apple subscription: it continues; Manage subscription', (
      WidgetTester tester,
    ) async {
      final _Setup s = _Setup(
        billing: _billing(
          provider: 'apple',
          plan: 'pro',
          productId: 'app.uptrack.mobile.pro.monthly',
        ),
      );
      await tester.pumpWidget(s.wrap(_settingsBody()));
      await tester.pumpAndSettle();
      final Finder text = find.byKey(
        const ValueKey<String>('delete-apple-subscription'),
      );
      await _scrollTo(tester, text);
      expect(
        tester.widget<Text>(text).data,
        contains('continues after you delete your account'),
      );
      final Finder manage = find.byKey(
        const ValueKey<String>('delete-manage-apple'),
      );
      await _scrollTo(tester, manage);
      await tester.tap(manage);
      await tester.pumpAndSettle();
      expect(s.store.manageSheets, 1);
    });

    testWidgets('no "Settings → Billing" text is left', (
      WidgetTester tester,
    ) async {
      final _Setup s = _Setup(billing: _billing(provider: 'paddle'));
      await tester.pumpWidget(s.wrap(_settingsBody()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Settings → Billing'), findsNothing);
    });
  });

  test('plan facts cover every product and the D6 product IDs', () {
    expect(kAppleProductIds, <String>{
      'app.uptrack.mobile.pro.monthly',
      'app.uptrack.mobile.pro.yearly',
      'app.uptrack.mobile.team.monthly',
      'app.uptrack.mobile.team.yearly',
      'app.uptrack.mobile.business.monthly',
      'app.uptrack.mobile.business.yearly',
    });
    for (final PlanFacts p in kPaidPlans) {
      for (final BillingPeriod period in BillingPeriod.values) {
        expect(appleProductFor(p.plan, period).plan, p.plan);
      }
    }
    expect(kPaidPlans.map((PlanFacts p) => p.plan), <String>[
      'pro',
      'team',
      'business',
    ]);
  });
}
