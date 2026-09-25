import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/billing_subscription.dart';
import 'package:uptrack_mobile/api/models/notification_preferences.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/features/settings/settings_screen.dart';

/// Fake [HttpClientAdapter] returning canned JSON without network access
/// (same pattern as `test/api/uptrack_api_test.dart`).
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this._handler);

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

ResponseBody jsonResponse(Map<String, Object?> json, [int status = 200]) {
  return ResponseBody.fromString(
    jsonEncode(json),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );
}

Map<String, Object?> meFixture() => <String, Object?>{
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
};

Map<String, Object?> prefsFixture() => <String, Object?>{
  'user_id': 'u1',
  'severity_overrides': <String, Object?>{'info': 'active'},
  'quiet_hours_start': '22:00:00',
  'quiet_hours_end': '07:00:00',
  'mobile_push_enabled': true,
  'digest_p3': false,
};

Map<String, Object?> billingFixture() => <String, Object?>{
  'data': <String, Object?>{
    'id': 's1',
    'plan': 'pro',
    'status': 'active',
    'current_period_start': '2026-09-01T00:00:00Z',
    'current_period_end': '2026-10-01T00:00:00Z',
    'cancelled_at': null,
  },
  'plan': 'pro',
};

Dio dioWithFake(Future<ResponseBody> Function(RequestOptions) handler) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:4000'));
  dio.httpClientAdapter = FakeAdapter(handler);
  return dio;
}

void main() {
  group('UptrackApi prefs + billing', () {
    test('getNotificationPreferences parses the row shape', () async {
      final Dio dio = dioWithFake(
        (RequestOptions options) async => jsonResponse(prefsFixture()),
      );

      final NotificationPreferences prefs = await UptrackApi(dio: dio)
          .getNotificationPreferences();

      expect(prefs.severityOverrides, <String, String>{'info': 'active'});
      expect(prefs.quietHoursStart, '22:00:00');
      expect(prefs.digestP3, isFalse);
    });

    test('updateNotificationPreferences PATCHes the merge body', () async {
      RequestOptions? seen;
      Map<String, dynamic>? sentBody;
      final Dio dio = dioWithFake((RequestOptions options) async {
        seen = options;
        final Object? data = options.data;
        if (data is Map<String, dynamic>) {
          sentBody = data;
        }
        return jsonResponse(prefsFixture());
      });

      final Map<String, Object?> patch = <String, Object?>{
        'severity_overrides': <String, String>{},
        'quiet_hours_start': null,
        'quiet_hours_end': null,
        'mobile_push_enabled': false,
        'digest_p3': true,
      };
      final NotificationPreferences updated = await UptrackApi(dio: dio)
          .updateNotificationPreferences(patch);

      expect(seen?.method, 'PATCH');
      expect(seen?.path, kNotificationPreferencesPath);
      expect(sentBody?['mobile_push_enabled'], isFalse);
      expect(updated.mobilePushEnabled, isTrue);
    });

    test('getBillingSubscription parses plan + subscription', () async {
      final Dio dio = dioWithFake(
        (RequestOptions options) async => jsonResponse(billingFixture()),
      );

      final BillingSubscriptionInfo info = await UptrackApi(dio: dio)
          .getBillingSubscription();

      expect(info.plan, 'pro');
      expect(info.subscription?.status, 'active');
      expect(info.subscription?.currentPeriodEnd, '2026-10-01T00:00:00Z');
    });

    test('billing parses a null subscription (plan-only orgs)', () async {
      final Dio dio = dioWithFake(
        (RequestOptions options) async =>
            jsonResponse(<String, Object?>{'data': null, 'plan': 'free'}),
      );

      final BillingSubscriptionInfo info = await UptrackApi(dio: dio)
          .getBillingSubscription();

      expect(info.plan, 'free');
      expect(info.subscription, isNull);
    });
  });

  group('SettingsScreen new sections', () {
    ProviderContainer makeContainer(
      Future<ResponseBody> Function(RequestOptions) handler,
    ) {
      final AuthTokenHolder holder = AuthTokenHolder()..token = 'udt_test';
      final ProviderContainer container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
          authTokenHolderProvider.overrideWithValue(holder),
          dioProvider.overrideWithValue(
            buildAppDio(
              holder: holder,
              onUnauthorized: () {},
              adapter: FakeAdapter(handler),
            ),
          ),
        ],
      );
      return container;
    }

    Future<ResponseBody> fullHandler(RequestOptions options) async {
      final String path = options.path;
      if (path == kGetMePath) {
        return jsonResponse(meFixture());
      }
      if (path == kNotificationPreferencesPath) {
        if (options.method == 'PATCH') {
          return jsonResponse(prefsFixture());
        }
        return jsonResponse(prefsFixture());
      }
      if (path == kBillingSubscriptionPath) {
        return jsonResponse(billingFixture());
      }
      if (path == kDeviceTokensPath) {
        return jsonResponse(<String, Object?>{'data': <Object?>[]});
      }
      return jsonResponse(<String, Object?>{'ok': true});
    }

    Future<void> pumpSettings(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Later settings sections are lazily built — drag the outer list
    /// until [finder] is hit-testable before asserting or tapping
    /// (presence alone is not enough: the list builds ahead into its
    /// cache extent). A plain `scrollUntilVisible` cannot pin the outer
    /// [Scrollable]: the quiet-hours text fields each contain their own
    /// inner scrollable.
    Future<void> scrollTo(WidgetTester tester, Finder finder) async {
      final Finder list = find.byKey(const ValueKey<String>('settings-list'));
      for (int i = 0; i < 15 && finder.hitTestable().evaluate().isEmpty; i++) {
        await tester.drag(list, const Offset(0, -500));
        await tester.pumpAndSettle();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('profile shows user, org, and plan', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = makeContainer(fullHandler);
      addTearDown(container.dispose);

      await pumpSettings(tester, container);

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('ada@example.com'), findsOneWidget);
      expect(find.text('Acme'), findsOneWidget);
    });

    testWidgets('billing shows plan + subscription state', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = makeContainer(fullHandler);
      addTearDown(container.dispose);

      await pumpSettings(tester, container);

      await scrollTo(tester, find.text('Billing'));
      expect(find.text('Billing'), findsOneWidget);
      expect(find.text('Current plan'), findsOneWidget);
      expect(find.text('Subscription active'), findsOneWidget);
    });

    testWidgets('prefs load, toggle off push, and save via PATCH', (
      WidgetTester tester,
    ) async {
      final List<RequestOptions> seen = <RequestOptions>[];
      final ProviderContainer container = makeContainer((
        RequestOptions options,
      ) async {
        seen.add(options);
        return fullHandler(options);
      });
      addTearDown(container.dispose);

      await pumpSettings(tester, container);

      await scrollTo(tester, find.text('Notifications'));
      expect(find.text('Notifications'), findsOneWidget);
      // Stored override renders without the "(default)" marker.
      expect(find.text('info'), findsOneWidget);

      final SwitchListTile pushSwitch = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey<String>('prefs-mobile-push')),
      );
      expect(pushSwitch.value, isTrue);

      await scrollTo(
        tester,
        find.byKey(const ValueKey<String>('prefs-mobile-push')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('prefs-mobile-push')));
      await tester.pumpAndSettle();

      await scrollTo(tester, find.byKey(const ValueKey<String>('prefs-save')));
      await tester.tap(find.byKey(const ValueKey<String>('prefs-save')));
      await tester.pumpAndSettle();

      final List<RequestOptions> patches = seen
          .where((RequestOptions o) => o.method == 'PATCH')
          .toList();
      expect(patches, hasLength(1));
      expect(patches.single.path, kNotificationPreferencesPath);
      final Object? data = patches.single.data;
      expect(data, isA<Map<String, Object?>>());
      expect((data! as Map<String, Object?>)['mobile_push_enabled'], isFalse);
      await scrollTo(tester, find.text('Preferences saved.'));
      expect(find.text('Preferences saved.'), findsOneWidget);
    });

    testWidgets('invalid quiet-hours blocks the save with a message', (
      WidgetTester tester,
    ) async {
      final List<RequestOptions> seen = <RequestOptions>[];
      final ProviderContainer container = makeContainer((
        RequestOptions options,
      ) async {
        seen.add(options);
        return fullHandler(options);
      });
      addTearDown(container.dispose);

      await pumpSettings(tester, container);

      await scrollTo(
        tester,
        find.byKey(const ValueKey<String>('prefs-quiet-start')),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('prefs-quiet-start')),
        '25:00',
      );
      await scrollTo(tester, find.byKey(const ValueKey<String>('prefs-save')));
      await tester.tap(find.byKey(const ValueKey<String>('prefs-save')));
      await tester.pumpAndSettle();

      await scrollTo(
        tester,
        find.text('Quiet-hours start must be HH:MM (24-hour).'),
      );
      expect(
        find.text('Quiet-hours start must be HH:MM (24-hour).'),
        findsOneWidget,
      );
      expect(seen.where((RequestOptions o) => o.method == 'PATCH'), isEmpty);
    });
  });
}
