import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/uptrack_api.dart';
import '../../app.dart' show createRouter;
import '../../data/local/app_database.dart';
import '../../data/local/database_providers.dart';
import '../../theme/app_theme.dart';
import 'auth_controller.dart';

bool get isAndroidDemoAvailable =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// A disposable workspace. Its adapter never forwards a request to a server.
class DemoAdapter implements HttpClientAdapter {
  final DateTime now = DateTime.now().toUtc();
  String? acknowledgedAt;
  Map<String, Object?> preferences = <String, Object?>{};

  String ago(int minutes) =>
      now.subtract(Duration(minutes: minutes)).toIso8601String();

  List<Map<String, Object?>> get monitors => <Map<String, Object?>>[
    for (final (id, name, status, response) in <(String, String, String, int)>[
      ('demo-website', 'Marketing website', 'up', 182),
      ('demo-api', 'Public API', 'down', 0),
      ('demo-checkout', 'Checkout service', 'up', 245),
    ])
      <String, Object?>{
        'id': id,
        'name': name,
        'url': 'https://$id.example.com',
        'monitor_type': 'http',
        'status': status,
        'interval': 60,
        'timeout': 10,
        'confirmation_window': 'immediate',
        'regions_required': 'any',
        'created_at': ago(43200),
        'updated_at': ago(1),
        'uptime_percentage': status == 'up' ? 99.98 : 98.72,
        'last_check': <String, Object?>{
          'status': status,
          'response_time': response,
          'checked_at': ago(1),
        },
      },
  ];

  List<Map<String, Object?>> get incidents => <Map<String, Object?>>[
    <String, Object?>{
      'id': 'demo-incident',
      'monitor_id': 'demo-api',
      'monitor_name': 'Public API',
      'status': 'ongoing',
      'inserted_at': ago(12),
      'started_at': ago(12),
      'acknowledged_at': acknowledgedAt,
    },
    <String, Object?>{
      'id': 'demo-resolved',
      'monitor_id': 'demo-checkout',
      'monitor_name': 'Checkout service',
      'status': 'resolved',
      'inserted_at': ago(180),
      'started_at': ago(180),
      'resolved_at': ago(174),
    },
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    Object? data;
    int status = 200;
    if (path == kGetMePath && options.method == 'GET') {
      data = <String, Object?>{
        'user': <String, Object?>{
          'id': 'demo-user',
          'name': 'Beta tester',
          'email': 'demo@example.com',
          'provider': 'demo',
          'role': 'owner',
          'is_admin': false,
          'inserted_at': ago(43200),
        },
        'organization': <String, Object?>{
          'id': 'demo-org',
          'name': 'Uptrack Demo',
          'slug': 'demo',
          'plan': 'pro',
        },
      };
    } else if (path == kListMonitorsPath && options.method == 'GET') {
      final search = (options.queryParameters['search'] as String? ?? '')
          .toLowerCase();
      final rows = monitors
          .where(
            (m) => '${m['name']} ${m['url']}'.toLowerCase().contains(search),
          )
          .toList();
      data = <String, Object?>{
        'data': rows,
        'meta': <String, Object?>{
          'total': rows.length,
          'page': 1,
          'per_page': 20,
        },
      };
    } else if (path.startsWith('$kListMonitorsPath/') &&
        options.method == 'GET') {
      final parts = path.split('/');
      final matches = monitors.where((m) => m['id'] == parts[3]);
      if (matches.isEmpty) {
        status = 404;
        data = <String, Object?>{'error': 'Demo monitor not found.'};
      } else if (parts.length == 5 && parts.last == 'checks') {
        final down = matches.first['status'] == 'down';
        data = <String, Object?>{
          'data': <Object?>[
            for (int i = 0; i < 20; i++)
              <String, Object?>{
                'status': down && i < 12 ? 'down' : 'up',
                'response_time': down && i < 12 ? 0 : 170 + i * 7,
                'status_code': down && i < 12 ? 503 : 200,
                'checked_at': ago(i + 1),
                'error_message': down && i < 12
                    ? 'HTTP 503 Service Unavailable'
                    : null,
              },
          ],
        };
      } else {
        data = <String, Object?>{'data': matches.first};
      }
    } else if (path.startsWith('/api/analytics/monitors/') &&
        options.method == 'GET') {
      final days = (options.queryParameters['days'] as int? ?? 7);
      data = <String, Object?>{
        'monitor_id': path.split('/').last,
        'period_days': days,
        'response_times': <Object?>[
          for (int i = 24; i >= 0; i--)
            <String, Object?>{
              'timestamp':
                  now
                      .subtract(Duration(hours: i * days))
                      .millisecondsSinceEpoch ~/
                  1000,
              'response_time': 160 + (i % 7) * 18,
            },
        ],
        'percentiles': <String, Object?>{'p50': 214, 'p95': 268, 'p99': 286},
      };
    } else if (path == kIncidentsPath && options.method == 'GET') {
      data = <String, Object?>{
        'data': incidents
            .where(
              (i) =>
                  options.queryParameters['status'] == null ||
                  i['status'] == options.queryParameters['status'],
            )
            .toList(),
      };
    } else if (path.startsWith('$kIncidentsPath/')) {
      final parts = path.split('/');
      final matches = incidents.where((i) => i['id'] == parts[3]);
      if (matches.isNotEmpty &&
          (options.method == 'GET' || parts.last == 'acknowledge')) {
        if (options.method == 'POST' && parts.last == 'acknowledge') {
          acknowledgedAt = now.toIso8601String();
        }
        final incident = incidents.firstWhere((i) => i['id'] == parts[3]);
        data = <String, Object?>{
          'data': <String, Object?>{
            'incident': incident,
            'updates': <Object?>[
              <String, Object?>{
                'id': 1,
                'status': 'investigating',
                'title': 'Investigating elevated API errors',
                'description': 'Sample incident for exploring Uptrack.',
                'posted_at': incident['started_at'],
              },
              if (incident['resolved_at'] != null)
                <String, Object?>{
                  'id': 2,
                  'status': 'resolved',
                  'title': 'Service recovered',
                  'posted_at': incident['resolved_at'],
                },
              if (acknowledgedAt != null && incident['id'] == 'demo-incident')
                <String, Object?>{
                  'id': 3,
                  'status': 'acknowledged',
                  'title': 'Acknowledged in this demo session',
                  'posted_at': acknowledgedAt,
                },
            ],
          },
        };
      } else {
        status = 403;
        data = <String, Object?>{
          'error': 'This action is unavailable in the sample workspace.',
        };
      }
    } else if (path == kNotificationPreferencesPath &&
        <String>['GET', 'PATCH'].contains(options.method)) {
      if (options.method == 'PATCH') {
        preferences.addAll((options.data as Map).cast<String, Object?>());
      }
      data = preferences;
    } else if (path == kBillingSubscriptionPath && options.method == 'GET') {
      data = <String, Object?>{'plan': 'pro', 'data': null};
    } else if (path == kDeviceTokensPath && options.method == 'GET') {
      data = <String, Object?>{'data': <Object?>[]};
    } else {
      status = 403;
      data = <String, Object?>{
        'error': 'Demo uses sample data. Sign in to your account to use this feature.',
      };
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _DemoAuthController extends AuthController {
  _DemoAuthController(this.onExit);
  final VoidCallback onExit;
  @override
  AuthState build() =>
      const AuthState(status: AuthStatus.signedIn, email: 'demo@example.com');
  @override
  Future<void> signOut({String? pushToken}) async => onExit();
}

/// A separate provider container, router and in-memory database keep demo
/// samples away from real credentials, account state, push and disk caches.
class DemoSessionScreen extends StatefulWidget {
  const DemoSessionScreen({super.key, required this.onExit});
  final VoidCallback onExit;
  @override
  State<DemoSessionScreen> createState() => _DemoSessionScreenState();
}

class _DemoSessionScreenState extends State<DemoSessionScreen> {
  late final GoRouter router;
  late final ProviderContainer container;
  late final AppDatabase database;
  late final Dio dio;

  @override
  void initState() {
    super.initState();
    router = createRouter();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio()..httpClientAdapter = DemoAdapter();
    container = ProviderContainer(
      overrides: [
        uptrackApiProvider.overrideWithValue(UptrackApi(dio: dio)),
        dioProvider.overrideWithValue(dio),
        appDatabaseProvider.overrideWithValue(database),
        authControllerProvider.overrideWith(
          () => _DemoAuthController(widget.onExit),
        ),
      ],
    );
  }

  @override
  void dispose() {
    container.dispose();
    router.dispose();
    dio.close(force: true);
    unawaited(database.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      title: 'Uptrack Demo',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) => Column(
        children: <Widget>[
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    const Expanded(child: Text('Demo · sample data')),
                    TextButton(
                      onPressed: widget.onExit,
                      child: const Text('Exit demo'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Confine route BlockSemantics to its own container so the persistent
          // sample notice and exit action remain available to screen readers.
          Expanded(child: Semantics(container: true, child: child!)),
        ],
      ),
    ),
  );
}
