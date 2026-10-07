import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/database_providers.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/push/push_channels.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/push/push_providers.dart';
import 'package:uptrack_mobile/push/push_registration.dart';
import 'package:uptrack_mobile/push/push_service.dart';

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

    test(
      'an explicit pushToken still wins and is unregistered first',
      () async {
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
      },
    );

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

  group('app wiring: real pushServiceProvider + auth session (4.3)', () {
    const String plugin = 'dexterous.com/flutter/local_notifications';
    late List<String> pluginCalls;
    TargetPlatform? previous;

    setUp(() {
      previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      pluginCalls = <String>[];
      final TestDefaultBinaryMessenger messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel(plugin), (
        MethodCall call,
      ) async {
        pluginCalls.add(call.method);
        return call.method == 'getNotificationAppLaunchDetails' ? null : true;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel(PushChannels.token),
        (MethodCall call) async => call.method == PushTokenMethods.getToken
            ? <String, Object?>{'token': 'fcm-live', 'platform': 'android'}
            : null,
      );
      addTearDown(() {
        debugDefaultTargetPlatformOverride = previous;
        messenger.setMockMethodCallHandler(const MethodChannel(plugin), null);
        messenger.setMockMethodCallHandler(
          const MethodChannel(PushChannels.token),
          null,
        );
      });
    });

    test('login registers with the bearer; logout unregisters it', () async {
      container.read(pushAuthBindingProvider);
      await container.read(pushServiceProvider).initialize();
      expect(
        server.calls,
        isNot(contains('POST $kPushDevicesPath')),
        reason: 'signed out at launch',
      );
      expect(pluginCalls, isNot(contains('requestNotificationsPermission')));

      await signIn();
      // The binding reacts to the status change asynchronously.
      await pumpEventQueue();

      final RequestOptions post = server.seen.singleWhere(
        (RequestOptions o) => o.method == 'POST' && o.path == kPushDevicesPath,
      );
      expect(post.headers['Authorization'], 'Bearer udt_test_raw_token');
      expect(post.data, <String, Object?>{
        'platform': 'android',
        'token': 'fcm-live',
      });
      expect(pluginCalls, contains('requestNotificationsPermission'));

      await container.read(authControllerProvider.notifier).signOut();

      final RequestOptions delete = server.seen.singleWhere(
        (RequestOptions o) =>
            o.method == 'DELETE' && o.path == kPushDevicesPath,
      );
      expect(delete.data, <String, Object?>{'token': 'fcm-live'});
      expect(
        server.calls.indexOf('DELETE $kPushDevicesPath'),
        lessThan(
          server.calls.indexOf(
            'DELETE $kDeviceTokensPath/44444444-4444-4444-8444-444444444444',
          ),
        ),
      );
    });
  });

  group('PushService registration follows the session (4.3)', () {
    late _Lifecycle h;

    setUp(() => h = _Lifecycle());

    test('signed out at launch: no token request, no POST', () async {
      h.signedIn = false;
      await h.service.initialize();

      expect(
        h.tokenCalls,
        isNot(contains(PushTokenMethods.getToken)),
        reason:
            'getToken raises the iOS permission prompt; it must not show on '
            'the login screen',
      );
      expect(h.posted, isEmpty);
      expect(h.store.registered, isNull);
    });

    test('sign-in registers the token and records it for logout', () async {
      h.signedIn = false;
      await h.service.initialize();

      h.signedIn = true;
      await h.service.onAuthChanged(signedIn: true);

      expect(h.posted, <PushRegistration>[
        const PushRegistration(
          platform: 'ios',
          token: 'apns-1',
          environment: 'production',
        ),
      ]);
      expect(h.store.registered?.token, 'apns-1');
    });

    test('signed in at launch registers once', () async {
      await h.service.initialize();
      await h.service.onAuthChanged(signedIn: true);

      expect(h.posted, hasLength(1));
      expect(h.store.registered?.token, 'apns-1');
    });

    test(
      'a token that arrives while signed out is registered at sign-in',
      () async {
        // iOS: APNs answers after the prompt, so getToken has nothing yet and
        // the token arrives later as onPushToken.
        h.nativeToken = null;
        h.signedIn = false;
        await h.service.initialize();
        await h.sendEvent(PushEventMethods.onPushToken, <String, Object?>{
          'token': 'apns-late',
          'platform': 'ios',
          'environment': 'sandbox',
        });
        expect(h.posted, isEmpty, reason: 'no bearer yet: the POST would 401');

        h.signedIn = true;
        await h.service.onAuthChanged(signedIn: true);

        expect(h.posted.single.token, 'apns-late');
        expect(h.posted.single.environment, 'sandbox');
      },
    );

    test('token refresh re-registers, keeps the environment, and logout then '
        'targets the new token', () async {
      await h.service.initialize();
      await h.sendEvent(PushEventMethods.onTokenRefresh, <String, Object?>{
        'token': 'apns-2',
      });

      expect(h.posted.last.token, 'apns-2');
      expect(h.posted.last.platform, 'ios');
      expect(
        h.posted.last.environment,
        'production',
        reason: 'a refresh must not move the device to the default host',
      );
      expect(h.store.registered?.token, 'apns-2');
    });

    test('a failed POST (offline) never escapes and is retried', () async {
      h.failPosts = true;
      await h.service.initialize();
      await h.sendEvent(PushEventMethods.onTokenRefresh, <String, Object?>{
        'token': 'apns-3',
      });
      expect(h.store.registered, isNull);

      h.failPosts = false;
      await h.service.onAuthChanged(signedIn: true);
      expect(h.store.registered?.token, isNotNull);
    });

    test('sign-out stops later token events from registering', () async {
      await h.service.initialize();
      h.signedIn = false;
      await h.service.onAuthChanged(signedIn: false);
      final int before = h.posted.length;

      await h.sendEvent(PushEventMethods.onTokenRefresh, <String, Object?>{
        'token': 'apns-4',
      });

      expect(h.posted.length, before);
    });

    test('android asks for the notification permission at sign-in', () async {
      h.platform = TargetPlatform.android;
      h.nativeToken = <String, Object?>{
        'token': 'fcm-1',
        'platform': 'android',
      };
      h.signedIn = false;
      await h.service.initialize();
      expect(h.permissionRequests, 0);

      h.signedIn = true;
      await h.service.onAuthChanged(signedIn: true);

      expect(
        h.permissionRequests,
        1,
        reason:
            'Android 13+ blocks every notification until POST_NOTIFICATIONS '
            'is granted at runtime',
      );
      expect(h.posted.single.token, 'fcm-1');
    });
  });
}

class _Lifecycle {
  _Lifecycle() {
    messenger.setMockMethodCallHandler(
      const MethodChannel(PushChannels.token),
      (MethodCall call) async {
        tokenCalls.add(call.method);
        if (call.method == PushTokenMethods.getToken) {
          return nativeToken;
        }
        return null;
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel(PushChannels.token),
        null,
      ),
    );
  }

  bool signedIn = true;
  bool failPosts = false;
  int permissionRequests = 0;
  TargetPlatform platform = TargetPlatform.iOS;
  Map<String, Object?>? nativeToken = <String, Object?>{
    'token': 'apns-1',
    'platform': 'ios',
    'environment': 'production',
  };
  final List<String> tokenCalls = <String>[];
  final List<PushRegistration> posted = <PushRegistration>[];
  final PushRegistrationStore store = PushRegistrationStore();

  late final PushService service = PushService(
    registerToken:
        ({
          required String platform,
          required String token,
          String? environment,
        }) async {
          if (failPosts) {
            throw DioException(
              requestOptions: RequestOptions(path: kPushDevicesPath),
              type: DioExceptionType.connectionError,
            );
          }
          posted.add(
            PushRegistration(
              platform: platform,
              token: token,
              environment: environment,
            ),
          );
        },
    onNavigate: (_) {},
    events: const MethodChannel(PushChannels.events),
    tokenChannel: const MethodChannel(PushChannels.token),
    notifier: _SilentNotifier(),
    platform: platform,
    registrationStore: store,
    isSignedIn: () => signedIn,
    requestPermission: () async {
      permissionRequests++;
      return true;
    },
  );

  TestDefaultBinaryMessenger get messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> sendEvent(String method, [Map<String, Object?>? args]) {
    return messenger.handlePlatformMessage(
      PushChannels.events,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }
}

class _SilentNotifier implements LocalNotifier {
  @override
  Future<void> initialize({
    required void Function(PushMessage message) onTap,
  }) async {}

  @override
  Future<PushMessage?> initialNotification() async => null;

  @override
  Future<void> showForeground(PushMessage message) async {}
}
