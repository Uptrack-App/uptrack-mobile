import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/database_providers.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/login_screen.dart';
import 'package:uptrack_mobile/features/auth/social_login.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';

/// Fake [HttpClientAdapter] returning canned JSON without network access
/// (same pattern as `test/api/uptrack_api_test.dart`).
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;
  final List<RequestOptions> seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(
  Map<String, Object?> json, [
  int status = 200,
  Map<String, List<String>> extraHeaders = const <String, List<String>>{},
]) {
  return ResponseBody.fromString(
    jsonEncode(json),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      ...extraHeaders,
    },
  );
}

Map<String, Object?> meFixture() => <String, Object?>{
  'user': <String, Object?>{
    'id': '11111111-1111-4111-8111-111111111111',
    'name': 'Ada',
    'email': 'ada@example.com',
    'provider': null,
    'role': 'owner',
    'is_admin': false,
    'preferred_locale': null,
    'inserted_at': '2026-01-01T00:00:00Z',
  },
  'organization': <String, Object?>{
    'id': '22222222-2222-4222-8222-222222222222',
    'name': 'Acme',
    'slug': 'acme',
    'plan': 'free',
  },
};

Map<String, Object?> issuanceFixture() => <String, Object?>{
  'id': '44444444-4444-4444-8444-444444444444',
  'label': null,
  'token': 'udt_test_raw_token',
  'created_at': '2026-01-01T00:00:00',
};

const Map<String, List<String>> sessionCookieHeader = <String, List<String>>{
  'set-cookie': <String>['_uptrack_key=abc123; Path=/; HttpOnly'],
};

void main() {
  group('validators', () {
    test('email', () {
      expect(validateEmail(null), isNotNull);
      expect(validateEmail(''), isNotNull);
      expect(validateEmail('not-an-email'), isNotNull);
      expect(validateEmail('ada@'), isNotNull);
      expect(validateEmail('ada@example.com'), isNull);
    });

    test('password', () {
      expect(validatePassword(null), isNotNull);
      expect(validatePassword(''), isNotNull);
      expect(validatePassword('secret'), isNull);
    });

    test('2FA code', () {
      expect(validateTwoFactorCode(null), isNotNull);
      expect(validateTwoFactorCode('123'), isNotNull);
      expect(validateTwoFactorCode('123456'), isNull);
    });
  });

  group('parseMagicLink', () {
    test(
      'accepts a pasted email link or raw token for the matching account',
      () {
        expect(
          magicLinkInputToken(input: ' raw_token ', email: 'ada@example.com'),
          'raw_token',
        );
        expect(
          magicLinkInputToken(
            input: 'https://uptrack.app/auth/verify-magic-link?email=ada%40example.com&token=abc',
            email: 'Ada@example.com',
          ),
          'abc',
        );
        expect(
          magicLinkInputToken(
            input: 'https://uptrack.app/auth/verify-magic-link?email=other%40example.com&token=abc',
            email: 'ada@example.com',
          ),
          isNull,
        );
        expect(
          magicLinkInputToken(
            input: 'https://uptrack.app/checkout?token=abc',
            email: 'ada@example.com',
          ),
          isNull,
        );
        expect(
          magicLinkInputToken(input: '', email: 'ada@example.com'),
          isNull,
        );
      },
    );
    test('extracts email + token', () {
      final ({String email, String token})? parsed = parseMagicLink(
        Uri.parse('uptrack://auth/magic?email=ada%40example.com&token=abc'),
      );
      expect(parsed?.email, 'ada@example.com');
      expect(parsed?.token, 'abc');
    });

    test('null when params missing', () {
      expect(parseMagicLink(Uri.parse('uptrack://auth/magic')), isNull);
      expect(
        parseMagicLink(Uri.parse('uptrack://auth/magic?email=a%40b.c')),
        isNull,
      );
    });
  });

  group('auth flow (fake adapter)', () {
    late MemoryTokenStore store;
    late AuthTokenHolder holder;
    late FakeAdapter adapter;
    late bool meShould401;
    late ProviderContainer container;

    Future<ResponseBody> handler(RequestOptions options) async {
      final String key = '${options.method} ${options.path}';
      switch (key) {
        case 'POST $kLoginPath':
          return jsonResponse(meFixture(), 200, sessionCookieHeader);
        case 'POST $kDeviceTokensPath':
          return jsonResponse(issuanceFixture(), 201);
        case 'GET $kGetMePath':
          if (meShould401) {
            return jsonResponse(<String, Object?>{
              'error': 'Unauthorized',
            }, 401);
          }
          return jsonResponse(meFixture());
        case 'DELETE $kDeviceTokensPath/44444444-4444-4444-8444-444444444444':
          return jsonResponse(<String, Object?>{'ok': true});
        case 'DELETE $kPushDevicesPath':
          return jsonResponse(<String, Object?>{'ok': true});
        case 'POST $kLogoutPath':
          return jsonResponse(<String, Object?>{});
        default:
          return jsonResponse(<String, Object?>{
            'error': 'unexpected $key',
          }, 500);
      }
    }

    setUp(() {
      meShould401 = false;
      store = MemoryTokenStore();
      holder = AuthTokenHolder();
      adapter = FakeAdapter(handler);
      container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(store),
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
          // R2.4: sign-out wipes the offline cache — back it with an
          // in-memory DB so no host database is touched in tests.
          appDatabaseProvider.overrideWithValue(
            AppDatabase.forTesting(NativeDatabase.memory()),
          ),
        ],
      );
      addTearDown(() {
        container.read(appDatabaseProvider).close();
        container.dispose();
      });
    });

    test(
      'password login exchanges session for a stored device token',
      () async {
        final AuthController controller = container.read(
          authControllerProvider.notifier,
        );

        await controller.signInWithPassword(
          email: 'ada@example.com',
          password: 'secret',
        );

        expect(
          container.read(authControllerProvider).status,
          AuthStatus.signedIn,
        );
        expect(await store.readDeviceToken(), 'udt_test_raw_token');
        expect(holder.token, 'udt_test_raw_token');

        // Bearer interceptor attaches the stored device token afterwards.
        await container.read(uptrackApiProvider).getMe();
        final RequestOptions meCall = adapter.seen.lastWhere(
          (RequestOptions o) => o.path == kGetMePath,
        );
        expect(meCall.headers['Authorization'], 'Bearer udt_test_raw_token');
      },
    );

    test('totp_required moves to the 2FA step, code completes login', () async {
      final FakeAdapter totpAdapter = FakeAdapter((
        RequestOptions options,
      ) async {
        if (options.method == 'POST' && options.path == kLoginPath) {
          final Object? data = options.data;
          final bool hasCode =
              data is Map && (data['totp_code'] as String?) == '123456';
          if (!hasCode) {
            return jsonResponse(<String, Object?>{'totp_required': true});
          }
          return jsonResponse(meFixture(), 200, sessionCookieHeader);
        }
        return handler(options);
      });
      final ProviderContainer totpContainer = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(store),
          authTokenHolderProvider.overrideWithValue(holder),
          dioProvider.overrideWithValue(
            buildAppDio(
              holder: holder,
              onUnauthorized: () {},
              adapter: totpAdapter,
            ),
          ),
        ],
      );
      addTearDown(totpContainer.dispose);

      final AuthController controller = totpContainer.read(
        authControllerProvider.notifier,
      );
      await controller.signInWithPassword(
        email: 'ada@example.com',
        password: 'secret',
      );
      expect(
        totpContainer.read(authControllerProvider).status,
        AuthStatus.needsTwoFactor,
      );

      await controller.submitTwoFactorCode('123456');
      expect(
        totpContainer.read(authControllerProvider).status,
        AuthStatus.signedIn,
      );
      expect(await store.readDeviceToken(), 'udt_test_raw_token');
    });

    test('401 while signed in signs out (re-auth)', () async {
      final AuthController controller = container.read(
        authControllerProvider.notifier,
      );
      await controller.signInWithPassword(
        email: 'ada@example.com',
        password: 'secret',
      );
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedIn,
      );

      meShould401 = true;
      await expectLater(
        container.read(uptrackApiProvider).getMe(),
        throwsA(isA<DioException>()),
      );

      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedOut,
      );
      expect(
        container.read(authControllerProvider).errorMessage,
        contains('Session expired'),
      );
      expect(holder.token, isNull);
      expect(await store.readDeviceToken(), isNull);
    });

    test(
      'magic-link 2FA does not issue a device token until the code is verified',
      () async {
        final FakeAdapter magicAdapter = FakeAdapter((
          RequestOptions options,
        ) async {
          if (options.path == kMagicLinkVerifyPath) {
            final data = options.data as Map<String, Object?>;
            expect(data['token'], 'magic_token');
            if (data['totp_code'] != '123456') {
              return jsonResponse(<String, Object?>{'totp_required': true});
            }
            return jsonResponse(meFixture(), 200, sessionCookieHeader);
          }
          return handler(options);
        });
        final ProviderContainer magicContainer = ProviderContainer(
          overrides: [
            tokenStoreProvider.overrideWithValue(store),
            authTokenHolderProvider.overrideWithValue(holder),
            uptrackApiProvider.overrideWithValue(
              UptrackApi(
                dio: buildAppDio(
                  holder: holder,
                  onUnauthorized: () {},
                  adapter: magicAdapter,
                ),
              ),
            ),
          ],
        );
        addTearDown(magicContainer.dispose);
        final AuthController controller = magicContainer.read(
          authControllerProvider.notifier,
        );
        await controller.verifyMagicLink(
          email: 'ada@example.com',
          token: 'magic_token',
        );
        expect(
          magicContainer.read(authControllerProvider).status,
          AuthStatus.needsTwoFactor,
        );
        expect(await store.readDeviceToken(), isNull);
        expect(
          magicAdapter.seen.any(
            (RequestOptions request) => request.path == kDeviceTokensPath,
          ),
          isFalse,
        );
        await controller.submitTwoFactorCode('000000');
        expect(
          magicContainer.read(authControllerProvider).status,
          AuthStatus.needsTwoFactor,
        );
        expect(await store.readDeviceToken(), isNull);
        await controller.submitTwoFactorCode('123456');
        expect(
          magicContainer.read(authControllerProvider).status,
          AuthStatus.signedIn,
        );
        expect(await store.readDeviceToken(), 'udt_test_raw_token');
      },
    );

    test(
      'canceling magic-link 2FA discards the pending sign-in credential',
      () async {
        final FakeAdapter magicAdapter = FakeAdapter(
          (RequestOptions options) async =>
              jsonResponse(<String, Object?>{'totp_required': true}),
        );
        final ProviderContainer magicContainer = ProviderContainer(
          overrides: [
            tokenStoreProvider.overrideWithValue(store),
            authTokenHolderProvider.overrideWithValue(holder),
            uptrackApiProvider.overrideWithValue(
              UptrackApi(
                dio: buildAppDio(
                  holder: holder,
                  onUnauthorized: () {},
                  adapter: magicAdapter,
                ),
              ),
            ),
          ],
        );
        addTearDown(magicContainer.dispose);
        final AuthController controller = magicContainer.read(
          authControllerProvider.notifier,
        );
        await controller.verifyMagicLink(
          email: 'ada@example.com',
          token: 'magic_token',
        );
        controller.cancelTwoFactor();
        await controller.submitTwoFactorCode('123456');
        expect(magicAdapter.seen, hasLength(1));
        expect(
          magicContainer.read(authControllerProvider).status,
          AuthStatus.signedOut,
        );
        expect(await store.readDeviceToken(), isNull);
      },
    );

    test('failed login keeps the field-level error (no 401 loop)', () async {
      final FakeAdapter badCreds = FakeAdapter((RequestOptions options) async {
        return jsonResponse(<String, Object?>{
          'error': 'Invalid email or password',
        }, 401);
      });
      ProviderContainer? badRef;
      final AuthTokenHolder badHolder = AuthTokenHolder();
      final ProviderContainer badContainer = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
          authTokenHolderProvider.overrideWithValue(badHolder),
          dioProvider.overrideWithValue(
            buildAppDio(
              holder: badHolder,
              onUnauthorized: () => badRef
                  ?.read(authControllerProvider.notifier)
                  .handleUnauthorized(),
              adapter: badCreds,
            ),
          ),
        ],
      );
      badRef = badContainer;
      addTearDown(badContainer.dispose);

      await badContainer
          .read(authControllerProvider.notifier)
          .signInWithPassword(email: 'ada@example.com', password: 'wrong');

      final AuthState state = badContainer.read(authControllerProvider);
      expect(state.status, AuthStatus.signedOut);
      expect(state.errorMessage, 'Invalid email or password');
    });

    test(
      'sign-out revokes device token, unregisters push, clears local',
      () async {
        final AuthController controller = container.read(
          authControllerProvider.notifier,
        );
        await controller.signInWithPassword(
          email: 'ada@example.com',
          password: 'secret',
        );
        expect(
          container.read(authControllerProvider).status,
          AuthStatus.signedIn,
        );

        await controller.signOut(pushToken: 'fcm-token-1');

        expect(
          container.read(authControllerProvider).status,
          AuthStatus.signedOut,
        );
        expect(await store.readDeviceToken(), isNull);
        expect(holder.token, isNull);
        final Set<String> calls = adapter.seen
            .map((RequestOptions o) => '${o.method} ${o.path}')
            .toSet();
        expect(
          calls,
          contains(
            'DELETE $kDeviceTokensPath/44444444-4444-4444-8444-444444444444',
          ),
        );
        expect(calls, contains('DELETE $kPushDevicesPath'));
        expect(calls, contains('POST $kLogoutPath'));
      },
    );
  });

  group('LoginScreen widget', () {
    testWidgets(
      'a passwordless web customer can paste the emailed link after returning from checkout',
      (WidgetTester tester) async {
        String? verifiedToken;
        final MemoryTokenStore store = MemoryTokenStore();
        final AuthTokenHolder holder = AuthTokenHolder();
        final FakeAdapter adapter = FakeAdapter((RequestOptions options) async {
          if (options.path == kMagicLinkPath) {
            expect(options.data, {
              'email': 'ada@example.com',
              'client': 'mobile',
            });
            return jsonResponse(<String, Object?>{'ok': true});
          }
          if (options.path == kMagicLinkVerifyPath) {
            final data = options.data as Map<String, Object?>;
            verifiedToken = data['token'] as String?;
            return jsonResponse(meFixture(), 200, sessionCookieHeader);
          }
          if (options.path == kDeviceTokensPath) {
            return jsonResponse(issuanceFixture(), 201);
          }
          return jsonResponse(meFixture());
        });
        final ProviderContainer container = ProviderContainer(
          overrides: [
            tokenStoreProvider.overrideWithValue(store),
            authTokenHolderProvider.overrideWithValue(holder),
            uptrackApiProvider.overrideWithValue(
              UptrackApi(
                dio: buildAppDio(
                  holder: holder,
                  onUnauthorized: () {},
                  adapter: adapter,
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: LoginScreen(returnLocation: '/billing/return?plan=pro'),
            ),
          ),
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'),
          'ada@example.com',
        );
        await tester.tap(find.text('Email me a sign-in link'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Sign-in link or code'),
          'https://uptrack.app/auth/verify-magic-link?email=ada%40example.com&token=abc',
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Sign in'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();
        expect(verifiedToken, 'abc');
        expect(
          container.read(authControllerProvider).status,
          AuthStatus.signedIn,
        );
        expect(await store.readDeviceToken(), 'udt_test_raw_token');
      },
    );
    testWidgets('empty submit shows validation errors', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
            socialProvidersProvider.overrideWith((ref) async => <String>{}),
            uptrackApiProvider.overrideWithValue(
              UptrackApi(dio: Dio(BaseOptions(baseUrl: 'http://localhost'))),
            ),
          ],
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

      await tester.ensureVisible(find.text('Email me a sign-in link'));
      await tester.tap(find.text('Email me a sign-in link'));
      await tester.pump();

      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsNothing);
    });

    testWidgets('valid submit signs in via the fake API', (
      WidgetTester tester,
    ) async {
      final MemoryTokenStore store = MemoryTokenStore();
      final AuthTokenHolder testHolder = AuthTokenHolder();
      final FakeAdapter testAdapter = FakeAdapter((
        RequestOptions options,
      ) async {
        if (options.method == 'POST' && options.path == kMagicLinkVerifyPath) {
          return jsonResponse(meFixture(), 200, sessionCookieHeader);
        }
        if (options.method == 'POST' && options.path == kDeviceTokensPath) {
          return jsonResponse(issuanceFixture(), 201);
        }
        return jsonResponse(meFixture());
      });
      final ProviderContainer testContainer = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(store),
          authTokenHolderProvider.overrideWithValue(testHolder),
          uptrackApiProvider.overrideWithValue(
            UptrackApi(
              dio: buildAppDio(
                holder: testHolder,
                onUnauthorized: () {},
                adapter: testAdapter,
              ),
            ),
          ),
        ],
      );
      addTearDown(testContainer.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: testContainer,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'ada@example.com',
      );
      await tester.tap(find.text('Email me a sign-in link'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Sign-in link or code'),
        'abc',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sign in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(
        testContainer.read(authControllerProvider).status,
        AuthStatus.signedIn,
      );
      expect(await store.readDeviceToken(), 'udt_test_raw_token');
    });
  });
}
