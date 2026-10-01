import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/notification_preferences.dart';
import 'package:uptrack_mobile/api/models/status_page.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/features/status/status_page_screen.dart';

/// Fake [HttpClientAdapter] returning canned JSON without network access
/// (same pattern as `test/api/uptrack_api_test.dart`).
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
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

Map<String, Object?> statusFixture() => <String, Object?>{
  'data': <String, Object?>{
    'name': 'Acme Status',
    'slug': 'acme',
    'description': 'All systems nominal-ish.',
    'overall_status': 'degraded',
    'uptime_percentage': 99.95,
    'monitors': <Object?>[
      <String, Object?>{
        'name': 'api',
        'status': 'up',
        'response_time': 42,
        'last_checked_at': '2026-09-26T00:00:00Z',
      },
      <String, Object?>{
        'name': 'db',
        'status': 'down',
        'response_time': null,
        'last_checked_at': null,
      },
    ],
    'recent_incidents': <Object?>[
      <String, Object?>{
        'id': '11111111-1111-4111-8111-111111111111',
        'status': 'ongoing',
        'monitor_name': 'db',
        'started_at': '2026-09-25T00:00:00Z',
        'resolved_at': null,
        'cause': null,
      },
    ],
    'maintenance_windows': <Object?>[],
  },
};

Dio dioWithFake(Future<ResponseBody> Function(RequestOptions) handler) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:4000'));
  dio.httpClientAdapter = FakeAdapter(handler);
  return dio;
}

void main() {
  group('StatusPageData model', () {
    test('parses the data envelope with monitors + incidents', () {
      final StatusPageData page = StatusPageData.fromJson(
        (statusFixture()['data']! as Map).cast<String, Object?>(),
      );
      expect(page.name, 'Acme Status');
      expect(page.overallStatus, 'degraded');
      expect(page.uptimePercentage, closeTo(99.95, 0.0001));
      expect(page.monitors, hasLength(2));
      expect(page.monitors.last.status, 'down');
      expect(page.recentIncidents, hasLength(1));
      expect(page.recentIncidents.first.monitorName, 'db');
    });
  });

  group('UptrackApi status page', () {
    test('GETs the slug path without auth envelope assumptions', () async {
      RequestOptions? seen;
      final Dio dio = dioWithFake((RequestOptions options) async {
        seen = options;
        return jsonResponse(statusFixture());
      });

      final StatusPageData page = await UptrackApi(dio: dio)
          .getStatusPage('acme');

      expect(seen?.method, 'GET');
      expect(seen?.path, '/api/status/acme');
      expect(seen?.queryParameters, isEmpty);
      expect(page.name, 'Acme Status');
    });

    test('sends the page password as ?password=', () async {
      RequestOptions? seen;
      final Dio dio = dioWithFake((RequestOptions options) async {
        seen = options;
        return jsonResponse(statusFixture());
      });

      await UptrackApi(dio: dio).getStatusPage('acme', password: 's3cret');

      expect(seen?.queryParameters['password'], 's3cret');
    });
  });

  group('StatusPageScreen', () {
    ProviderContainer makeContainer(
      Future<ResponseBody> Function(RequestOptions) handler,
    ) {
      final AuthTokenHolder holder = AuthTokenHolder();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
          authTokenHolderProvider.overrideWithValue(holder),
          dioProvider.overrideWithValue(
            buildAppDio(
              holder: holder,
              onUnauthorized: () {},
              adapter: FakeAdapter(handler),
            ),
          ),
        ],
      );
      return container;
    }

    Future<void> pumpPage(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: StatusPageScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('slug lookup renders overall status + monitors', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = makeContainer(
        (RequestOptions options) async => jsonResponse(statusFixture()),
      );
      addTearDown(container.dispose);

      await pumpPage(tester, container);
      await tester.enterText(
        find.byKey(const ValueKey<String>('status-slug')),
        'acme',
      );
      await tester.tap(find.text('View status'));
      await tester.pumpAndSettle();

      expect(find.text('Acme Status'), findsOneWidget);
      expect(find.text('Degraded'), findsOneWidget);
      expect(find.text('api'), findsOneWidget);
      expect(find.text('db'), findsWidgets);
    });

    testWidgets('unknown slug shows the not-found state + retry', (
      WidgetTester tester,
    ) async {
      bool fail = true;
      final ProviderContainer container = makeContainer((
        RequestOptions options,
      ) async {
        if (fail) {
          return jsonResponse(<String, Object?>{'error': 'not found'}, 404);
        }
        return jsonResponse(statusFixture());
      });
      addTearDown(container.dispose);

      await pumpPage(tester, container);
      await tester.enterText(
        find.byKey(const ValueKey<String>('status-slug')),
        'nope',
      );
      await tester.tap(find.text('View status'));
      await tester.pumpAndSettle();

      // The server's `error` field takes precedence in the message mapping.
      expect(find.text('not found'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Acme Status'), findsOneWidget);
    });

    test('statusPageErrorMessage maps 401/403/404 without a body', () {
      DioException errFor(int status) => DioException(
        requestOptions: RequestOptions(path: '/api/status/x'),
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/api/status/x'),
          statusCode: status,
        ),
      );
      expect(
        statusPageErrorMessage(errFor(401)),
        'This status page needs a password.',
      );
      expect(
        statusPageErrorMessage(errFor(403)),
        'This status page needs a password.',
      );
      expect(
        statusPageErrorMessage(errFor(404)),
        'No status page found for that slug.',
      );
    });
  });

  group('NotificationPreferences model', () {
    test('fromJson keeps known severities, drops unknown keys', () {
      final NotificationPreferences prefs = NotificationPreferences.fromJson(
        <String, Object?>{
          'severity_overrides': <String, Object?>{
            'p1': 'passive',
            'bogus': 'active',
          },
          'quiet_hours_start': '22:00:00',
          'quiet_hours_end': null,
          'mobile_push_enabled': false,
          'digest_p3': true,
        },
      );
      expect(prefs.severityOverrides, <String, String>{'p1': 'passive'});
      expect(prefs.quietHoursStart, '22:00:00');
      expect(prefs.mobilePushEnabled, isFalse);
    });

    test('quiet-time validation accepts HH:MM only', () {
      expect(isValidQuietTime('22:00'), isTrue);
      expect(isValidQuietTime('09:30'), isTrue);
      expect(isValidQuietTime('9:30'), isFalse);
      expect(isValidQuietTime('24:00'), isFalse);
      expect(isValidQuietTime('22:00:00'), isFalse);
      expect(isValidQuietTime(''), isFalse);
    });
  });
}
