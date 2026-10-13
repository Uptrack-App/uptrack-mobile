import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/billing_subscription.dart';
import 'package:uptrack_mobile/api/models/notification_preferences.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/database_providers.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/features/settings/settings_screen.dart';
import 'package:uptrack_mobile/push/live_activity_support.dart';

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
      Future<ResponseBody> Function(RequestOptions) handler, {
      String? osVersion,
    }) {
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
          if (osVersion != null) osVersionProvider.overrideWithValue(osVersion),
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

    group('Live Activity hint (D9)', () {
      Future<void> pumpWithOs(
        WidgetTester tester, {
        required TargetPlatform platform,
        required String osVersion,
      }) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final ProviderContainer container = makeContainer(
            fullHandler,
            osVersion: osVersion,
          );
          addTearDown(container.dispose);
          await pumpSettings(tester, container);
          await scrollTo(
            tester,
            find.byKey(const ValueKey<String>('prefs-mobile-push')),
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }

      const ValueKey<String> hintKey = ValueKey<String>(
        'prefs-live-activity-hint',
      );

      testWidgets('iOS 16.1 to 17.1 sees the app-open hint', (
        WidgetTester tester,
      ) async {
        await pumpWithOs(
          tester,
          platform: TargetPlatform.iOS,
          osVersion: 'Version 16.4 (Build 20E247)',
        );
        expect(find.byKey(hintKey), findsOneWidget);
        expect(
          find.textContaining('starts only while Uptrack is open'),
          findsOneWidget,
        );
      });

      testWidgets('iOS 16.0 sees the no-Live-Activity hint', (
        WidgetTester tester,
      ) async {
        await pumpWithOs(
          tester,
          platform: TargetPlatform.iOS,
          osVersion: 'Version 16.0 (Build 20A362)',
        );
        expect(find.byKey(hintKey), findsOneWidget);
        expect(
          find.textContaining('Live Activities need iOS 16.1'),
          findsOneWidget,
        );
      });

      testWidgets('iOS 17.2 and later sees no hint', (
        WidgetTester tester,
      ) async {
        await pumpWithOs(
          tester,
          platform: TargetPlatform.iOS,
          osVersion: 'Version 17.2 (Build 21C62)',
        );
        expect(find.byKey(hintKey), findsNothing);
      });

      testWidgets('Android sees no hint whatever the version text says', (
        WidgetTester tester,
      ) async {
        await pumpWithOs(
          tester,
          platform: TargetPlatform.android,
          osVersion: 'Version 16.0',
        );
        expect(find.byKey(hintKey), findsNothing);
      });
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

    group('DangerZoneSection (R2.6)', () {
      ProviderContainer dangerContainer(
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
            appDatabaseProvider.overrideWithValue(
              AppDatabase.forTesting(NativeDatabase.memory()),
            ),
          ],
        );
        addTearDown(() {
          container.read(appDatabaseProvider).close();
          container.dispose();
        });
        return container;
      }

      Future<ResponseBody> dangerHandler(
        RequestOptions options, {
        int deleteStatus = 200,
        Map<String, Object?>? deleteBody,
      }) async {
        final String path = options.path;
        if (path == kGetMePath) return jsonResponse(meFixture());
        if (path == kNotificationPreferencesPath) {
          return jsonResponse(prefsFixture());
        }
        if (path == kBillingSubscriptionPath) {
          return jsonResponse(billingFixture());
        }
        if (path == kDeviceTokensPath) {
          return jsonResponse(<String, Object?>{'data': <Object?>[]});
        }
        if (path == kDeleteAccountPath) {
          return jsonResponse(
            deleteBody ?? <String, Object?>{'ok': true},
            deleteStatus,
          );
        }
        return jsonResponse(<String, Object?>{'ok': true});
      }

      Future<void> openDanger(
        WidgetTester tester,
        ProviderContainer container,
      ) async {
        await pumpSettings(tester, container);
        await scrollTo(tester, find.text('Danger zone'));
        // The confirm checkbox and delete button sit below the title; bring
        // the whole section into view so taps hit-test.
        await scrollTo(
          tester,
          find.byKey(const ValueKey<String>('delete-account')),
        );
      }

      testWidgets('delete stays disabled until confirmed', (
        WidgetTester tester,
      ) async {
        final ProviderContainer container = dangerContainer(dangerHandler);
        await openDanger(tester, container);

        final Finder button = find.byKey(
          const ValueKey<String>('delete-account'),
        );
        expect(
          tester
              .widget<FilledButton>(
                find.descendant(
                  of: button,
                  matching: find.byType(FilledButton),
                ),
              )
              .enabled,
          isFalse,
        );

        await tester.tap(find.byKey(const ValueKey<String>('delete-confirm')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.descendant(
                  of: button,
                  matching: find.byType(FilledButton),
                ),
              )
              .enabled,
          isTrue,
        );
      });

      testWidgets('live subscription surfaces the server message', (
        WidgetTester tester,
      ) async {
        final List<RequestOptions> seen = <RequestOptions>[];
        final ProviderContainer container = dangerContainer((
          RequestOptions options,
        ) async {
          seen.add(options);
          return dangerHandler(
            options,
            deleteStatus: 409,
            deleteBody: <String, Object?>{'error': 'Cancel first.'},
          );
        });
        await openDanger(tester, container);

        await tester.tap(find.byKey(const ValueKey<String>('delete-confirm')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('delete-account')));
        await tester.pumpAndSettle();

        expect(find.text('Cancel first.'), findsOneWidget);
        expect(
          seen.where(
            (RequestOptions o) =>
                o.path == kDeleteAccountPath && o.method == 'POST',
          ),
          hasLength(1),
        );
      });

      testWidgets('wrong password maps to 422 copy', (
        WidgetTester tester,
      ) async {
        final ProviderContainer container = dangerContainer((
          RequestOptions options,
        ) async {
          return dangerHandler(
            options,
            deleteStatus: 422,
            deleteBody: <String, Object?>{'error': 'Password is incorrect'},
          );
        });
        await openDanger(tester, container);

        await tester.enterText(
          find.byKey(const ValueKey<String>('delete-password')),
          'wrong',
        );
        await tester.tap(find.byKey(const ValueKey<String>('delete-confirm')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('delete-account')));
        await tester.pumpAndSettle();

        expect(
          find.text('That password is incorrect. Try again.'),
          findsOneWidget,
        );
      });

      // D11: a device token deletes only within 15 minutes of a sign-in.
      testWidgets('an old sign-in asks the user to sign in again', (
        WidgetTester tester,
      ) async {
        final ProviderContainer container = dangerContainer((
          RequestOptions options,
        ) async {
          return dangerHandler(
            options,
            deleteStatus: 403,
            deleteBody: <String, Object?>{
              'error': 'Sign in again to delete your account.',
              'code': 'reauth_required',
            },
          );
        });
        await openDanger(tester, container);

        await tester.tap(find.byKey(const ValueKey<String>('delete-confirm')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('delete-account')));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'For your safety, sign in again. Then delete your account within 15 minutes.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Only the organization owner can delete the account.'),
          findsNothing,
        );
        final Finder reauth = find.byKey(
          const ValueKey<String>('delete-reauth'),
        );
        await scrollTo(tester, reauth);
        await tester.tap(reauth);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          container.read(authControllerProvider).status,
          AuthStatus.signedOut,
        );
      });

      testWidgets('a 403 without a code is still the owner-only copy', (
        WidgetTester tester,
      ) async {
        final ProviderContainer container = dangerContainer((
          RequestOptions options,
        ) async {
          return dangerHandler(
            options,
            deleteStatus: 403,
            deleteBody: <String, Object?>{},
          );
        });
        await openDanger(tester, container);

        await tester.tap(find.byKey(const ValueKey<String>('delete-confirm')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('delete-account')));
        await tester.pumpAndSettle();

        expect(
          find.text('Only the organization owner can delete the account.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('delete-reauth')),
          findsNothing,
        );
      });

      testWidgets('success posts and signs out', (WidgetTester tester) async {
        final List<RequestOptions> seen = <RequestOptions>[];
        final ProviderContainer container = dangerContainer((
          RequestOptions options,
        ) async {
          seen.add(options);
          return dangerHandler(options);
        });
        await openDanger(tester, container);

        await tester.tap(find.byKey(const ValueKey<String>('delete-confirm')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('delete-account')));
        // Success leaves the busy spinner mounted (the real app navigates away
        // on sign-out), so settle is impossible: bounded pumps flush the async
        // sign-out chain instead.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          seen.any(
            (RequestOptions o) =>
                o.path == kDeleteAccountPath && o.method == 'POST',
          ),
          isTrue,
        );
        expect(
          container.read(authControllerProvider).status,
          AuthStatus.signedOut,
        );
        expect(
          find.byKey(const ValueKey<String>('delete-error')),
          findsNothing,
        );
      });
    });
  });
}
