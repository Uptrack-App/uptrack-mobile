import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/push/push_channels.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/push/push_service.dart';

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

/// Fake [LocalNotifier] recording foreground displays and taps.
class FakeNotifier implements LocalNotifier {
  PushMessage? shown;
  PushMessage? initial;
  void Function(PushMessage message)? onTap;

  @override
  Future<void> initialize({
    required void Function(PushMessage message) onTap,
  }) async {
    this.onTap = onTap;
  }

  @override
  Future<void> showForeground(PushMessage message) async {
    shown = message;
  }

  @override
  Future<PushMessage?> initialNotification() async => initial;
}

class RegisteredToken {
  const RegisteredToken({
    required this.platform,
    required this.token,
    this.environment,
  });

  final String platform;
  final String token;
  final String? environment;
}

class PushHarness {
  PushHarness({TargetPlatform? platform})
    : notifier = FakeNotifier(),
      navigated = <String>[],
      registered = <RegisteredToken>[] {
    service = PushService(
      registerToken:
          ({
            required String platform,
            required String token,
            String? environment,
          }) async {
            registered.add(
              RegisteredToken(
                platform: platform,
                token: token,
                environment: environment,
              ),
            );
          },
      onNavigate: navigated.add,
      events: const MethodChannel(PushChannels.events),
      tokenChannel: const MethodChannel(PushChannels.token),
      notifier: notifier,
      platform: platform,
    );
  }

  late final PushService service;
  final FakeNotifier notifier;
  final List<String> navigated;
  final List<RegisteredToken> registered;

  TestDefaultBinaryMessenger get messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Mocks the native host behind [PushChannels.token].
  void mockTokenHost(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(
      const MethodChannel(PushChannels.token),
      handler,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel(PushChannels.token),
        null,
      ),
    );
  }

  /// Simulates one Swift/Kotlin → Dart call on [PushChannels.events].
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

  group('PushMessage', () {
    test('parses a full payload', () {
      final PushMessage? message = PushMessage.fromMap(<Object?, Object?>{
        'title': 'P1: api down',
        'body': 'Down for 2m',
        'incident_id': 'inc-1',
        'monitor_id': 'mon-1',
        'severity': 'p1',
        'collapse_key': 'inc-1',
      });
      expect(message, isNotNull);
      expect(message!.title, 'P1: api down');
      expect(message.routeLocation, '/incidents/inc-1');
      expect(message.isHighPriority, isTrue);
    });

    test('monitor-only payload routes to the monitor', () {
      final PushMessage? message = PushMessage.fromMap(<Object?, Object?>{
        'monitor_id': 'mon-9',
        'severity': 'p3',
      });
      expect(message!.routeLocation, '/monitors/mon-9');
      expect(message.isHighPriority, isFalse);
    });

    test('null map and payload without ids have no route', () {
      expect(PushMessage.fromMap(null), isNull);
      final PushMessage? message = PushMessage.fromMap(<Object?, Object?>{
        'title': 'hello',
      });
      expect(message!.routeLocation, isNull);
      expect(message.isHighPriority, isFalse);
    });

    test('non-string values are ignored', () {
      final PushMessage? message = PushMessage.fromMap(<Object?, Object?>{
        'incident_id': 42,
        'title': '',
      });
      expect(message!.incidentId, isNull);
      expect(message.title, isNull);
    });

    test('notification id is stable per collapse key', () {
      PushMessage msg(String key) => PushMessage(collapseKey: key);
      expect(msg('a').notificationId, msg('a').notificationId);
    });

    test('round-trips through toMap', () {
      const PushMessage original = PushMessage(
        title: 't',
        incidentId: 'inc-1',
        severity: 'p2',
      );
      final PushMessage? back = PushMessage.fromMap(original.toMap());
      expect(back!.title, 't');
      expect(back.routeLocation, '/incidents/inc-1');
      expect(back.isHighPriority, isTrue);
    });
  });

  group('registerPushDevice', () {
    test('POSTs platform/token/environment/app_version', () async {
      Map<String, Object?>? seenBody;
      String? seenPath;
      String? seenMethod;
      final FakeAdapter adapter = FakeAdapter((RequestOptions options) async {
        seenPath = options.path;
        seenMethod = options.method;
        final Object? data = options.data;
        seenBody = (data! as Map).cast<String, Object?>();
        return jsonResponse(<String, Object?>{});
      });
      final Dio dio = Dio()..httpClientAdapter = adapter;
      dio.options.baseUrl = 'http://localhost:4000';
      final UptrackApi api = UptrackApi(dio: dio);

      await api.registerPushDevice(
        platform: 'ios',
        token: 'apns-token',
        environment: 'sandbox',
        appVersion: '1.0.0',
      );

      expect(seenMethod, 'POST');
      expect(seenPath, kPushDevicesPath);
      expect(seenBody, <String, Object?>{
        'platform': 'ios',
        'token': 'apns-token',
        'environment': 'sandbox',
        'app_version': '1.0.0',
      });
    });

    test('omits null optionals', () async {
      Map<String, Object?>? seenBody;
      final FakeAdapter adapter = FakeAdapter((RequestOptions options) async {
        final Object? data = options.data;
        seenBody = (data! as Map).cast<String, Object?>();
        return jsonResponse(<String, Object?>{});
      });
      final Dio dio = Dio()..httpClientAdapter = adapter;
      dio.options.baseUrl = 'http://localhost:4000';

      await UptrackApi(dio: dio)
          .registerPushDevice(platform: 'android', token: 'fcm-token');

      expect(seenBody, <String, Object?>{
        'platform': 'android',
        'token': 'fcm-token',
      });
    });
  });

  group('PushService', () {
    test(
      'initialize registers the current token + drains a cold-start tap',
      () async {
        final PushHarness h = PushHarness();
        h.mockTokenHost((MethodCall call) async {
          switch (call.method) {
            case PushTokenMethods.getToken:
              return <String, Object?>{
                'token': 'native-token',
                'platform': 'ios',
                'environment': 'sandbox',
              };
            case PushTokenMethods.getInitialNotification:
              return <String, Object?>{'incident_id': 'inc-7'};
          }
          return null;
        });

        await h.service.initialize();

        expect(h.service.isInitialized, isTrue);
        expect(h.registered, hasLength(1));
        expect(h.registered.single.platform, 'ios');
        expect(h.registered.single.token, 'native-token');
        expect(h.registered.single.environment, 'sandbox');
        // Killed-state tap deep-links to the incident.
        expect(h.navigated, <String>['/incidents/inc-7']);
      },
    );

    test('initialize is idempotent', () async {
      final PushHarness h = PushHarness();
      h.mockTokenHost((MethodCall call) async {
        if (call.method == PushTokenMethods.getToken) {
          return <String, Object?>{'token': 't', 'platform': 'android'};
        }
        return null;
      });

      await h.service.initialize();
      await h.service.initialize();

      expect(h.registered, hasLength(1));
    });

    test('falls back to the local-notification launch details', () async {
      final PushHarness h = PushHarness();
      h.mockTokenHost((_) async => null);
      h.notifier.initial = const PushMessage(monitorId: 'mon-3');

      await h.service.initialize();

      expect(h.navigated, <String>['/monitors/mon-3']);
    });

    test('degrades gracefully without a native host (pre-T028)', () async {
      final PushHarness h = PushHarness();
      // No mock: invokeMethod throws MissingPluginException.

      await h.service.initialize();

      expect(h.service.isInitialized, isTrue);
      expect(h.registered, isEmpty);
      expect(h.navigated, isEmpty);
    });

    test('foreground message shows a local notification', () async {
      final PushHarness h = PushHarness();
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onForegroundMessage, <String, Object?>{
        'title': 'P1: api down',
        'body': 'Down for 2m',
        'incident_id': 'inc-1',
        'severity': 'p1',
      });

      expect(h.notifier.shown, isNotNull);
      expect(h.notifier.shown!.routeLocation, '/incidents/inc-1');
      // Foreground display does not navigate by itself.
      expect(h.navigated, isEmpty);
    });

    test('background tap navigates; tap without ids does nothing', () async {
      final PushHarness h = PushHarness();
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onNotificationTap, <String, Object?>{
        'incident_id': 'inc-2',
      });
      await h.sendEvent(PushEventMethods.onNotificationTap, <String, Object?>{
        'title': 'no ids',
      });

      expect(h.navigated, <String>['/incidents/inc-2']);
    });

    test('local-notification tap navigates (all app states)', () async {
      final PushHarness h = PushHarness();
      await h.service.initialize();

      h.notifier.onTap?.call(const PushMessage(monitorId: 'mon-5'));

      expect(h.navigated, <String>['/monitors/mon-5']);
    });

    test('token refresh re-registers via the service', () async {
      final PushHarness h = PushHarness(platform: TargetPlatform.iOS);
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onTokenRefresh, <String, Object?>{
        'token': 'rotated-token',
      });

      expect(h.registered, hasLength(1));
      expect(h.registered.single.platform, 'ios');
      expect(h.registered.single.token, 'rotated-token');
    });

    test('onPushToken with unsupported platform does not register', () async {
      final PushHarness h = PushHarness();
      await h.service.initialize();

      await h.sendEvent(PushEventMethods.onPushToken, <String, Object?>{
        'token': 'desktop-token',
        'platform': 'macos',
      });

      expect(h.registered, isEmpty);
    });

    test('unknown methods and empty payloads are ignored', () async {
      final PushHarness h = PushHarness();
      await h.service.initialize();

      await h.sendEvent('futureMethodFromT028', <String, Object?>{});
      await h.sendEvent(PushEventMethods.onTokenRefresh, <String, Object?>{});

      expect(h.registered, isEmpty);
      expect(h.navigated, isEmpty);
      expect(h.notifier.shown, isNull);
    });
  });
}
