import 'dart:async';

import 'package:dio/dio.dart' show RequestOptions;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/app.dart';
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

/// Plan 5.3: the emailed sign-in link reaches the sign-in step in both forms
/// (universal link `https://uptrack.app/auth/verify-magic-link` and the
/// `uptrack://auth/magic` scheme), at cold start and when the app is open.
///
/// The link is delivered the way the Flutter engine delivers it: on iOS
/// `FlutterSceneDelegate` / `FlutterAppDelegate` call
/// `sendDeepLinkToFramework`, which sends `pushRouteInformation` with the full
/// URL (`absoluteString`) on the `flutter/navigation` channel after the first
/// frame. That is the same path for both schemes, so the test drives the
/// channel and not `router.go`.
class _DelayedStore extends MemoryTokenStore {
  final Completer<String?> ready = Completer<String?>();
  @override
  Future<String?> readDeviceToken() => ready.future;
}

const Map<String, String> _links = <String, String>{
  'universal link':
      'https://uptrack.app/auth/verify-magic-link'
      '?token=abc123&email=ada%40example.com&client=mobile',
  'universal link with a web redirect':
      'https://uptrack.app/auth/verify-magic-link'
      '?token=abc123&email=ada%40example.com&client=mobile'
      '&redirect=%2Fdashboard',
  'uptrack scheme': 'uptrack://auth/magic?email=ada%40example.com&token=abc123',
};

Future<void> _deliverLink(WidgetTester tester, String url) async {
  final ByteData message = const JSONMethodCodec().encodeMethodCall(
    MethodCall('pushRouteInformation', <String, Object?>{
      'location': url,
      'state': null,
    }),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    message,
    (ByteData? _) {},
  );
}

void main() {
  for (final MapEntry<String, String> link in _links.entries) {
    for (final bool cold in <bool>[true, false]) {
      testWidgets('${link.key} signs in at ${cold ? 'cold' : 'warm'} start', (
        WidgetTester tester,
      ) async {
        final AuthTokenHolder holder = AuthTokenHolder();
        final _DelayedStore store = _DelayedStore();
        final List<Map<dynamic, dynamic>> verifies = <Map<dynamic, dynamic>>[];
        final FakeAdapter adapter = FakeAdapter((RequestOptions options) async {
          if (options.path == kMagicLinkVerifyPath) {
            verifies.add(options.data as Map<dynamic, dynamic>);
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
            socialProvidersProvider.overrideWith((Ref ref) async => <String>{}),
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
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        if (cold) {
          // Cold start: the engine sends the link after the first frame,
          // while the stored session is still being restored.
          await _deliverLink(tester, link.value);
          await tester.pump();
          expect(verifies, isEmpty);
          store.ready.complete(null);
        } else {
          // Warm start: the app is open on the sign-in screen.
          store.ready.complete(null);
          await tester.pumpAndSettle();
          expect(router.state.matchedLocation, '/login');
          await _deliverLink(tester, link.value);
        }
        await tester.pumpAndSettle();

        expect(verifies, hasLength(1));
        expect(verifies.single['token'], 'abc123');
        expect(verifies.single['email'], 'ada@example.com');
        expect(
          container.read(authControllerProvider).status,
          AuthStatus.signedIn,
        );
        expect(holder.token, 'udt_test_raw_token');
      });
    }
  }
}
