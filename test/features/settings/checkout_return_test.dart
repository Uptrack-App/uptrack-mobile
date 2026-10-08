import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uptrack_mobile/api/models/billing_subscription.dart';
import 'package:uptrack_mobile/api/models/current_user.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/app.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/features/settings/checkout_return_screen.dart';

class _Api extends UptrackApi {
  _Api() : super(dio: Dio());

  String plan = 'free';
  String status = 'active';
  bool featuresEnabled = false;
  bool fail = false;
  int billingReads = 0;

  @override
  Future<CurrentUserResponse> getMe() async {
    if (fail) throw Exception('offline');
    return CurrentUserResponse(
      user: const AuthUser(
        id: 'user',
        name: 'Ada',
        email: 'ada@example.com',
        role: 'owner',
        isAdmin: false,
        insertedAt: '2026-01-01T00:00:00Z',
      ),
      organization: AuthOrganization(
        id: 'org',
        name: 'Acme',
        slug: 'acme',
        plan: plan,
        featuresEnabled: featuresEnabled,
      ),
    );
  }

  @override
  Future<BillingSubscriptionInfo> getBillingSubscription() async {
    billingReads += 1;
    return BillingSubscriptionInfo(
      plan: plan,
      subscription: plan == 'free'
          ? null
          : BillingSubscription(id: 'sub', plan: plan, status: status),
    );
  }
}

void main() {
  testWidgets(
    'checkout return stays usable on a small screen with large text',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [uptrackApiProvider.overrideWithValue(_Api())],
          child: MaterialApp(
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const CheckoutReturnScreen(expectedPlan: 'pro'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(find.text('Check again').hitTestable(), findsOneWidget);
    },
  );
  test('checkout return is a fixed internal destination without secrets', () {
    expect(
      checkoutReturnLocation(
        Uri.parse('uptrack://app/billing/return?plan=pro&token=untrusted'),
      ),
      '/billing/return?plan=pro',
    );
    expect(
      checkoutReturnLocation(Uri.parse('/billing/return?plan=invalid')),
      '/billing/return',
    );
    expect(checkoutReturnLocation(Uri.parse('/monitors')), isNull);
  });

  testWidgets(
    'a forged return cannot activate access; a later server update can be rechecked',
    (WidgetTester tester) async {
      final _Api api = _Api();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [uptrackApiProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: CheckoutReturnScreen(expectedPlan: 'pro'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your subscription is not active yet'), findsOneWidget);
      expect(find.text('Continue to dashboard'), findsNothing);
      expect(find.text('Signed in as ada@example.com'), findsOneWidget);

      api.plan = 'pro';
      api.featuresEnabled = true;
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(api.billingReads, 2);
      expect(find.text('Your Pro plan is ready'), findsOneWidget);
      expect(find.text('Continue to dashboard'), findsOneWidget);
    },
  );

  testWidgets('does not confirm a different tier or past-due subscription', (
    WidgetTester tester,
  ) async {
    final _Api api = _Api()
      ..plan = 'team'
      ..featuresEnabled = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [uptrackApiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: CheckoutReturnScreen(expectedPlan: 'pro'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your subscription is not active yet'), findsOneWidget);

    api.plan = 'pro';
    api.status = 'past_due';
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(find.text('Your subscription is not active yet'), findsOneWidget);
    expect(find.text('Continue to dashboard'), findsNothing);
  });

  testWidgets('connection failures offer retry without claiming activation', (
    WidgetTester tester,
  ) async {
    final _Api api = _Api()..fail = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [uptrackApiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: CheckoutReturnScreen(expectedPlan: 'pro'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    api.fail = false;
    api.plan = 'pro';
    api.featuresEnabled = true;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Your Pro plan is ready'), findsOneWidget);
  });

  testWidgets('with the billing link off, a checkout link resolves to the home screen', (
    WidgetTester tester,
  ) async {
    final GoRouter router = createRouter(authStatusOf: () => AuthStatus.signedIn);
    addTearDown(router.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (BuildContext c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    // Ask the router where the link leads without building any screen.
    for (final String link in <String>[
      'uptrack://app/billing/return?plan=pro',
      '/billing/return',
    ]) {
      final matches = await router.routeInformationParser
          .parseRouteInformationWithDependencies(
            RouteInformation(uri: Uri.parse(link)),
            context,
          );
      expect(matches.uri.path, '/', reason: link);
    }
  });

  testWidgets('preserves the checkout return through first-app sign-in', (
    WidgetTester tester,
  ) async {
    final _Api api = _Api()
      ..plan = 'pro'
      ..featuresEnabled = true;
    AuthStatus status = AuthStatus.signedOut;
    final ValueNotifier<int> refresh = ValueNotifier<int>(0);
    final GoRouter router = createRouter(
      checkoutReturnEnabled: true,
      initialLocation: 'uptrack://app/billing/return?plan=pro',
      authStatusOf: () => status,
      refreshListenable: refresh,
    );
    addTearDown(() {
      router.dispose();
      refresh.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uptrackApiProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(find.text('Email me a sign-in link'), findsOneWidget);
    expect(
      find.textContaining('same account you used in the browser'),
      findsOneWidget,
    );
    status = AuthStatus.signedIn;
    refresh.value += 1;
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/billing/return');
    expect(find.text('Your Pro plan is ready'), findsOneWidget);
  });

  testWidgets(
    'restoring a device token keeps the same router and pending return',
    (WidgetTester tester) async {
      final _Api api = _Api()
        ..plan = 'pro'
        ..featuresEnabled = true;
      final MemoryTokenStore store = MemoryTokenStore();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          checkoutReturnEnabledProvider.overrideWithValue(true),
          uptrackApiProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      final GoRouter router = container.read(routerProvider);
      router.go('/billing/return?plan=pro');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await store.writeDeviceToken(token: 'udt_test', id: 'device');
      await container.read(authControllerProvider.notifier).restore();
      await tester.pumpAndSettle();
      expect(identical(container.read(routerProvider), router), isTrue);
      expect(router.routeInformationProvider.value.uri.path, '/billing/return');
      expect(find.text('Your Pro plan is ready'), findsOneWidget);
    },
  );
}
