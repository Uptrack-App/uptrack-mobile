import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/app.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/social_login.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';

import 'auth_test.dart'
    show
        FakeAdapter,
        jsonResponse,
        meFixture,
        issuanceFixture,
        sessionCookieHeader;

class _DelayedStore extends MemoryTokenStore {
  final ready = Completer<String?>();
  @override
  Future<String?> readDeviceToken() => ready.future;
}

void main() {
  test('rejects foreign callback URLs', () {
    for (final url in [
      'https://evil.test/auth/verify-magic-link?email=a@b.com&token=t',
      'uptrack://evil/magic?email=a@b.com&token=t',
      'uptrack://auth/other?email=a@b.com&token=t',
    ]) {
      expect(parseMagicLink(Uri.parse(url)), isNull);
    }
  });
  for (final cold in [true, false]) {
    testWidgets(
      '${cold ? 'cold' : 'warm'} callback preserves 2FA, rejects replay, and allows a fresh link',
      (tester) async {
        final holder = AuthTokenHolder();
        final store = _DelayedStore();
        var issued = 0;
        var verifies = 0;
        final adapter = FakeAdapter((options) async {
          if (options.path == kMagicLinkVerifyPath) {
            verifies++;
            final data = options.data as Map;
            if (data['token'] == 'expired') {
              return jsonResponse({'error': 'Link expired'}, 400);
            }
            if (data['totp_code'] == null) {
              return jsonResponse({'totp_required': true});
            }
            return jsonResponse(meFixture(), 200, sessionCookieHeader);
          }
          if (options.path == kDeviceTokensPath) {
            issued++;
            return jsonResponse(issuanceFixture(), 201);
          }
          return jsonResponse(meFixture());
        });
        final container = ProviderContainer(
          overrides: [
            tokenStoreProvider.overrideWithValue(store),
            authTokenHolderProvider.overrideWithValue(holder),
            socialProvidersProvider.overrideWith((ref) async => <String>{}),
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
        final router = createRouter(
          authStatusOf: () => container.read(authControllerProvider).status,
          initialLocation: cold
              ? '/magic?email=ada%40example.com&token=expired'
              : '/login',
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        if (!cold) {
          router.go('/magic?email=ada%40example.com&token=expired');
          await tester.pump();
        }
        expect(verifies, 0); // Storage restore has not finished yet.
        store.ready.complete(null);
        await tester.pumpAndSettle();
        expect(find.text('Link expired'), findsOneWidget);
        expect(issued, 0);
        await tester.pump();
        expect(verifies, 1); // Rebuilding must not consume a token twice.
        router.go('/magic?email=ada%40example.com&token=fresh');
        await tester.pumpAndSettle();
        expect(
          find.text('Enter the 6-digit code from your authenticator app.'),
          findsOneWidget,
        );
        expect(issued, 0);
        await tester.enterText(
          find.widgetWithText(TextFormField, '2FA code'),
          '123456',
        );
        await tester.tap(find.text('Verify'));
        await tester.pumpAndSettle();
        expect(issued, 1);
        expect(
          container.read(authControllerProvider).status,
          AuthStatus.signedIn,
        );
        expect(holder.token, 'udt_test_raw_token');
      },
    );
  }
}
