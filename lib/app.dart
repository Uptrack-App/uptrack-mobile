import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'obs/observability.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/incidents/incident_detail_screen.dart';
import 'features/incidents/incidents_screen.dart';
import 'features/monitors/monitor_detail_screen.dart';
import 'features/monitors/monitors_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/status/status_page_screen.dart';
import 'push/push_providers.dart';
import 'theme/app_theme.dart';

GoRouter createRouter({
  AuthStatus Function()? authStatusOf,
  String initialLocation = '/',
  List<NavigatorObserver>? observers,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    observers: observers,
    redirect: (BuildContext context, GoRouterState state) {
      final AuthStatus Function()? statusOf = authStatusOf;
      if (statusOf == null) {
        return null;
      }
      final AuthStatus status = statusOf();
      final bool loggingIn = state.matchedLocation == '/login';
      if (status != AuthStatus.signedIn && !loggingIn) {
        return '/login';
      }
      if (status == AuthStatus.signedIn && loggingIn) {
        return '/';
      }
      return null;
    },
    routes: <GoRoute>[
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (BuildContext context, GoRouterState state) =>
            const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        name: 'dashboard',
        builder: (BuildContext context, GoRouterState state) =>
            const DashboardScreen(),
        routes: <GoRoute>[
          GoRoute(
            path: 'monitors',
            name: 'monitors',
            builder: (BuildContext context, GoRouterState state) =>
                const MonitorsScreen(),
            routes: <GoRoute>[
              GoRoute(
                path: ':id',
                name: 'monitorDetail',
                builder: (BuildContext context, GoRouterState state) =>
                    MonitorDetailScreen(monitorId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: 'incidents',
            name: 'incidents',
            builder: (BuildContext context, GoRouterState state) =>
                const IncidentsScreen(),
            routes: <GoRoute>[
              GoRoute(
                path: ':id',
                name: 'incidentDetail',
                builder: (BuildContext context, GoRouterState state) =>
                    IncidentDetailScreen(
                      incidentId: state.pathParameters['id']!,
                    ),
              ),
            ],
          ),
          GoRoute(
            path: 'settings',
            name: 'settings',
            builder: (BuildContext context, GoRouterState state) =>
                const SettingsScreen(),
          ),
          GoRoute(
            path: 'status',
            name: 'status',
            builder: (BuildContext context, GoRouterState state) =>
                StatusPageScreen(
                  initialSlug: state.uri.queryParameters['slug'] ?? '',
                ),
          ),
        ],
      ),
    ],
  );
}

final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final AuthStatus status = ref.watch(
    authControllerProvider.select((AuthState s) => s.status),
  );
  return createRouter(
    authStatusOf: () => status,
    observers: buildAppObservers(),
  );
});

class UptrackApp extends ConsumerStatefulWidget {
  const UptrackApp({super.key});

  @override
  ConsumerState<UptrackApp> createState() => _UptrackAppState();
}

class _UptrackAppState extends ConsumerState<UptrackApp> {
  @override
  void initState() {
    super.initState();
    // Best-effort push plumbing (token registration, cold-start deep link,
    // foreground display); never blocks the first frame.
    unawaited(initializePush(ref));
  }

  @override
  Widget build(BuildContext context) {
    final GoRouter router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Uptrack',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
