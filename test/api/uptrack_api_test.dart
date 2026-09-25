import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/client.dart';
import 'package:uptrack_mobile/api/models/check.dart';
import 'package:uptrack_mobile/api/models/current_user.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/api/models/monitor.dart';
import 'package:uptrack_mobile/api/models/monitor_analytics.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';

/// Fake [HttpClientAdapter] returning canned JSON without network access.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
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

Map<String, Object?> meFixture() => <String, Object?>{
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

Map<String, Object?> monitorsFixture() => <String, Object?>{
  'data': <Object?>[
    <String, Object?>{
      'id': '33333333-3333-4333-8333-333333333333',
      'name': 'Homepage',
      'url': 'https://example.com',
      'monitor_type': 'http',
      'status': 'up',
      'interval': 60,
      'timeout': 10,
      'settings': <String, Object?>{},
      'confirmation_window': '1m',
      'regions_required': 'any',
      'alert_contacts': <Object?>[],
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-02T00:00:00Z',
      'uptime_percentage': 99.9,
      'last_check': <String, Object?>{
        'status': 'up',
        'response_time': 123,
        'checked_at': '2026-01-02T00:00:00Z',
      },
    },
  ],
  'meta': <String, Object?>{'total': 1, 'page': 1, 'per_page': 20},
};

Dio dioWithFake(Future<ResponseBody> Function(RequestOptions) handler) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:4000'));
  dio.httpClientAdapter = FakeAdapter(handler);
  return dio;
}

void main() {
  test('getMe parses user + organization', () async {
    final Dio dio = dioWithFake(
      (RequestOptions options) async => jsonResponse(meFixture()),
    );
    final UptrackApi api = UptrackApi(dio: dio);

    final CurrentUserResponse me = await api.getMe();

    expect(me.user.email, 'ada@example.com');
    expect(me.organization.slug, 'acme');
  });

  test('listMonitors parses monitors + meta and sends paging params', () async {
    RequestOptions? seen;
    final Dio dio = dioWithFake((RequestOptions options) async {
      seen = options;
      return jsonResponse(monitorsFixture());
    });
    final UptrackApi api = UptrackApi(dio: dio);

    final MonitorListResponse res = await api.listMonitors(
      page: 2,
      perPage: 50,
    );

    expect(res.meta.total, 1);
    expect(res.meta.page, 1);
    expect(res.data, hasLength(1));
    expect(res.data.single.name, 'Homepage');
    expect(res.data.single.lastCheck?.responseTime, 123);
    expect(seen?.queryParameters['page'], 2);
    expect(seen?.queryParameters['per_page'], 50);
  });

  test('listIncidents parses the data envelope + status filter', () async {
    RequestOptions? seen;
    final Dio dio = dioWithFake((RequestOptions options) async {
      seen = options;
      return jsonResponse(<String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': '44444444-4444-4444-8444-444444444444',
            'monitor_id': '33333333-3333-4333-8333-333333333333',
            'monitor_name': 'Homepage',
            'status': 'open',
            'started_at': '2026-09-26T00:00:00Z',
            'resolved_at': null,
            'acknowledged_at': null,
            'inserted_at': '2026-09-26T00:00:00Z',
          },
        ],
      });
    });
    final UptrackApi api = UptrackApi(dio: dio);

    final IncidentListResponse res = await api.listIncidents(status: 'ongoing');

    expect(seen?.path, kIncidentsPath);
    expect(seen?.queryParameters['status'], 'ongoing');
    expect(res.data, hasLength(1));
    expect(res.data.single.displayName, 'Homepage');
    expect(res.data.single.isOngoing, isTrue);
  });

  test('getMonitor parses the { data } envelope', () async {
    RequestOptions? seen;
    final Dio dio = dioWithFake((RequestOptions options) async {
      seen = options;
      return jsonResponse(<String, Object?>{
        'data': (monitorsFixture()['data']! as List).single,
      });
    });
    final UptrackApi api = UptrackApi(dio: dio);

    final Monitor monitor = await api.getMonitor(
      '33333333-3333-4333-8333-333333333333',
    );

    expect(seen?.path, '/api/monitors/33333333-3333-4333-8333-333333333333');
    expect(monitor.name, 'Homepage');
    expect(monitor.regionsRequired, 'any');
  });

  test('listChecks parses checks newest-first with a limit param', () async {
    RequestOptions? seen;
    final Dio dio = dioWithFake((RequestOptions options) async {
      seen = options;
      return jsonResponse(<String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'status': 'up',
            'response_time': 120,
            'status_code': 200,
            'checked_at': '2026-09-26T00:00:00Z',
            'error_message': null,
          },
          <String, Object?>{
            'status': 'down',
            'response_time': 5000,
            'status_code': 503,
            'checked_at': '2026-09-25T23:55:00Z',
            'error_message': 'connection refused',
          },
        ],
      });
    });
    final UptrackApi api = UptrackApi(dio: dio);

    final CheckListResponse res = await api.listChecks('monitor-id');

    expect(seen?.path, '/api/monitors/monitor-id/checks');
    expect(seen?.queryParameters['limit'], 20);
    expect(res.data, hasLength(2));
    expect(res.data.first.isUp, isTrue);
    expect(res.data.last.errorMessage, 'connection refused');
  });

  test(
    'getMonitorAnalytics parses series + percentiles + period_days',
    () async {
      RequestOptions? seen;
      final Dio dio = dioWithFake((RequestOptions options) async {
        seen = options;
        return jsonResponse(<String, Object?>{
          'monitor_id': 'monitor-id',
          'period_days': 7,
          'uptime_chart': <Object?>[],
          'response_times': <Object?>[
            <String, Object?>{'timestamp': 1729900000, 'response_time': 123.5},
            <String, Object?>{'timestamp': 1729903600, 'response_time': 140.0},
          ],
          'percentiles': <String, Object?>{
            'p50': 120.0,
            'p95': 300.0,
            'p99': 500.0,
          },
          'incident_stats': <String, Object?>{
            'total_incidents': 1,
            'ongoing_incidents': 0,
            'resolved_incidents': 1,
            'mttr_minutes': 12.0,
          },
        });
      });
      final UptrackApi api = UptrackApi(dio: dio);

      final MonitorAnalytics analytics = await api.getMonitorAnalytics(
        'monitor-id',
        days: 90,
      );

      expect(seen?.path, '/api/analytics/monitors/monitor-id');
      expect(seen?.queryParameters['days'], 90);
      expect(analytics.periodDays, 7);
      expect(analytics.responseTimes, hasLength(2));
      expect(analytics.responseTimes.first.responseTime, 123.5);
      expect(analytics.percentiles.p95, 300.0);
    },
  );

  test('getMonitorAnalytics rejects windows outside 1/7/90', () async {
    final Dio dio = dioWithFake(
      (RequestOptions options) async => jsonResponse(<String, Object?>{}),
    );
    final UptrackApi api = UptrackApi(dio: dio);

    expect(
      () => api.getMonitorAnalytics('monitor-id', days: 30),
      throwsArgumentError,
    );
  });

  test('bearer-token interceptor attaches Authorization header', () async {
    RequestOptions? seen;
    final Dio inner = dioWithFake((RequestOptions options) async {
      seen = options;
      return jsonResponse(meFixture());
    });
    final Dio dio = createApiClient(
      dio: inner,
      tokenProvider: () => 'device-token-123',
    );
    final UptrackApi api = UptrackApi(dio: dio);

    await api.getMe();

    expect(seen?.headers['Authorization'], 'Bearer device-token-123');
  });

  test('no Authorization header without a token', () async {
    RequestOptions? seen;
    final Dio inner = dioWithFake((RequestOptions options) async {
      seen = options;
      return jsonResponse(meFixture());
    });
    final Dio dio = createApiClient(dio: inner, tokenProvider: () => null);
    final UptrackApi api = UptrackApi(dio: dio);

    await api.getMe();

    expect(seen?.headers.containsKey('Authorization'), isFalse);
  });

  test('getIncident parses incident + updates', () async {
    RequestOptions? seen;
    final Dio dio = dioWithFake((RequestOptions options) async {
      seen = options;
      return jsonResponse(<String, Object?>{
        'data': <String, Object?>{
          'incident': <String, Object?>{
            'id': '44444444-4444-4444-8444-444444444444',
            'monitor_id': '33333333-3333-4333-8333-333333333333',
            'monitor_name': 'Homepage',
            'status': 'open',
            'started_at': '2026-09-26T00:00:00Z',
            'resolved_at': null,
            'acknowledged_at': null,
            'inserted_at': '2026-09-26T00:00:00Z',
          },
          'updates': <Object?>[
            <String, Object?>{
              'id': 7,
              'status': 'investigating',
              'title': 'Looking into it',
              'description': 'Checking the logs.',
              'posted_at': '2026-09-26T00:05:00Z',
              'user_id': null,
            },
          ],
        },
      });
    });
    final UptrackApi api = UptrackApi(dio: dio);

    final IncidentDetail detail = await api.getIncident(
      '44444444-4444-4444-8444-444444444444',
    );

    expect(seen?.path, '/api/incidents/44444444-4444-4444-8444-444444444444');
    expect(seen?.method, 'GET');
    expect(detail.incident.displayName, 'Homepage');
    expect(detail.incident.isOngoing, isTrue);
    expect(detail.updates, hasLength(1));
    expect(detail.updates.single.displayTitle, 'Looking into it');
  });

  test('acknowledgeIncident POSTs to the acknowledge path', () async {
    RequestOptions? seen;
    final Dio dio = dioWithFake((RequestOptions options) async {
      seen = options;
      return jsonResponse(<String, Object?>{
        'data': <String, Object?>{
          'incident': <String, Object?>{
            'id': '44444444-4444-4444-8444-444444444444',
            'monitor_id': '33333333-3333-4333-8333-333333333333',
            'monitor_name': null,
            'status': 'open',
            'started_at': '2026-09-26T00:00:00Z',
            'resolved_at': null,
            'acknowledged_at': '2026-09-26T00:10:00Z',
            'inserted_at': '2026-09-26T00:00:00Z',
          },
          'updates': <Object?>[],
        },
      });
    });
    final UptrackApi api = UptrackApi(dio: dio);

    final IncidentDetail detail = await api.acknowledgeIncident(
      '44444444-4444-4444-8444-444444444444',
    );

    expect(
      seen?.path,
      '/api/incidents/44444444-4444-4444-8444-444444444444/acknowledge',
    );
    expect(seen?.method, 'POST');
    expect(detail.incident.isAcknowledged, isTrue);
  });
}
