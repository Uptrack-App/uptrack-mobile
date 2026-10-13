import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/login_screen.dart';
import 'package:uptrack_mobile/features/auth/social_login.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';

import 'auth_test.dart' show FakeAdapter, jsonResponse, issuanceFixture;

class FakeBrowser implements SocialBrowser {
  FakeBrowser(this.handler);
  final Future<Uri> Function(Uri) handler;
  int calls = 0;
  @override
  Future<Uri> authenticate(Uri url) {
    calls++;
    return handler(url);
  }
}

Uri callbackFor(Uri start, {String? state, String? error}) => Uri(
  scheme: socialCallbackScheme,
  host: 'callback',
  queryParameters: <String, String>{
    'state': state ?? start.queryParameters['mobile_state']!,
    if (error != null) 'error': error else 'code': 'one_time_test_code',
  },
);

void main() {
  test(
    'PKCE vector; callback rejects wrong state, route, duplicates and errors',
    () {
      final request = SocialLoginRequest(
        state: 'state',
        verifier: 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
      );
      expect(request.challenge, 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
      expect(
        request
            .parseCallback(
              Uri.parse(
                '$socialCallbackScheme://callback?state=state&code=abc',
              ),
            )
            .code,
        'abc',
      );
      for (final url in <String>[
        '$socialCallbackScheme://callback?state=other&code=abc',
        '$socialCallbackScheme://other?state=state&code=abc',
        '$socialCallbackScheme://callback/path?state=state&code=abc',
        '$socialCallbackScheme://callback?state=state&state=state&code=abc',
        '$socialCallbackScheme://callback?state=state&code=abc&code=def',
        '$socialCallbackScheme://callback?state=state&error=auth_failed',
        '$socialCallbackScheme://callback?state=state&code=',
        '$socialCallbackScheme://callback?state=state&code=abc#fragment',
        '$socialCallbackScheme://callback?state=state&code=abc&token=untrusted',
      ]) {
        expect(
          () => request.parseCallback(Uri.parse(url)),
          throwsFormatException,
        );
      }
      final a = SocialLoginRequest.create();
      final b = SocialLoginRequest.create();
      expect(a.state.length, 43);
      expect(a.verifier.length, 43);
      expect(a.state, isNot(a.verifier));
      expect(a.state, isNot(b.state));
    },
  );

  test('browser URL uses same API and rejects nonlocal cleartext and unknown provider', () {
    final api = UptrackApi(
      dio: Dio(BaseOptions(baseUrl: 'https://api.uptrack.app')),
    );
    expect(
      api.socialLoginUrl('google', 'state', 'challenge').path,
      '/auth/google',
    );
    expect(
      api
          .socialLoginUrl('github', 'state', 'challenge')
          .queryParameters['code_challenge_method'],
      'S256',
    );
    expect(
      () => api.socialLoginUrl('other', 'state', 'challenge'),
      throwsArgumentError,
    );
    expect(
      () =>
          UptrackApi(dio: Dio(BaseOptions(baseUrl: 'http://api.uptrack.app')))
              .socialLoginUrl('google', 'state', 'challenge'),
      throwsFormatException,
    );
  });

  group('social controller', () {
    late MemoryTokenStore store;
    late ProviderContainer container;
    late FakeAdapter adapter;
    late FakeBrowser browser;
    bool needsTwoFactor = false;
    bool rejectCallback = false;
    bool cancelBrowser = false;

    setUp(() {
      store = MemoryTokenStore();
      needsTwoFactor = false;
      rejectCallback = false;
      cancelBrowser = false;
      browser = FakeBrowser((url) async {
        if (cancelBrowser) throw SocialLoginCancelled();
        return callbackFor(url, state: rejectCallback ? 'wrong' : null);
      });
      adapter = FakeAdapter((request) async {
        if (request.path == '/api/auth/providers') {
          return jsonResponse(<String, Object?>{
            'providers': <String, Object?>{'google': true, 'github': true},
          });
        }
        expect(request.path, '/api/auth/mobile/exchange');
        final data = request.data as Map;
        expect(data['code'], 'one_time_test_code');
        expect((data['code_verifier'] as String).length, 43);
        if (needsTwoFactor && data['totp_code'] == null) {
          return jsonResponse(<String, Object?>{'totp_required': true});
        }
        if (needsTwoFactor && data['totp_code'] != '123456') {
          return jsonResponse(<String, Object?>{
            'error': 'Invalid 2FA code',
          }, 401);
        }
        return jsonResponse(issuanceFixture(), 201);
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://api.uptrack.app'))
        ..httpClientAdapter = adapter;
      container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(store),
          uptrackApiProvider.overrideWithValue(UptrackApi(dio: dio)),
          socialBrowserProvider.overrideWithValue(browser),
        ],
      );
    });
    tearDown(() => container.dispose());

    test('signup/signin stores device token without browser session or second issuance', () async {
      final controller = container.read(authControllerProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      await controller.signInWithSocial('google');
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedIn,
      );
      expect(await store.readDeviceToken(), 'udt_test_raw_token');
      expect(
        container.read(authTokenHolderProvider).token,
        'udt_test_raw_token',
      );
      expect(
        adapter.seen.where((r) => r.path == '/api/auth/mobile/exchange').length,
        1,
      );
      expect(adapter.seen.any((r) => r.path == kDeviceTokensPath), false);
    });

    test(
      '2FA required; wrong code stores nothing; correct code finishes',
      () async {
        needsTwoFactor = true;
        final controller = container.read(authControllerProvider.notifier);
        await Future<void>.delayed(Duration.zero);
        await controller.signInWithSocial('github');
        expect(
          container.read(authControllerProvider).status,
          AuthStatus.needsTwoFactor,
        );
        expect(await store.readDeviceToken(), isNull);
        await controller.submitTwoFactorCode('000000');
        expect(
          container.read(authControllerProvider).errorMessage,
          'Invalid 2FA code',
        );
        expect(await store.readDeviceToken(), isNull);
        await controller.submitTwoFactorCode('123456');
        expect(
          container.read(authControllerProvider).status,
          AuthStatus.signedIn,
        );
      },
    );

    test('cancel 2FA clears pending authorization', () async {
      needsTwoFactor = true;
      final controller = container.read(authControllerProvider.notifier);
      await controller.signInWithSocial('google');
      controller.cancelTwoFactor();
      await controller.submitTwoFactorCode('123456');
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedOut,
      );
      expect(await store.readDeviceToken(), isNull);
      expect(
        adapter.seen.where((r) => r.path == '/api/auth/mobile/exchange').length,
        1,
      );
    });

    test('repeated taps launch only one browser session', () async {
      final opened = Completer<Uri>();
      final returned = Completer<Uri>();
      final delayedBrowser = FakeBrowser((url) {
        opened.complete(url);
        return returned.future;
      });
      container.updateOverrides([
        tokenStoreProvider.overrideWithValue(store),
        uptrackApiProvider.overrideWithValue(
          UptrackApi(
            dio: Dio(BaseOptions(baseUrl: 'https://api.uptrack.app'))
              ..httpClientAdapter = adapter,
          ),
        ),
        socialBrowserProvider.overrideWithValue(delayedBrowser),
      ]);
      final controller = container.read(authControllerProvider.notifier);
      final first = controller.signInWithSocial('google');
      final start = await opened.future;
      await controller.signInWithSocial('github');
      expect(delayedBrowser.calls, 1);
      returned.complete(callbackFor(start));
      await first;
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedIn,
      );
    });

    test(
      'browser cancellation is quiet and leaves account signed out',
      () async {
        cancelBrowser = true;
        await container
            .read(authControllerProvider.notifier)
            .signInWithSocial('google');
        expect(container.read(authControllerProvider).isLoading, false);
        expect(container.read(authControllerProvider).errorMessage, isNull);
        expect(await store.readDeviceToken(), isNull);
      },
    );

    test('wrong callback never reaches token exchange', () async {
      rejectCallback = true;
      await container
          .read(authControllerProvider.notifier)
          .signInWithSocial('google');
      expect(container.read(authControllerProvider).errorMessage, isNotNull);
      expect(
        adapter.seen.any((r) => r.path == '/api/auth/mobile/exchange'),
        false,
      );
      expect(await store.readDeviceToken(), isNull);
    });
  });

  // App Store Guideline 4.8: Google/GitHub login on iOS also needs a
  // privacy-focused login such as Sign in with Apple. Until that exists, iOS
  // offers email only.
  group('social providers by platform', () {
    Future<(Set<String>, int)> providersOn(TargetPlatform platform) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final adapter = FakeAdapter(
        (options) async => jsonResponse(<String, Object?>{
          'providers': <String, Object?>{'google': true, 'github': true},
        }),
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://api.uptrack.app'))
        ..httpClientAdapter = adapter;
      final container = ProviderContainer(
        overrides: [uptrackApiProvider.overrideWithValue(UptrackApi(dio: dio))],
      );
      addTearDown(container.dispose);
      final providers = await container.read(socialProvidersProvider.future);
      return (providers, adapter.seen.length);
    }

    test('iOS offers no social login and does not ask the server', () async {
      final (providers, requests) = await providersOn(TargetPlatform.iOS);
      expect(providers, isEmpty);
      expect(requests, 0);
    });

    test('Android keeps the configured providers', () async {
      final (providers, _) = await providersOn(TargetPlatform.android);
      expect(providers, <String>{'google', 'github'});
    });
  });

  testWidgets(
    'only configured social providers appear and signup is explicit',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
            socialProvidersProvider.overrideWith(
              (ref) async => <String>{'google'},
            ),
          ],
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with GitHub'), findsNothing);
      expect(
        find.text('Sign up or sign in with your Uptrack account.'),
        findsOneWidget,
      );
      expect(find.textContaining('choose plan'), findsNothing);
    },
  );
}
