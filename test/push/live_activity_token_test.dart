import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/push/push_channels.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/push/push_registration.dart';
import 'package:uptrack_mobile/push/push_service.dart';
import 'package:uptrack_mobile/widgets/live_activity.dart';

/// Fake [LocalNotifier] — same seam as `test/push/push_test.dart`.
class FakeNotifier implements LocalNotifier {
  @override
  Future<void> initialize({
    required void Function(PushMessage message) onTap,
  }) async {}

  @override
  Future<void> showForeground(PushMessage message) async {}

  @override
  Future<PushMessage?> initialNotification() async => null;
}

class LiveActivityHarness {
  LiveActivityHarness({this.throwOnRegister = false, this.signedIn = true}) {
    service = PushService(
      registerToken: ({
        required String platform,
        required String token,
        String? environment,
      }) async {},
      onNavigate: (_) {},
      events: const MethodChannel(PushChannels.events),
      tokenChannel: const MethodChannel(PushChannels.token),
      notifier: FakeNotifier(),
      platform: TargetPlatform.iOS,
      registrationStore: store,
      isSignedIn: () => signedIn,
      registerLiveActivity: (LiveActivityRegisterRequest request) async {
        attempts.add(request);
        if (throwOnRegister) {
          throw Exception('offline');
        }
        registered.add(request);
      },
      unregisterLiveActivity: (LiveActivityRemoveRequest request) async {
        if (throwOnRegister) {
          throw Exception('offline');
        }
        removed.add(request.token);
      },
    );
  }

  late final PushService service;
  final PushRegistrationStore store = PushRegistrationStore();
  final List<LiveActivityRegisterRequest> attempts =
      <LiveActivityRegisterRequest>[];
  final List<LiveActivityRegisterRequest> registered =
      <LiveActivityRegisterRequest>[];
  final List<String> removed = <String>[];
  bool throwOnRegister;
  bool signedIn;

  TestDefaultBinaryMessenger get messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> sendEvent(String method, [Map<String, Object?>? args]) {
    final ByteData message = const StandardMethodCodec().encodeMethodCall(
      MethodCall(method, args),
    );
    return messenger.handlePlatformMessage(
      PushChannels.events,
      message,
      (_) {},
    );
  }

  Future<void> signOut() async {
    signedIn = false;
    store.clearRegistered();
    await service.onAuthChanged(signedIn: false);
  }

  Future<void> signIn() async {
    signedIn = true;
    await service.onAuthChanged(signedIn: true);
  }
}

/// Native push-to-start payload (`UptrackLiveActivityLogic.pushToStartPayload`).
Map<String, Object?> _pts(String token, {String? environment = 'sandbox'}) =>
    <String, Object?>{
      'token': token,
      'kind': 'push_to_start',
      'environment': ?environment,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(PushChannels.token),
          null,
        );
  });

  group('push-to-start token (one row per signed-in device)', () {
    test('posts as soon as it is known, with no incident and its '
        'environment', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onLiveActivityToken, _pts('pts-1'));

      final LiveActivityRegisterRequest request = h.registered.single;
      expect(request.toJson(), <String, Object?>{
        'token': 'pts-1',
        'kind': 'push_to_start',
        'environment': 'sandbox',
      });
      expect(request.validate(), isEmpty);
      expect(h.store.registeredPushToStart, 'pts-1');
    });

    test('an old payload with an incident id posts without it', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'pts-1',
        'kind': 'push_to_start',
        'incident_id': 'inc-1',
      });

      expect(h.registered.single.incidentId, isNull);
      expect(h.registered.single.kind, 'push_to_start');
    });

    test('kind defaults to push_to_start when omitted', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'pts-2',
      });

      expect(h.registered.single.kind, 'push_to_start');
    });

    test('the same token posts once per session', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onLiveActivityToken, _pts('pts-1'));
      await h.sendEvent(PushEventMethods.onLiveActivityToken, _pts('pts-1'));
      await h.sendEvent(PushEventMethods.onForegroundMessage, <String, Object?>{
        'title': 'P1: api down',
        'incident_id': 'inc-9',
      });
      await h.signIn();

      expect(h.attempts, hasLength(1));
    });

    test('concurrent deliveries of one token post once', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();

      await Future.wait(<Future<void>>[
        h.sendEvent(PushEventMethods.onLiveActivityToken, _pts('pts-1')),
        h.sendEvent(PushEventMethods.onLiveActivityToken, _pts('pts-1')),
      ]);

      expect(h.attempts, hasLength(1));
    });

    test('a rotated token posts again', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onLiveActivityToken, _pts('pts-1'));
      await h.sendEvent(PushEventMethods.onLiveActivityToken, _pts('pts-2'));

      expect(
        h.registered.map((LiveActivityRegisterRequest r) => r.token),
        <String>['pts-1', 'pts-2'],
      );
      expect(h.store.registeredPushToStart, 'pts-2');
    });

    test('never posts while signed out; posts at the next sign-in', () async {
      final LiveActivityHarness h = LiveActivityHarness(signedIn: false);
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onLiveActivityToken, _pts('pts-1'));
      await h.sendEvent(PushEventMethods.onForegroundMessage, <String, Object?>{
        'title': 'P1: api down',
        'incident_id': 'inc-9',
      });
      expect(h.attempts, isEmpty);
      expect(h.service.pushToStartToken, 'pts-1');

      await h.signIn();

      expect(h.registered.single.token, 'pts-1');
    });

    test(
      'a failed post is retried at the next opportunity, then stops',
      () async {
        final LiveActivityHarness h = LiveActivityHarness(
          throwOnRegister: true,
        );
        await h.service.initialize();

        await h.sendEvent(PushEventMethods.onLiveActivityToken, _pts('pts-1'));
        expect(h.registered, isEmpty);
        expect(h.store.registeredPushToStart, isNull);

        h.throwOnRegister = false;
        // An incoming push is the next opportunity.
        await h.sendEvent(
          PushEventMethods.onForegroundMessage,
          <String, Object?>{'title': 'P1: api down'},
        );
        expect(h.registered.single.token, 'pts-1');

        await h.sendEvent(PushEventMethods.onNotificationTap, <String, Object?>{
          'incident_id': 'inc-3',
        });
        expect(h.attempts, hasLength(2));
      },
    );

    test('a failed post is retried on a restored session', () async {
      final LiveActivityHarness h = LiveActivityHarness(throwOnRegister: true);
      await h.service.initialize();
      await h.sendEvent(PushEventMethods.onLiveActivityToken, _pts('pts-1'));

      h.throwOnRegister = false;
      await h.signIn();

      expect(h.registered.single.token, 'pts-1');
    });

    test('sign-out then sign-in posts the token again (new session)', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();
      await h.sendEvent(PushEventMethods.onLiveActivityToken, _pts('pts-1'));

      await h.signOut();
      expect(h.store.registeredPushToStart, isNull);
      await h.sendEvent(PushEventMethods.onLiveActivityToken, _pts('pts-1'));
      expect(h.attempts, hasLength(1), reason: 'signed out: no post');

      await h.signIn();

      expect(h.attempts, hasLength(2));
      expect(h.registered.last.token, 'pts-1');
    });

    test('a 401 that drops the session also drops the record', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();
      await h.sendEvent(PushEventMethods.onLiveActivityToken, _pts('pts-1'));

      // AuthController.handleUnauthorized clears the store.
      h.store.clearRegistered();

      expect(h.store.registeredPushToStart, isNull);
    });

    test('without a native environment, the APNs registration environment '
        'is used', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();
      await h.sendEvent(PushEventMethods.onPushToken, <String, Object?>{
        'token': 'apns-hex',
        'platform': 'ios',
        'environment': 'production',
      });

      await h.sendEvent(
        PushEventMethods.onLiveActivityToken,
        _pts('pts-1', environment: null),
      );

      expect(h.registered.single.environment, 'production');
    });

    test('an unknown environment is not sent', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();

      await h.sendEvent(
        PushEventMethods.onLiveActivityToken,
        _pts('pts-1', environment: 'staging'),
      );

      expect(h.registered.single.environment, isNull);
      expect(h.registered.single.validate(), isEmpty);
    });

    test('malformed payloads post nothing', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();

      // Missing token.
      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'kind': 'push_to_start',
      });
      // Blank token.
      await h.sendEvent(PushEventMethods.onLiveActivityToken, _pts('  '));
      // Unknown kind.
      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'la-x',
        'kind': 'bogus',
        'incident_id': 'inc-1',
      });
      // Unscoped `update` token: names no activity.
      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'la-z',
        'kind': 'update',
      });
      // Update TTL outside the server 60s..7d bounds.
      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'la-y',
        'kind': 'update',
        'incident_id': 'inc-1',
        'expires_in_seconds': 5,
      });

      expect(h.attempts, isEmpty);
      expect(h.service.pushToStartToken, isNull);
    });

    test('unwired service keeps the token without crashing', () async {
      final PushService service = PushService(
        registerToken: ({
          required String platform,
          required String token,
          String? environment,
        }) async {},
        onNavigate: (_) {},
        events: const MethodChannel(PushChannels.events),
        tokenChannel: const MethodChannel(PushChannels.token),
        notifier: FakeNotifier(),
      );
      await service.initialize();
      final ByteData message = const StandardMethodCodec().encodeMethodCall(
        MethodCall(PushEventMethods.onLiveActivityToken, _pts('pts-1')),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(PushChannels.events, message, (_) {});

      expect(service.pushToStartToken, 'pts-1');
    });

    test('initialize posts the token the native host saw before Dart '
        'listened', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(PushChannels.token), (
            MethodCall call,
          ) async {
            if (call.method == PushTokenMethods.getLiveActivityTokens) {
              return <Object?>[_pts('pts-1', environment: 'production')];
            }
            return null;
          });
      final LiveActivityHarness h = LiveActivityHarness();

      await h.service.initialize();

      expect(h.registered.single.token, 'pts-1');
      expect(h.registered.single.environment, 'production');
    });

    test(
      'signed out at launch: the pulled token waits for the session',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(PushChannels.token), (
              MethodCall call,
            ) async {
              if (call.method == PushTokenMethods.getLiveActivityTokens) {
                return <Object?>[_pts('pts-1')];
              }
              return null;
            });
        final LiveActivityHarness h = LiveActivityHarness(signedIn: false);

        await h.service.initialize();
        expect(h.attempts, isEmpty);

        await h.signIn();
        expect(h.registered.single.token, 'pts-1');
      },
    );
  });

  group('Live Activity token lifecycle (I2.2)', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(PushChannels.token),
            null,
          );
    });

    test('the per-activity update token registers with its TTL', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();

      // Shape sent by UptrackLiveActivityBridge for every activity.
      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'upd-1',
        'kind': 'update',
        'incident_id': 'inc-1',
        'expires_in_seconds': 43200,
        'environment': 'sandbox',
      });

      final LiveActivityRegisterRequest request = h.registered.single;
      expect(request.toJson(), <String, Object?>{
        'incident_id': 'inc-1',
        'token': 'upd-1',
        'expires_in_seconds': 43200,
        'kind': 'update',
        'environment': 'sandbox',
      });
      expect(request.validate(), isEmpty);
    });

    test('the same token for the same incident posts once', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();
      final Map<String, Object?> payload = <String, Object?>{
        'token': 'upd-1',
        'kind': 'update',
        'incident_id': 'inc-1',
      };

      await h.sendEvent(PushEventMethods.onLiveActivityToken, payload);
      await h.sendEvent(PushEventMethods.onLiveActivityToken, payload);

      expect(h.registered, hasLength(1));
    });

    test('a failed registration is retried on the next delivery', () async {
      final LiveActivityHarness h = LiveActivityHarness(throwOnRegister: true);
      await h.service.initialize();
      final Map<String, Object?> payload = <String, Object?>{
        'token': 'upd-1',
        'kind': 'update',
        'incident_id': 'inc-1',
      };

      await h.sendEvent(PushEventMethods.onLiveActivityToken, payload);
      h.throwOnRegister = false;
      await h.sendEvent(PushEventMethods.onLiveActivityToken, payload);

      expect(h.registered, hasLength(1));
    });

    test('an ended activity removes its token from the server', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();
      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'upd-1',
        'kind': 'update',
        'incident_id': 'inc-1',
      });

      await h.sendEvent(PushEventMethods.onLiveActivityEnded, <String, Object?>{
        'token': 'upd-1',
        'incident_id': 'inc-1',
      });

      expect(h.removed, <String>['upd-1']);
    });

    test('an ended activity without a token removes nothing', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onLiveActivityEnded, <String, Object?>{
        'incident_id': 'inc-1',
      });
      await h.sendEvent(PushEventMethods.onLiveActivityEnded);

      expect(h.removed, isEmpty);
    });

    test('a failed removal never escapes', () async {
      final LiveActivityHarness h = LiveActivityHarness(throwOnRegister: true);
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onLiveActivityEnded, <String, Object?>{
        'token': 'upd-1',
      });

      expect(h.removed, isEmpty);
    });

    test(
      'initialize pulls tokens the native host saw before Dart listened',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(PushChannels.token), (
              MethodCall call,
            ) async {
              if (call.method == PushTokenMethods.getLiveActivityTokens) {
                return <Object?>[
                  <Object?, Object?>{'token': 'pts-1', 'kind': 'push_to_start'},
                  <Object?, Object?>{
                    'token': 'upd-1',
                    'kind': 'update',
                    'incident_id': 'inc-1',
                    'expires_in_seconds': 43200,
                  },
                  'garbage',
                ];
              }
              return null;
            });
        final LiveActivityHarness h = LiveActivityHarness();

        await h.service.initialize();

        expect(
          h.registered.map((LiveActivityRegisterRequest r) => r.token),
          <String>['pts-1', 'upd-1'],
        );
      },
    );

    test('an update token is never posted while signed out', () async {
      final LiveActivityHarness h = LiveActivityHarness(signedIn: false);
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'upd-1',
        'kind': 'update',
        'incident_id': 'inc-1',
      });

      expect(h.attempts, isEmpty);
    });

    test('a new session posts the update token again', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();
      final Map<String, Object?> payload = <String, Object?>{
        'token': 'upd-1',
        'kind': 'update',
        'incident_id': 'inc-1',
      };
      await h.sendEvent(PushEventMethods.onLiveActivityToken, payload);

      await h.signOut();
      await h.signIn();
      await h.sendEvent(PushEventMethods.onLiveActivityToken, payload);

      expect(h.registered, hasLength(2));
    });
  });
}
