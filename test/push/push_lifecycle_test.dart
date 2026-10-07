import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/database_providers.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/push/push_registration.dart';

/// Plan item 4.3: the push device follows the signed-in session.
///
/// The server keys `push_devices` by user, not by device token, so revoking
/// the device token does NOT stop pushes. Only `DELETE /api/push/devices`
/// does, and that endpoint needs the device-token bearer. These tests use a
/// fake server that enforces exactly that.
class _Server implements HttpClientAdapter {
  final List<String> calls = <String>[];
  final List<RequestOptions> seen = <RequestOptions>[];
  bool deviceTokenRevoked = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    final String key = '${options.method} ${options.path}';
    calls.add(key);
    final Object? auth = options.headers['Authorization'];
    final bool bearer = auth == 'Bearer udt_test_raw_token';
    if (key == 'POST $kLoginPath') {
      return _json(_me(), 200, <String, List<String>>{
        'set-cookie': <String>['_uptrack_key=abc; Path=/; HttpOnly'],
      });
    }
    if (key == 'POST $kDeviceTokensPath') {
      return _json(<String, Object?>{
        'id': '44444444-4444-4444-8444-444444444444',
        'label': null,
        'token': 'udt_test_raw_token',
        'created_at': '2026-01-01T00:00:00',
      }, 201);
    }
    if (key == 'POST $kLogoutPath') {
      return _json(<String, Object?>{});
    }
    // Device-token routes: a revoked bearer is a 401, like the server.
    if (!bearer || deviceTokenRevoked) {
      return _json(<String, Object?>{'error': 'Unauthorized'}, 401);
    }
    if (key ==
        'DELETE $kDeviceTokensPath/44444444-4444-4444-8444-444444444444') {
      deviceTokenRevoked = true;
      return _json(<String, Object?>{'ok': true});
    }
    if (key == 'DELETE $kPushDevicesPath' || key == 'POST $kPushDevicesPath') {
      return _json(<String, Object?>{'ok': true});
    }
    return _json(<String, Object?>{'error': 'unexpected $key'}, 500);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(
  Map<String, Object?> body, [
  int status = 200,
  Map<String, List<String>> headers = const <String, List<String>>{},
]) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      ...headers,
    },
  );
}

Map<String, Object?> _me() => <String, Object?>{
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Server server;
  late ProviderContainer container;

  setUp(() {
    server = _Server();
    final AuthTokenHolder holder = AuthTokenHolder();
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
            adapter: server,
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
  });

  Future<void> signIn() => container
      .read(authControllerProvider.notifier)
      .signInWithPassword(email: 'ada@example.com', password: 'secret');

  group('logout unregisters the push device (4.3)', () {
    test(
      'signOut() with no argument unregisters the registered token while the '
      'bearer is still valid',
      () async {
        await signIn();
        // What PushService records after a successful POST /api/push/devices.
        container
            .read(pushRegistrationStoreProvider)
            .markRegistered(
              const PushRegistration(
                platform: 'ios',
                token: 'apns-hex-1',
                environment: 'production',
              ),
            );

        // The settings screen calls signOut() with no push token.
        await container.read(authControllerProvider.notifier).signOut();

        final int unregister = server.calls.indexOf('DELETE $kPushDevicesPath');
        final int revoke = server.calls.indexOf(
          'DELETE $kDeviceTokensPath/44444444-4444-4444-8444-444444444444',
        );
        expect(unregister, isNot(-1), reason: 'push device never unregistered');
        expect(
          unregister,
          lessThan(revoke),
          reason:
              'the unregister needs the device-token bearer, so it must run '
              'before the device token is revoked',
        );
        final RequestOptions delete = server.seen.firstWhere(
          (RequestOptions o) =>
              o.method == 'DELETE' && o.path == kPushDevicesPath,
        );
        expect(delete.data, <String, Object?>{'token': 'apns-hex-1'});
        expect(
          container.read(pushRegistrationStoreProvider).registered,
          isNull,
          reason: 'the next sign-in must register again',
        );
      },
    );

    test('an explicit pushToken still wins and is unregistered first', () async {
      await signIn();
      await container
          .read(authControllerProvider.notifier)
          .signOut(pushToken: 'fcm-token-1');
      final int unregister = server.calls.indexOf('DELETE $kPushDevicesPath');
      final int revoke = server.calls.indexOf(
        'DELETE $kDeviceTokensPath/44444444-4444-4444-8444-444444444444',
      );
      expect(unregister, isNot(-1));
      expect(unregister, lessThan(revoke));
    });

    test('no registered token means no unregister call', () async {
      await signIn();
      await container.read(authControllerProvider.notifier).signOut();
      expect(server.calls, isNot(contains('DELETE $kPushDevicesPath')));
    });

    test('a 401 drops the registration record locally', () async {
      await signIn();
      container
          .read(pushRegistrationStoreProvider)
          .markRegistered(
            const PushRegistration(platform: 'android', token: 'fcm-1'),
          );
      container.read(authControllerProvider.notifier).handleUnauthorized();
      expect(container.read(pushRegistrationStoreProvider).registered, isNull);
    });
  });
}
