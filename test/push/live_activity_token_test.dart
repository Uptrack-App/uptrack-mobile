import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/push/push_channels.dart';
import 'package:uptrack_mobile/push/push_message.dart';
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
  LiveActivityHarness({this.throwOnRegister = false}) {
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
      registerLiveActivity: (LiveActivityRegisterRequest request) async {
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
  final List<LiveActivityRegisterRequest> registered =
      <LiveActivityRegisterRequest>[];
  final List<String> removed = <String>[];
  bool throwOnRegister;

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('onLiveActivityToken', () {
    test('scoped token registers immediately with exact fields', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'la-token-1',
        'kind': 'push_to_start',
        'incident_id': 'inc-1',
      });

      expect(h.registered, hasLength(1));
      final LiveActivityRegisterRequest request = h.registered.single;
      expect(request.token, 'la-token-1');
      expect(request.kind, 'push_to_start');
      expect(request.incidentId, 'inc-1');
      expect(h.service.pendingLiveActivityToken, isNull);
    });

    test('kind defaults to push_to_start when omitted', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'la-token-2',
        'incident_id': 'inc-2',
      });

      expect(h.registered, hasLength(1));
      expect(h.registered.single.kind, 'push_to_start');
    });

    test(
      'unscoped push_to_start parks until a foreground push names an incident',
      () async {
        final LiveActivityHarness h = LiveActivityHarness();
        await h.service.initialize();

        // Native bootstrap shape (T055): no incident_id yet.
        await h.sendEvent(
          PushEventMethods.onLiveActivityToken,
          <String, Object?>{'token': 'la-bootstrap', 'kind': 'push_to_start'},
        );

        expect(h.registered, isEmpty);
        expect(h.service.pendingLiveActivityToken?.token, 'la-bootstrap');

        // A push without an incident id does not flush.
        await h.sendEvent(
          PushEventMethods.onForegroundMessage,
          <String, Object?>{'title': 'no ids'},
        );
        expect(h.registered, isEmpty);

        // The next incident push flushes the parked token once.
        await h.sendEvent(
          PushEventMethods.onForegroundMessage,
          <String, Object?>{'title': 'P1: api down', 'incident_id': 'inc-9'},
        );

        expect(h.registered, hasLength(1));
        expect(h.registered.single.token, 'la-bootstrap');
        expect(h.registered.single.incidentId, 'inc-9');
        expect(h.registered.single.kind, 'push_to_start');
        expect(h.service.pendingLiveActivityToken, isNull);
      },
    );

    test('parked token also flushes on notification tap', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'la-bootstrap',
      });
      await h.sendEvent(PushEventMethods.onNotificationTap, <String, Object?>{
        'incident_id': 'inc-3',
      });

      expect(h.registered, hasLength(1));
      expect(h.registered.single.incidentId, 'inc-3');
      expect(h.service.pendingLiveActivityToken, isNull);
    });

    test('malformed payloads register nothing and park nothing', () async {
      final LiveActivityHarness h = LiveActivityHarness();
      await h.service.initialize();

      // Missing token.
      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'kind': 'push_to_start',
        'incident_id': 'inc-1',
      });
      // Unknown kind with an incident (fails server validation).
      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'la-x',
        'kind': 'bogus',
        'incident_id': 'inc-1',
      });
      // TTL outside the server 60s..7d bounds.
      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'la-y',
        'kind': 'push_to_start',
        'incident_id': 'inc-1',
        'expires_in_seconds': 5,
      });
      // Unscoped `update` token: no incident to refresh, dropped not parked.
      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'la-z',
        'kind': 'update',
      });

      expect(h.registered, isEmpty);
      expect(h.service.pendingLiveActivityToken, isNull);
    });

    test('registration failure is best-effort (no crash)', () async {
      final LiveActivityHarness h = LiveActivityHarness(throwOnRegister: true);
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'la-token',
        'incident_id': 'inc-1',
      });

      expect(h.registered, isEmpty);
      expect(h.service.pendingLiveActivityToken, isNull);
    });

    test('unwired service drops the token without crashing', () async {
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
      final TestDefaultBinaryMessenger messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Future<void> send(String method, [Map<String, Object?>? args]) {
        final ByteData message = const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, args),
        );
        return messenger.handlePlatformMessage(
          PushChannels.events,
          message,
          (_) {},
        );
      }

      await send(PushEventMethods.onLiveActivityToken, <String, Object?>{
        'token': 'la-token',
        'incident_id': 'inc-1',
      });
    });
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
      });

      final LiveActivityRegisterRequest request = h.registered.single;
      expect(request.kind, 'update');
      expect(request.incidentId, 'inc-1');
      expect(request.expiresInSeconds, 43200);
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

        expect(h.registered.single.token, 'upd-1');
        expect(h.service.pendingLiveActivityToken?.token, 'pts-1');
      },
    );
  });
}
