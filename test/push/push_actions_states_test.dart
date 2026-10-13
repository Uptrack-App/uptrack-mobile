import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/app.dart' show routerProvider;
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/database_providers.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/push/push_actions.dart';
import 'package:uptrack_mobile/push/push_channels.dart';
import 'package:uptrack_mobile/push/push_providers.dart';

/// Plan item 4.6: lock-screen actions (Acknowledge / Escalate / Snooze) in
/// every app state, with the real providers, the real plugin channel and a
/// fake server that requires the device-token bearer.

const String _plugin = 'dexterous.com/flutter/local_notifications';
const String _incident = '5f0c1c9e-0000-4000-8000-000000000001';

Map<String, Object?> _incidentDetail() => <String, Object?>{
  'data': <String, Object?>{
    'incident': <String, Object?>{
      'id': _incident,
      'monitor_id': 'mon-1',
      'monitor_name': 'DB primary',
      'status': 'open',
      'started_at': '2026-09-26T00:00:00Z',
      'resolved_at': null,
      'acknowledged_at': '2026-09-26T00:01:00Z',
      'inserted_at': '2026-09-26T00:00:00Z',
    },
    'updates': <Object?>[],
  },
};

class _Server implements HttpClientAdapter {
  final List<String> calls = <String>[];
  final List<String> unauthorized = <String>[];

  /// Transport failures to throw before answering (offline).
  int dropNext = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String key = '${options.method} ${options.path}';
    if (dropNext > 0) {
      dropNext--;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: const SocketException('Network is unreachable'),
      );
    }
    if (options.headers['Authorization'] != 'Bearer udt_stored') {
      unauthorized.add(key);
      return _json(<String, Object?>{'error': 'Unauthorized'}, 401);
    }
    calls.add(key);
    return _json(<String, Object?>{
      ..._incidentDetail(),
      'escalated': true,
      'snoozed_until': '2026-09-26T01:00:00Z',
    });
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, Object?> body, [int status = 200]) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );
}

/// Secure storage whose read waits like a real cold start.
class _Store implements TokenStore {
  _Store({required this.token});

  final String? token;
  final Completer<void> unblock = Completer<void>();

  @override
  Future<String?> readDeviceToken() async {
    await unblock.future;
    return token;
  }

  @override
  Future<String?> readDeviceTokenId() async => 'dt-1';

  @override
  Future<void> writeDeviceToken({
    required String token,
    required String id,
  }) async {}

  @override
  Future<void> clear() async {}
}

class _Router extends Fake implements GoRouter {
  final List<String> gone = <String>[];

  @override
  void go(String location, {Object? extra}) => gone.add(location);

  @override
  void dispose() {}
}

class _App {
  _App({String? storedToken = 'udt_stored', this.initial}) {
    store = _Store(token: storedToken);
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel(_plugin), (
      MethodCall call,
    ) async {
      return call.method == 'getNotificationAppLaunchDetails' ? null : true;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel(PushChannels.token),
      (MethodCall call) async =>
          call.method == PushTokenMethods.getInitialNotification
          ? initial
          : null,
    );
    final AuthTokenHolder holder = AuthTokenHolder();
    container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(store),
        authTokenHolderProvider.overrideWithValue(holder),
        dioProvider.overrideWithValue(
          buildAppDio(holder: holder, onUnauthorized: () {}, adapter: server),
        ),
        appDatabaseProvider.overrideWithValue(
          AppDatabase.forTesting(NativeDatabase.memory()),
        ),
        routerProvider.overrideWith((Ref ref) => router),
        pushActionRetryDelaysProvider.overrideWithValue(const <Duration>[
          Duration.zero,
          Duration.zero,
        ]),
      ],
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(const MethodChannel(_plugin), null);
      messenger.setMockMethodCallHandler(
        const MethodChannel(PushChannels.token),
        null,
      );
      container.read(appDatabaseProvider).close();
      container.dispose();
    });
  }

  final Map<String, Object?>? initial;
  final _Server server = _Server();
  final _Router router = _Router();
  late final _Store store;
  late final ProviderContainer container;

  /// App start: auth restore begins, push initializes (as `UptrackApp`).
  Future<void> start() async {
    container.read(authControllerProvider);
    container.read(pushAuthBindingProvider);
    await container.read(pushServiceProvider).initialize();
  }

  Future<void> restore() async {
    store.unblock.complete();
    await pumpEventQueue();
  }
}

/// The plugin's `didReceiveNotificationResponse`, as Android sends it when an
/// action button on a notification the Dart renderer showed is tapped.
Future<void> _pluginActionTap(String actionId) {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _plugin,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('didReceiveNotificationResponse', <String, Object?>{
            'notificationId': 1,
            'actionId': actionId,
            'input': null,
            'payload': jsonEncode(<String, String>{
              'incident_id': _incident,
              'severity': 'p1',
            }),
            'notificationResponseType':
                NotificationResponseType.selectedNotificationAction.index,
          }),
        ),
        (_) {},
      );
}

Future<void> _nativeEvent(String method, Map<String, Object?> args) {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        PushChannels.events,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TargetPlatform? previous;

  setUp(() {
    previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });

  tearDown(() => debugDefaultTargetPlatformOverride = previous);

  group('Android: plugin notification responses are not trusted', () {
    // flutter_local_notifications reads its responses from intents sent to
    // the exported launcher activity (action SELECT_FOREGROUND_NOTIFICATION_
    // ACTION + extras). Any app can send that intent, so a plugin response
    // must never run a triage call. Android action buttons go through the
    // non-exported UptrackActionActivity instead (push_action_origin_test).
    test('a forged plugin action response runs no API call', () async {
      final _App app = _App();
      await app.start();
      await app.restore();

      await _pluginActionTap(PushIntentIdentity.acknowledge);
      await _pluginActionTap(PushIntentIdentity.escalate);
      await _pluginActionTap(PushIntentIdentity.snooze);
      await pumpEventQueue();

      expect(app.server.calls, isEmpty);
      expect(app.server.unauthorized, isEmpty);
    });
  });

  group('killed state: the action that launched the app', () {
    test(
      'iOS/Android native cold start runs the action after restore',
      () async {
        final _App app = _App(
          initial: <String, Object?>{
            'action': 'UPTRACK_ACK',
            'incident_id': _incident,
          },
        );
        final Future<void> started = app.start();
        await pumpEventQueue();
        expect(
          app.server.unauthorized,
          isEmpty,
          reason: 'no API call may run before the stored session is restored',
        );

        await app.restore();
        await started;
        await pumpEventQueue();

        expect(
          app.server.calls,
          contains('POST /api/incidents/$_incident/acknowledge'),
        );
        expect(app.server.unauthorized, isEmpty);
        expect(app.router.gone, <String>['/incidents/$_incident']);
      },
    );

    test(
      'signed out: nothing runs, the incident opens after sign-in',
      () async {
        final _App app = _App(
          storedToken: null,
          initial: <String, Object?>{
            'action': 'UPTRACK_ESCALATE',
            'incident_id': _incident,
          },
        );
        final Future<void> started = app.start();
        await app.restore();
        await started;
        await pumpEventQueue();

        expect(app.server.calls, isEmpty);
        expect(app.server.unauthorized, isEmpty);
        expect(
          app.router.gone,
          isEmpty,
          reason: 'parked until a session exists',
        );
      },
    );
  });

  group('background state: a live action event', () {
    test('an action before the restore waits for the session', () async {
      final _App app = _App();
      await app.start();

      final Future<void> tap = _nativeEvent(
        PushEventMethods.onNotificationAction,
        <String, Object?>{'action': 'UPTRACK_SNOOZE', 'incident_id': _incident},
      );
      await pumpEventQueue();
      expect(app.server.unauthorized, isEmpty);

      await app.restore();
      await tap;
      await pumpEventQueue();

      expect(app.server.calls, contains('POST /api/monitors/mon-1/snooze'));
    });
  });

  group('offline', () {
    test('a transport failure is retried, then the action runs', () async {
      final _App app = _App();
      await app.start();
      await app.restore();
      app.server.dropNext = 2;

      await _nativeEvent(
        PushEventMethods.onNotificationAction,
        <String, Object?>{'action': 'UPTRACK_ACK', 'incident_id': _incident},
      );
      await pumpEventQueue();

      expect(app.server.calls, <String>[
        'POST /api/incidents/$_incident/acknowledge',
      ]);
    });
  });

  group('PushActionHandler retry policy', () {
    Dio dio(List<String> seen, List<Object> answers) {
      final Dio d = Dio()..options.baseUrl = 'http://localhost:4000';
      d.httpClientAdapter = _ScriptedAdapter(seen, answers);
      return d;
    }

    Future<PushActionOutcome> run(
      PushAction action,
      List<String> seen,
      List<Object> answers,
      List<String> navigated,
    ) {
      return PushActionHandler(
        api: UptrackApi(dio: dio(seen, answers)),
        onNavigate: navigated.add,
        retryDelays: const <Duration>[Duration.zero, Duration.zero],
      ).handle(PushActionRequest(action: action, incidentId: _incident));
    }

    test('still offline after every retry: failed + deep link', () async {
      final List<String> seen = <String>[];
      final List<String> navigated = <String>[];
      final PushActionOutcome outcome = await run(
        PushAction.acknowledge,
        seen,
        <Object>[
          DioExceptionType.connectionError,
          DioExceptionType.connectionError,
          DioExceptionType.connectionError,
          DioExceptionType.connectionError,
        ],
        navigated,
      );
      expect(outcome, PushActionOutcome.failed);
      expect(seen, hasLength(3), reason: 'one try plus two retries');
      expect(navigated, <String>['/incidents/$_incident']);
    });

    test('an HTTP error is not retried', () async {
      final List<String> seen = <String>[];
      final PushActionOutcome outcome = await run(
        PushAction.acknowledge,
        seen,
        <Object>[409],
        <String>[],
      );
      expect(outcome, PushActionOutcome.failed);
      expect(seen, hasLength(1));
    });

    test('a timeout after sending is not retried (escalate is not '
        'idempotent)', () async {
      final List<String> seen = <String>[];
      final PushActionOutcome outcome = await run(
        PushAction.escalate,
        seen,
        <Object>[DioExceptionType.receiveTimeout, 200],
        <String>[],
      );
      expect(outcome, PushActionOutcome.failed);
      expect(seen, hasLength(1));
    });

    test('401 is not retried and reports authExpired', () async {
      final List<String> seen = <String>[];
      final PushActionOutcome outcome = await run(
        PushAction.acknowledge,
        seen,
        <Object>[401],
        <String>[],
      );
      expect(outcome, PushActionOutcome.authExpired);
      expect(seen, hasLength(1));
    });
  });

  group('native hosts', () {
    final String swift = File('ios/Runner/AppDelegate.swift')
        .readAsStringSync();
    final String activity = File(
      'android/app/src/main/kotlin/app/uptrack/uptrack_mobile/MainActivity.kt',
    ).readAsStringSync();

    test('iOS actions open the app so Dart runs (killed state, scenes)', () {
      // A background action in the killed state connects no UIScene, so the
      // implicit Flutter engine never runs Dart and the action is lost.
      for (final String id in <String>[
        'ackActionId',
        'escalateActionId',
        'snoozeActionId',
      ]) {
        expect(
          swift,
          matches(
            RegExp(
              'identifier: $id, title: "[^"]+",\\s*options: \\[\\.foreground\\]',
            ),
          ),
          reason: '$id must use .foreground',
        );
      }
    });

    test('iOS keeps the action of a tap that arrives before Dart is ready', () {
      expect(
        swift,
        isNot(contains('tapOnly(')),
        reason: 'the action was stripped',
      );
      expect(swift, contains('dartReady'));
      expect(
        swift,
        isNot(
          contains(
            'events.invokeMethod("onNotificationTap", arguments: pending)',
          ),
        ),
        reason: 'replaying the buffer and draining it runs a tap twice',
      );
    });

    test('Android hands trampoline actions to Dart as actions', () {
      // Cold start: onCreate keeps it for getInitialNotification. Warm:
      // onNewIntent sends onNotificationAction. The action never comes from
      // MainActivity's own (exported) intent (push_action_origin_test).
      expect(activity, contains('pendingTap = PushActionInbox.take()'));
      expect(activity, contains('"onNotificationAction"'));
      expect(
        activity,
        contains('if (payload.containsKey("action")) METHOD_ACTION'),
      );
    });
  });
}

/// Answers each request with the next scripted item: an HTTP status (int) or
/// a transport failure ([DioExceptionType]).
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.seen, this.answers);

  final List<String> seen;
  final List<Object> answers;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add('${options.method} ${options.path}');
    final Object answer = answers.isEmpty ? 200 : answers.removeAt(0);
    if (answer is DioExceptionType) {
      throw DioException(requestOptions: options, type: answer);
    }
    final int status = answer as int;
    if (status != 200) {
      return _json(<String, Object?>{'error': 'nope'}, status);
    }
    return _json(<String, Object?>{
      ..._incidentDetail(),
      'escalated': true,
      'snoozed_until': '2026-09-26T01:00:00Z',
    });
  }

  @override
  void close({bool force = false}) {}
}
