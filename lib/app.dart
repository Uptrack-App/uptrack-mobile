import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'obs/observability.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/demo_session.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/incidents/incident_detail_screen.dart';
import 'features/incidents/incidents_controller.dart'
    show incidentFilterFromQuery;
import 'features/incidents/incidents_screen.dart';
import 'features/monitors/monitor_detail_screen.dart';
import 'features/monitors/monitors_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/checkout_return_screen.dart';
import 'features/status/status_page_screen.dart';
import 'push/push_providers.dart';
import 'theme/app_theme.dart';
import 'design/adaptive_scaffold.dart';

GoRouter createRouter({
  AuthStatus Function()? authStatusOf,
  String initialLocation = '/',
  List<NavigatorObserver>? observers,
  Listenable? refreshListenable,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    observers: observers,
    refreshListenable: refreshListenable,
    redirect: (BuildContext context, GoRouterState state) {
      if (state.matchedLocation == '/demo' && !isAndroidDemoAvailable) {
        return '/login';
      }
      final AuthStatus Function()? statusOf = authStatusOf;
      if (statusOf == null) {
        return null;
      }
      final AuthStatus status = statusOf();
      final bool loggingIn = state.matchedLocation == '/login';
      if (state.matchedLocation == '/demo' ||
          state.matchedLocation == '/magic') {
        return null;
      }
      if (status != AuthStatus.signedIn && !loggingIn) {
        final String? checkoutReturn = checkoutReturnLocation(state.uri);
        return checkoutReturn == null
            ? '/login'
            : Uri(
                path: '/login',
                queryParameters: <String, String>{'next': checkoutReturn},
              ).toString();
      }
      if (status == AuthStatus.signedIn && loggingIn) {
        return checkoutReturnLocation(
              Uri.tryParse(state.uri.queryParameters['next'] ?? '/'),
            ) ??
            '/';
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/magic',
        name: 'magicSignIn',
        builder: (context, state) => LoginScreen(
          magicLink: Uri(
            scheme: 'uptrack',
            host: 'auth',
            path: '/magic',
            queryParameters: state.uri.queryParameters,
          ),
        ),
      ),
      GoRoute(
        path: '/demo',
        builder: (context, state) =>
            DemoSessionScreen(onExit: () => context.go('/login')),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (BuildContext context, GoRouterState state) => LoginScreen(
          returnLocation:
              checkoutReturnLocation(
                Uri.tryParse(state.uri.queryParameters['next'] ?? '/'),
              ) ??
              '/',
        ),
      ),
      GoRoute(
        path: '/billing/return',
        name: 'checkoutReturn',
        builder: (BuildContext context, GoRouterState state) =>
            CheckoutReturnScreen(
              expectedPlan:
                  checkoutPaidPlans.contains(state.uri.queryParameters['plan'])
                  ? state.uri.queryParameters['plan']
                  : null,
            ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => UptrackAdaptiveScaffold(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (index) => shell.goBranch(
            index,
            initialLocation: index == shell.currentIndex,
          ),
          child: shell,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                name: 'dashboard',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/monitors',
                name: 'monitors',
                builder: (context, state) => const MonitorsScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    name: 'monitorDetail',
                    builder: (context, state) => MonitorDetailScreen(
                      monitorId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/incidents',
                name: 'incidents',
                builder: (context, state) => IncidentsScreen(
                  // A dashboard "view all" link names the filter it previews.
                  filter: incidentFilterFromQuery(
                    state.uri.queryParameters['filter'],
                  ),
                ),
                routes: [
                  GoRoute(
                    path: ':id',
                    name: 'incidentDetail',
                    builder: (context, state) => IncidentDetailScreen(
                      incidentId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                name: 'settings',
                builder: (context, state) => const SettingsScreen(),
              ),
              GoRoute(
                path: '/status',
                name: 'status',
                builder: (context, state) => StatusPageScreen(
                  initialSlug: state.uri.queryParameters['slug'] ?? '',
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  // Keep the same router through restore/login. Recreating it loses a cold
  // checkout return before the stored device token has finished restoring.
  final ValueNotifier<int> refresh = ValueNotifier<int>(0);
  ref.listen<AuthState>(authControllerProvider, (
    AuthState? previous,
    AuthState next,
  ) {
    if (previous?.status != next.status) refresh.value += 1;
  });
  final GoRouter router = createRouter(
    authStatusOf: () => ref.read(authControllerProvider).status,
    refreshListenable: refresh,
    observers: buildAppObservers(),
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
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
