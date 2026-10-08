import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
import '../../push/push_providers.dart';
import '../../push/push_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/appearance.dart';
import 'auth_controller.dart';

/// The sample workspace on the phone apps. iOS needs it too: App Review
/// must reach the app without an account (see store/metadata/review-notes.txt).
bool get isDemoAvailable =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// A disposable workspace. Its adapter never forwards a request to a server.
class DemoAdapter implements HttpClientAdapter {
  final DateTime now = DateTime.now().toUtc();
  Map<String, Object?> preferences = <String, Object?>{};

  /// Sample escalation policy: the first escalation of an open, unacknowledged
  /// incident runs two steps (page the on-call contact, then the backup).
  /// Afterwards the policy has nothing left, so the server-shaped answer is
  /// an idempotent no-op — the same behaviour the real endpoint has.
  static const int demoEscalationSteps = 2;
  static const String snoozedMonitorId = 'demo-api';

  /// The ongoing incident the tester responds to (acknowledge, escalate).
  static const String openIncidentId = 'demo-incident';

  /// An ongoing incident that is already acknowledged, so the dashboard shows
  /// both "needs acknowledgement" and "acknowledged open" at once.
  static const String acknowledgedIncidentId = 'demo-acknowledged';

  /// An older ongoing incident nobody answered. It is the reason the dashboard
  /// derives the queue from the whole list: newer incidents must not hide it.
  static const String unattendedIncidentId = 'demo-unanswered';

  bool escalated = false;
  String? snoozedUntil;

  /// Acknowledged timestamps by incident id, so acknowledging one incident
  /// never acknowledges the others (the real endpoint addresses one row).
  final Map<String, String> acknowledgedAt = <String, String>{};

  DemoAdapter() {
    acknowledgedAt[acknowledgedIncidentId] = ago(90);
  }

  String ago(int minutes) =>
      now.subtract(Duration(minutes: minutes)).toIso8601String();

  String inOneHour() => now.add(const Duration(hours: 1)).toIso8601String();

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

  /// Newest first, mirroring `GET /api/incidents`: one unacknowledged open
  /// incident, one acknowledged open incident, one older unacknowledged open
  /// incident and one resolved row.
  List<Map<String, Object?>> get incidents => <Map<String, Object?>>[
    <String, Object?>{
      'id': openIncidentId,
      'monitor_id': 'demo-api',
      'monitor_name': 'Public API',
      'status': 'ongoing',
      'inserted_at': ago(12),
      'started_at': ago(12),
      'acknowledged_at': acknowledgedAt[openIncidentId],
    },
    <String, Object?>{
      'id': acknowledgedIncidentId,
      'monitor_id': 'demo-checkout',
      'monitor_name': 'Checkout service',
      'status': 'ongoing',
      'inserted_at': ago(140),
      'started_at': ago(140),
      'acknowledged_at': acknowledgedAt[acknowledgedIncidentId],
    },
    <String, Object?>{
      'id': unattendedIncidentId,
      'monitor_id': 'demo-website',
      'monitor_name': 'Marketing website',
      'status': 'ongoing',
      'inserted_at': ago(560),
      'started_at': ago(560),
      'acknowledged_at': acknowledgedAt[unattendedIncidentId],
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
    } else if (path.startsWith('$kIncidentsPath/') &&
        options.method == 'POST' &&
        path.split('/').last == 'escalate') {
      // Escalation mirrors the real endpoint: a no-op once the incident is
      // acknowledged/resolved or the policy is spent, and never a claim that
      // anybody was actually notified.
      final Map<String, Object?> incident = incidents.firstWhere(
        (Map<String, Object?> i) => i['id'] == path.split('/')[3],
        orElse: () => <String, Object?>{},
      );
      final bool canFire =
          incident['id'] != null &&
          incident['resolved_at'] == null &&
          incident['acknowledged_at'] == null &&
          !escalated;
      if (!canFire) {
        data = <String, Object?>{'escalated': false, 'steps_fired': 0};
      } else {
        escalated = true;
        data = <String, Object?>{
          'escalated': true,
          'steps_fired': demoEscalationSteps,
        };
      }
    } else if (path.startsWith('$kListMonitorsPath/') &&
        options.method == 'POST' &&
        path.split('/').last == 'snooze') {
      // Monitor-scoped, this user only: the sample keeps its own expiry and
      // never touches team-wide state.
      final String id = path.split('/')[3];
      if (!monitors.any((Map<String, Object?> m) => m['id'] == id)) {
        status = 404;
        data = <String, Object?>{'error': 'Demo monitor not found.'};
      } else {
        snoozedUntil = inOneHour();
        data = <String, Object?>{'snoozed_until': snoozedUntil};
      }
    } else if (path.startsWith('$kIncidentsPath/')) {
      final parts = path.split('/');
      final matches = incidents.where((i) => i['id'] == parts[3]);
      if (matches.isNotEmpty &&
          (options.method == 'GET' || parts.last == 'acknowledge')) {
        if (options.method == 'POST' && parts.last == 'acknowledge') {
          // Addressed to one incident, like the real endpoint.
          acknowledgedAt[parts[3]] = now.toIso8601String();
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
              if (incident['acknowledged_at'] != null)
                <String, Object?>{
                  'id': 3,
                  'status': 'acknowledged',
                  'title': incident['id'] == acknowledgedIncidentId
                      ? 'Acknowledged before this demo session'
                      : 'Acknowledged in this demo session',
                  'posted_at': incident['acknowledged_at'],
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

/// The demo app itself: a separate provider container, router and in-memory
/// database keep demo samples away from real credentials, account state, push
/// and disk caches.
///
/// Public, and parameterised only where a harness needs it, so the on-device
/// acceptance fixture drives this exact widget — the real router, the real
/// screens, the real [DemoAdapter] — instead of re-pumping screens against
/// stand-in repositories. [initialLocation] and [adapter] exist so a test can
/// open a route directly and observe every request the journey makes; the
/// production entry point ([DemoSessionScreen]) leaves both at their defaults.
class UptrackDemoApp extends StatefulWidget {
  const UptrackDemoApp({
    required this.onExit,
    this.initialLocation = '/',
    this.adapter,
    this.pushService,
    super.key,
  });

  final VoidCallback onExit;

  /// Where the demo router starts. `'/'` is the dashboard; the production
  /// demo session always starts there.
  final String initialLocation;

  /// Sample workspace to serve requests from. Defaults to a fresh
  /// [DemoAdapter]; a test may pass a recording subclass to assert that the
  /// journey stays inside the sample.
  final DemoAdapter? adapter;

  /// Push service for *this demo container* only, or null for the production
  /// [pushServiceProvider] default.
  ///
  /// Narrow by design: the demo deliberately builds its own container instead of
  /// inheriting a live account's providers (that separation is what keeps sample
  /// data away from real credentials), so an override placed on an *outer*
  /// `ProviderScope` can never reach it. A harness that needs to watch the push
  /// boundary from inside the demo therefore passes the service here, where it
  /// reaches the container that actually resolves the provider.
  final PushService? pushService;

  @override
  State<UptrackDemoApp> createState() => _UptrackDemoAppState();
}

class _UptrackDemoAppState extends State<UptrackDemoApp> {
  late final GoRouter router;
  late final ProviderContainer container;
  late final AppDatabase database;
  late final Dio dio;

  @override
  void initState() {
    super.initState();
    router = createRouter(initialLocation: widget.initialLocation);
    database = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio()..httpClientAdapter = widget.adapter ?? DemoAdapter();
    container = ProviderContainer(
      overrides: [
        uptrackApiProvider.overrideWithValue(UptrackApi(dio: dio)),
        dioProvider.overrideWithValue(dio),
        appDatabaseProvider.overrideWithValue(database),
        authControllerProvider.overrideWith(
          () => _DemoAuthController(widget.onExit),
        ),
        // Only when asked for: the shipping demo leaves the production push
        // provider in place.
        if (widget.pushService != null)
          pushServiceProvider.overrideWithValue(widget.pushService!),
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
    child: ListenableBuilder(
      listenable: container.read(appearanceProvider),
      builder: (BuildContext context, Widget? _) => _app(context),
    ),
  );

  Widget _app(BuildContext context) => MaterialApp.router(
    title: 'Uptrack Demo',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: container.read(appearanceProvider).mode,
    routerConfig: router,
    builder: (context, child) {
      final MediaQueryData media = MediaQuery.of(context);
      return Column(
        children: <Widget>[
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: SafeArea(
              bottom: false,
              child: _DemoBanner(onExit: widget.onExit),
            ),
          ),
          // The banner above already consumed the status-bar inset, but a
          // routed screen's own Scaffold/AppBar insets itself by the same
          // amount again, which left a blank gap the height of the status bar
          // under every demo screen. Only the *top* padding is dropped, and
          // only for the routed screens: the banner keeps its SafeArea, and
          // the bottom gesture inset is untouched so the system gesture bar
          // is still respected.
          Expanded(
            child: Semantics(
              container: true,
              child: MediaQuery(
                data: media.copyWith(padding: media.padding.copyWith(top: 0)),
                child: child!,
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// The demo workspace banner: what this session is showing, and the way out of
/// it.
///
/// The explanation and the action share one row whenever that row genuinely
/// fits. They cannot always: at a 200% text scale "Exit demo" is wide enough to
/// leave the explanation a sliver of a column, which wraps it into many lines
/// and grows the banner until it covers the screen underneath it. So the layout
/// is chosen from a measurement of the *actual* scaled text instead of being
/// fixed:
///
/// * fits → the normal one-row banner, so the common case stays compact;
/// * narrow window or large text → the explanation takes the full width on its
///   own wrapping line, with the action below it, trailing-aligned.
///
/// Nothing is truncated, no font scale is clamped and the copy and the action
/// stay two separate, independently labelled nodes: a banner that fits is still
/// a banner a screen reader can read.
class _DemoBanner extends StatelessWidget {
  const _DemoBanner({required this.onExit});

  final VoidCallback onExit;

  static const String messageText = 'Demo · sample data';
  static const String exitText = 'Exit demo';

  /// Material's minimum interactive width, so the measured action width is the
  /// one the button will actually take.
  static const double _minActionWidth = 64;

  /// The default `TextButton` padding, used only when the theme sets none.
  static const EdgeInsetsGeometry _defaultActionPadding = EdgeInsets.symmetric(
    horizontal: 12,
  );

  static const EdgeInsets _horizontalPadding = EdgeInsets.symmetric(
    horizontal: 16,
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextDirection direction = Directionality.of(context);
    final TextScaler scaler = MediaQuery.textScalerOf(context);

    final TextStyle messageStyle =
        theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final ButtonStyle actionStyle =
        theme.textButtonTheme.style ?? const ButtonStyle();
    final TextStyle exitStyle =
        actionStyle.textStyle?.resolve(<WidgetState>{}) ??
        theme.textTheme.labelLarge ??
        const TextStyle(fontSize: 14);
    final EdgeInsets actionPadding =
        (actionStyle.padding?.resolve(<WidgetState>{}) ?? _defaultActionPadding)
            .resolve(direction);

    final double actionWidth = math.max(
      _minActionWidth,
      _textWidth(exitText, exitStyle, scaler, direction) +
          actionPadding.horizontal,
    );
    final double messageWidth = _textWidth(
      messageText,
      messageStyle,
      scaler,
      direction,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available =
            constraints.maxWidth - _horizontalPadding.horizontal;
        // One row only if the explanation still fits beside the action on a
        // single line at this text scale — that is what keeps the banner one
        // line tall in the common case. The margin keeps sub-pixel rounding
        // from wrapping the text the measurement said would fit.
        final bool fitsInOneRow = available >= actionWidth + messageWidth + 1;

        if (fitsInOneRow) {
          return Padding(
            padding: _horizontalPadding,
            child: Row(
              children: <Widget>[
                Expanded(child: Text(messageText, style: messageStyle)),
                TextButton(
                  onPressed: onExit,
                  style: actionStyle,
                  child: Text(exitText, style: exitStyle),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              // Full width: the explanation wraps across the whole banner
              // instead of fighting the action for the last few pixels.
              SizedBox(
                width: double.infinity,
                child: Text(
                  messageText,
                  style: messageStyle,
                  textAlign: TextAlign.start,
                ),
              ),
              TextButton(
                onPressed: onExit,
                style: actionStyle,
                child: Text(exitText, style: exitStyle),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The width one line of [text] needs at the real [style] and text [scaler].
  ///
  /// Measured, not assumed, so the row is chosen against the same scale the
  /// banner is about to lay out at.
  static double _textWidth(
    String text,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
    )..layout();
    final double width = painter.width;
    painter.dispose();
    return width;
  }
}

/// The routed `/demo` entry point: the demo app with its production defaults.
class DemoSessionScreen extends StatelessWidget {
  const DemoSessionScreen({super.key, required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => UptrackDemoApp(onExit: onExit);
}
