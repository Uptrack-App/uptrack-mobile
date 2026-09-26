import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/push/push_actions.dart';
import 'package:uptrack_mobile/push/push_channels.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/push/push_service.dart';

/// Fake [HttpClientAdapter] returning canned JSON without network access
/// (same pattern as `test/push/push_test.dart`).
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

Dio dioWithFake(Future<ResponseBody> Function(RequestOptions options) handler) {
  final Dio dio = Dio()..httpClientAdapter = FakeAdapter(handler);
  dio.options.baseUrl = 'http://localhost:4000';
  return dio;
}

Map<String, Object?> incidentDetailFixture({
  String incidentId = 'inc-1',
  String monitorId = 'mon-1',
  String? acknowledgedAt,
}) => <String, Object?>{
  'data': <String, Object?>{
    'incident': <String, Object?>{
      'id': incidentId,
      'monitor_id': monitorId,
      'monitor_name': 'Homepage',
      'status': 'open',
      'started_at': '2026-09-26T00:00:00Z',
      'resolved_at': null,
      'acknowledged_at': acknowledgedAt,
      'inserted_at': '2026-09-26T00:00:00Z',
    },
    'updates': <Object?>[],
  },
};

/// Records navigations and builds a handler over a fake [Dio].
class ActionHarness {
  ActionHarness({required Dio dio}) : navigated = <String>[] {
    handler = PushActionHandler(
      api: UptrackApi(dio: dio),
      onNavigate: navigated.add,
    );
  }

  final List<String> navigated;
  late final PushActionHandler handler;
}

void main() {
  group('triage API calls', () {
    test('escalateIncident POSTs the exact T030 path and parses', () async {
      RequestOptions? seen;
      final Dio dio = dioWithFake((RequestOptions options) async {
        seen = options;
        return jsonResponse(<String, Object?>{
          'ok': true,
          'escalated': true,
          'steps_fired': 2,
        });
      });

      final EscalateResult res = await UptrackApi(dio: dio)
          .escalateIncident('inc-1');

      expect(seen?.method, 'POST');
      expect(seen?.path, '/api/incidents/inc-1/escalate');
      expect(res.escalated, isTrue);
      expect(res.stepsFired, 2);
    });

    test('snoozeMonitor POSTs the exact T030 path and parses', () async {
      RequestOptions? seen;
      final Dio dio = dioWithFake((RequestOptions options) async {
        seen = options;
        return jsonResponse(<String, Object?>{
          'ok': true,
          'snoozed_until': '2026-09-26T01:00:00Z',
        });
      });

      final SnoozeResult res = await UptrackApi(dio: dio)
          .snoozeMonitor('mon-1');

      expect(seen?.method, 'POST');
      expect(seen?.path, '/api/monitors/mon-1/snooze');
      expect(res.snoozedUntil, '2026-09-26T01:00:00Z');
    });
  });

  group('PushActionRequest', () {
    test('parses native and lowercase action ids', () {
      expect(PushAction.parse('UPTRACK_ACK'), PushAction.acknowledge);
      expect(PushAction.parse('acknowledge'), PushAction.acknowledge);
      expect(PushAction.parse('UPTRACK_ESCALATE'), PushAction.escalate);
      expect(PushAction.parse('escalate'), PushAction.escalate);
      expect(PushAction.parse('UPTRACK_SNOOZE'), PushAction.snooze);
      expect(PushAction.parse('snooze'), PushAction.snooze);
    });

    test('unknown ids and null maps parse to null', () {
      expect(PushAction.parse('UPTRACK_FUTURE'), isNull);
      expect(PushAction.parse(null), isNull);
      expect(PushAction.parse(''), isNull);
      expect(PushActionRequest.fromMap(null), isNull);
      expect(
        PushActionRequest.fromMap(<Object?, Object?>{'action': 'nope'}),
        isNull,
      );
      expect(PushActionRequest.fromMap(<Object?, Object?>{}), isNull);
    });

    test('incident detail wins the route fallback', () {
      const PushActionRequest both = PushActionRequest(
        action: PushAction.escalate,
        incidentId: 'inc-1',
        monitorId: 'mon-1',
      );
      expect(both.routeLocation, '/incidents/inc-1');
      const PushActionRequest monitorOnly = PushActionRequest(
        action: PushAction.snooze,
        monitorId: 'mon-1',
      );
      expect(monitorOnly.routeLocation, '/monitors/mon-1');
      const PushActionRequest bare = PushActionRequest(
        action: PushAction.acknowledge,
      );
      expect(bare.routeLocation, isNull);
    });
  });

  group('PushActionHandler', () {
    test('acknowledge calls the endpoint then deep-links', () async {
      final List<String> paths = <String>[];
      final Dio dio = dioWithFake((RequestOptions options) async {
        paths.add('${options.method} ${options.path}');
        return jsonResponse(incidentDetailFixture());
      });
      final ActionHarness h = ActionHarness(dio: dio);

      final PushActionOutcome outcome = await h.handler.handle(
        const PushActionRequest(
          action: PushAction.acknowledge,
          incidentId: 'inc-1',
        ),
      );

      expect(outcome, PushActionOutcome.performed);
      expect(paths, <String>['POST /api/incidents/inc-1/acknowledge']);
      expect(h.navigated, <String>['/incidents/inc-1']);
    });

    test('escalate calls the T030 endpoint then deep-links', () async {
      final List<String> paths = <String>[];
      final Dio dio = dioWithFake((RequestOptions options) async {
        paths.add('${options.method} ${options.path}');
        return jsonResponse(<String, Object?>{
          'ok': true,
          'escalated': true,
          'steps_fired': 1,
        });
      });
      final ActionHarness h = ActionHarness(dio: dio);

      final PushActionOutcome outcome = await h.handler.handle(
        const PushActionRequest(
          action: PushAction.escalate,
          incidentId: 'inc-1',
        ),
      );

      expect(outcome, PushActionOutcome.performed);
      expect(paths, <String>['POST /api/incidents/inc-1/escalate']);
      expect(h.navigated, <String>['/incidents/inc-1']);
    });

    test('snooze with a monitor id calls the T030 endpoint', () async {
      final List<String> paths = <String>[];
      final Dio dio = dioWithFake((RequestOptions options) async {
        paths.add('${options.method} ${options.path}');
        return jsonResponse(<String, Object?>{
          'ok': true,
          'snoozed_until': '2026-09-26T01:00:00Z',
        });
      });
      final ActionHarness h = ActionHarness(dio: dio);

      final PushActionOutcome outcome = await h.handler.handle(
        const PushActionRequest(
          action: PushAction.snooze,
          incidentId: 'inc-1',
          monitorId: 'mon-1',
        ),
      );

      expect(outcome, PushActionOutcome.performed);
      expect(paths, <String>['POST /api/monitors/mon-1/snooze']);
      expect(h.navigated, <String>['/incidents/inc-1']);
    });

    test(
      'snooze with only an incident id resolves the monitor first',
      () async {
        final List<String> paths = <String>[];
        final Dio dio = dioWithFake((RequestOptions options) async {
          paths.add('${options.method} ${options.path}');
          if (options.method == 'GET') {
            return jsonResponse(incidentDetailFixture());
          }
          return jsonResponse(<String, Object?>{
            'ok': true,
            'snoozed_until': '2026-09-26T01:00:00Z',
          });
        });
        final ActionHarness h = ActionHarness(dio: dio);

        final PushActionOutcome outcome = await h.handler.handle(
          const PushActionRequest(
            action: PushAction.snooze,
            incidentId: 'inc-1',
          ),
        );

        expect(outcome, PushActionOutcome.performed);
        expect(paths, <String>[
          'GET /api/incidents/inc-1',
          'POST /api/monitors/mon-1/snooze',
        ]);
        expect(h.navigated, <String>['/incidents/inc-1']);
      },
    );

    test('401 drops the action and deep-links for manual retry', () async {
      final Dio dio = dioWithFake((RequestOptions options) async {
        return jsonResponse(<String, Object?>{'error': 'unauthorized'}, 401);
      });
      final ActionHarness h = ActionHarness(dio: dio);

      final PushActionOutcome outcome = await h.handler.handle(
        const PushActionRequest(
          action: PushAction.escalate,
          incidentId: 'inc-1',
        ),
      );

      expect(outcome, PushActionOutcome.authExpired);
      expect(h.navigated, <String>['/incidents/inc-1']);
    });

    test('non-401 errors deep-link and report failed', () async {
      final Dio dio = dioWithFake((RequestOptions options) async {
        return jsonResponse(<String, Object?>{'error': 'boom'}, 500);
      });
      final ActionHarness h = ActionHarness(dio: dio);

      final PushActionOutcome outcome = await h.handler.handle(
        const PushActionRequest(
          action: PushAction.acknowledge,
          incidentId: 'inc-1',
        ),
      );

      expect(outcome, PushActionOutcome.failed);
      expect(h.navigated, <String>['/incidents/inc-1']);
    });

    test('missing ids are ignored without API calls', () async {
      int calls = 0;
      final Dio dio = dioWithFake((RequestOptions options) async {
        calls++;
        return jsonResponse(<String, Object?>{});
      });
      final ActionHarness h = ActionHarness(dio: dio);

      expect(
        await h.handler.handle(
          const PushActionRequest(action: PushAction.acknowledge),
        ),
        PushActionOutcome.ignored,
      );
      expect(
        await h.handler.handle(
          const PushActionRequest(action: PushAction.snooze),
        ),
        PushActionOutcome.ignored,
      );

      expect(calls, 0);
      expect(h.navigated, isEmpty);
    });
  });

  group('PushService action dispatch', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    TestDefaultBinaryMessenger testMessenger() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    Future<void> sendEvent(String method, [Map<String, Object?>? args]) {
      final ByteData message = const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, args),
      );
      return testMessenger().handlePlatformMessage(
        PushChannels.events,
        message,
        (_) {},
      );
    }

    PushService serviceWithHandler(
      Dio dio,
      List<String> navigated, {
      bool includeHandler = true,
    }) {
      return PushService(
        registerToken: ({
          required String platform,
          required String token,
          String? environment,
        }) async {},
        onNavigate: navigated.add,
        events: const MethodChannel(PushChannels.events),
        tokenChannel: const MethodChannel(PushChannels.token),
        notifier: _NoopNotifier(),
        actionHandler: includeHandler
            ? PushActionHandler(
                api: UptrackApi(dio: dio),
                onNavigate: navigated.add,
              )
            : null,
      );
    }

    test('onNotificationAction executes through the handler', () async {
      final List<String> paths = <String>[];
      final Dio dio = dioWithFake((RequestOptions options) async {
        paths.add('${options.method} ${options.path}');
        return jsonResponse(incidentDetailFixture());
      });
      final List<String> navigated = <String>[];
      final PushService service = serviceWithHandler(dio, navigated);
      await service.initialize();

      await sendEvent(PushEventMethods.onNotificationAction, <String, Object?>{
        'action': 'UPTRACK_ACK',
        'incident_id': 'inc-1',
      });

      expect(paths, <String>['POST /api/incidents/inc-1/acknowledge']);
      expect(navigated, <String>['/incidents/inc-1']);
    });

    test('all three actions plus the 401 path over the channel', () async {
      int escalateCalls = 0;
      final Dio dio = dioWithFake((RequestOptions options) async {
        if (options.path.endsWith('/escalate')) {
          escalateCalls++;
          return jsonResponse(<String, Object?>{'error': 'unauthorized'}, 401);
        }
        if (options.path.endsWith('/snooze')) {
          return jsonResponse(<String, Object?>{
            'ok': true,
            'snoozed_until': '2026-09-26T01:00:00Z',
          });
        }
        return jsonResponse(incidentDetailFixture());
      });
      final List<String> navigated = <String>[];
      final PushService service = serviceWithHandler(dio, navigated);
      await service.initialize();

      await sendEvent(PushEventMethods.onNotificationAction, <String, Object?>{
        'action': 'escalate',
        'incident_id': 'inc-9',
      });
      await sendEvent(PushEventMethods.onNotificationAction, <String, Object?>{
        'action': 'snooze',
        'incident_id': 'inc-9',
        'monitor_id': 'mon-9',
      });

      expect(escalateCalls, 1);
      // 401 escalate still deep-links; snooze performs then deep-links.
      expect(navigated, <String>['/incidents/inc-9', '/incidents/inc-9']);
    });

    test('unknown action ids are ignored', () async {
      int calls = 0;
      final Dio dio = dioWithFake((RequestOptions options) async {
        calls++;
        return jsonResponse(<String, Object?>{});
      });
      final List<String> navigated = <String>[];
      final PushService service = serviceWithHandler(dio, navigated);
      await service.initialize();

      await sendEvent(PushEventMethods.onNotificationAction, <String, Object?>{
        'action': 'UPTRACK_FUTURE',
        'incident_id': 'inc-1',
      });

      expect(calls, 0);
      expect(navigated, isEmpty);
    });

    test('without a handler the tap falls back to a deep-link', () async {
      final List<String> navigated = <String>[];
      final PushService bare = PushService(
        registerToken: ({
          required String platform,
          required String token,
          String? environment,
        }) async {},
        onNavigate: navigated.add,
        events: const MethodChannel(PushChannels.events),
        tokenChannel: const MethodChannel(PushChannels.token),
        notifier: _NoopNotifier(),
      );
      await bare.initialize();

      await sendEvent(PushEventMethods.onNotificationAction, <String, Object?>{
        'action': 'acknowledge',
        'incident_id': 'inc-3',
      });

      expect(navigated, <String>['/incidents/inc-3']);
    });
  });
}

/// No-op [LocalNotifier] for channel-dispatch tests.
class _NoopNotifier implements LocalNotifier {
  @override
  Future<void> initialize({
    required void Function(PushMessage message) onTap,
  }) async {}

  @override
  Future<PushMessage?> initialNotification() async => null;

  @override
  Future<void> showForeground(PushMessage message) async {}
}
