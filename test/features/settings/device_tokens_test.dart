import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/device_token.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/features/settings/settings_screen.dart';

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

ResponseBody jsonResponse(Map<String, Object?> json, [int status = 200]) {
  return ResponseBody.fromString(
    jsonEncode(json),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );
}

Map<String, Object?> deviceFixture(String id, String? label) =>
    <String, Object?>{
      'id': id,
      'label': label,
      'created_at': '2026-01-01T00:00:00',
      'last_used_at': null,
    };

Map<String, Object?> listFixture() => <String, Object?>{
  'data': <Object?>[
    deviceFixture('11111111-1111-4111-8111-111111111111', 'Pixel 9'),
    deviceFixture('22222222-2222-4222-8222-222222222222', null),
  ],
};

Dio dioWithFake(Future<ResponseBody> Function(RequestOptions) handler) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:4000'));
  dio.httpClientAdapter = FakeAdapter(handler);
  return dio;
}

void main() {
  group('DeviceToken model', () {
    test('fromJson parses metadata; unlabeled falls back', () {
      final DeviceToken named = DeviceToken.fromJson(
        deviceFixture('id-1', 'Work iPhone'),
      );
      expect(named.id, 'id-1');
      expect(named.displayName, 'Work iPhone');

      final DeviceToken unlabeled = DeviceToken.fromJson(
        deviceFixture('id-2', null),
      );
      expect(unlabeled.displayName, 'Unlabeled device');
    });
  });

  group('UptrackApi device tokens', () {
    test('listDeviceTokens parses the data envelope', () async {
      RequestOptions? seen;
      final Dio dio = dioWithFake((RequestOptions options) async {
        seen = options;
        return jsonResponse(listFixture());
      });

      final List<DeviceToken> devices = await UptrackApi(dio: dio)
          .listDeviceTokens();

      expect(seen?.method, 'GET');
      expect(seen?.path, kDeviceTokensPath);
      expect(devices, hasLength(2));
      expect(devices.first.displayName, 'Pixel 9');
      expect(devices.last.displayName, 'Unlabeled device');
    });

    test('revokeDeviceToken DELETEs the id path', () async {
      RequestOptions? seen;
      final Dio dio = dioWithFake((RequestOptions options) async {
        seen = options;
        return jsonResponse(<String, Object?>{'ok': true});
      });

      await UptrackApi(dio: dio)
          .revokeDeviceToken('11111111-1111-4111-8111-111111111111');

      expect(seen?.method, 'DELETE');
      expect(
        seen?.path,
        '$kDeviceTokensPath/11111111-1111-4111-8111-111111111111',
      );
    });
  });

  group('SettingsScreen device management', () {
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

    /// The devices section sits below the profile/notifications/billing
    /// sections, so it is lazily built only once scrolled to. Drags the
    /// outer list until [finder] is hit-testable (presence alone is not
    /// enough: the list builds ahead into its cache extent). A plain
    /// `scrollUntilVisible` cannot pin the outer [Scrollable]: the
    /// quiet-hours text fields each contain their own inner scrollable.
    Future<void> scrollToDevices(WidgetTester tester, Finder finder) async {
      final Finder list = find.byKey(const ValueKey<String>('settings-list'));
      for (int i = 0; i < 15 && finder.hitTestable().evaluate().isEmpty; i++) {
        await tester.drag(list, const Offset(0, -500));
        await tester.pumpAndSettle();
      }
      await tester.pumpAndSettle();
    }

    ProviderContainer makeContainer(
      Future<ResponseBody> Function(RequestOptions) handler,
    ) {
      final AuthTokenHolder holder = AuthTokenHolder()..token = 'udt_test';
      final FakeAdapter adapter = FakeAdapter(handler);
      final ProviderContainer container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
          authTokenHolderProvider.overrideWithValue(holder),
          dioProvider.overrideWithValue(
            buildAppDio(
              holder: holder,
              onUnauthorized: () {},
              adapter: adapter,
            ),
          ),
        ],
      );
      return container;
    }

    testWidgets('lists devices with labels and fallback', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = makeContainer(
        (RequestOptions options) async => jsonResponse(listFixture()),
      );
      addTearDown(container.dispose);

      await pumpSettings(tester, container);

      await scrollToDevices(tester, find.text('Pixel 9'));
      expect(find.text('Devices'), findsOneWidget);
      expect(find.text('Pixel 9'), findsOneWidget);
      expect(find.text('Unlabeled device'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
    });

    testWidgets('empty list shows the empty state', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = makeContainer(
        (RequestOptions options) async =>
            jsonResponse(<String, Object?>{'data': <Object?>[]}),
      );
      addTearDown(container.dispose);

      await pumpSettings(tester, container);

      await scrollToDevices(tester, find.text('No devices signed in.'));
      expect(find.text('No devices signed in.'), findsOneWidget);
    });

    testWidgets('server error shows message + retry recovers', (
      WidgetTester tester,
    ) async {
      bool fail = true;
      final ProviderContainer container = makeContainer((
        RequestOptions options,
      ) async {
        if (fail) {
          return jsonResponse(<String, Object?>{'error': 'boom'}, 500);
        }
        return jsonResponse(listFixture());
      });
      addTearDown(container.dispose);

      await pumpSettings(tester, container);

      await scrollToDevices(tester, find.text('boom'));
      expect(find.text('boom'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      await scrollToDevices(tester, find.text('Pixel 9'));
      expect(find.text('Pixel 9'), findsOneWidget);
    });

    testWidgets('revoke removes the row; failure keeps it + persistent error', (
      WidgetTester tester,
    ) async {
      bool revokeShouldFail = false;
      final ProviderContainer container = makeContainer((
        RequestOptions options,
      ) async {
        if (options.method == 'GET') {
          return jsonResponse(listFixture());
        }
        if (options.method == 'DELETE') {
          if (revokeShouldFail) {
            return jsonResponse(<String, Object?>{'error': 'nope'}, 500);
          }
          return jsonResponse(<String, Object?>{'ok': true});
        }
        return jsonResponse(<String, Object?>{}, 500);
      });
      addTearDown(container.dispose);

      await pumpSettings(tester, container);
      await scrollToDevices(tester, find.text('Pixel 9'));
      expect(find.text('Pixel 9'), findsOneWidget);

      // Successful revoke drops the row.
      await scrollToDevices(
        tester,
        find.byKey(
          const ValueKey<String>('revoke-11111111-1111-4111-8111-111111111111'),
        ),
      );
      await tester.tap(
        find.byKey(
          const ValueKey<String>('revoke-11111111-1111-4111-8111-111111111111'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pixel 9'), findsNothing);
      expect(find.text('Unlabeled device'), findsOneWidget);

      // Failed revoke keeps the row and surfaces a persistent error.
      revokeShouldFail = true;
      await scrollToDevices(
        tester,
        find.byKey(
          const ValueKey<String>('revoke-22222222-2222-4222-8222-222222222222'),
        ),
      );
      await tester.tap(
        find.byKey(
          const ValueKey<String>('revoke-22222222-2222-4222-8222-222222222222'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unlabeled device'), findsOneWidget);
      expect(find.text('nope'), findsOneWidget);
    });
  });
}
