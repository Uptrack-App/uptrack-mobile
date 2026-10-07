import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api/models/billing_subscription.dart' show kBillingExternalLinkEnabled;
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
import 'util/universal_links.dart';
import 'design/adaptive_scaffold.dart';

/// [checkoutReturnEnabled] keeps the browser-checkout return screen
/// (`/billing/return`) off unless the billing link is on (D6 in
/// `uptrack-spec/docs/mobile/ios-release-plan.md`). With it off, a link such as
/// `uptrack://app/billing/return?plan=pro` lands on the home screen, so the app
/// shows no purchase flow that the store listing does not describe.
GoRouter createRouter({
  AuthStatus Function()? authStatusOf,
  String initialLocation = '/',
  List<NavigatorObserver>? observers,
  Listenable? refreshListenable,
  bool checkoutReturnEnabled = kBillingExternalLinkEnabled,
}) {
  String? checkoutReturnOf(Uri? uri) =>
      checkoutReturnEnabled ? checkoutReturnLocation(uri) : null;

  return GoRouter(
    initialLocation: initialLocation,
    observers: observers,
    refreshListenable: refreshListenable,
    redirect: (BuildContext context, GoRouterState state) {
      // A universal link (iOS) or app link (Android) arrives as the full
      // https URL. Map it to an app screen. An unknown link lands on home;
      // it must never match an app route by its path alone.
      if (state.uri.scheme == 'https' || state.uri.scheme == 'http') {
        return universalLinkLocation(state.uri) ?? '/';
      }
      if (!checkoutReturnEnabled &&
          state.matchedLocation == '/billing/return') {
        return '/';
      }
      if (state.matchedLocation == '/demo' && !isDemoAvailable) {
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
        final String? checkoutReturn = checkoutReturnOf(state.uri);
        return checkoutReturn == null
            ? '/login'
            : Uri(
                path: '/login',
                queryParameters: <String, String>{'next': checkoutReturn},
              ).toString();
      }
      if (status == AuthStatus.signedIn && loggingIn) {
        return checkoutReturnOf(
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
              checkoutReturnOf(
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

/// Whether the browser-checkout return screen may open. Off while the billing
/// link is off (D6); a provider so tests can turn it on.
final Provider<bool> checkoutReturnEnabledProvider = Provider<bool>(
  (Ref ref) => kBillingExternalLinkEnabled,
);

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
    checkoutReturnEnabled: ref.read(checkoutReturnEnabledProvider),
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
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // Best-effort push plumbing (token registration, cold-start deep link,
    // foreground display); never blocks the first frame.
    unawaited(initializePush(ref));
    // Home widget + Live Activity refresh: after every applied incident
    // write and on every resume. Attached only once signed in, so a
    // signed-out launch never opens the offline database for it.
    ref.listenManual<AuthStatus>(
      authControllerProvider.select((AuthState s) => s.status),
      (AuthStatus? _, AuthStatus status) {
        if (status == AuthStatus.signedIn) {
          _attachLiveSurfaces();
        }
      },
      fireImmediately: true,
    );
  }

  void _attachLiveSurfaces() {
    if (_lifecycle != null) {
      return;
    }
    // Reading the provider attaches it to the cache's change stream; the
    // first incident sync after sign-in then refreshes both surfaces.
    ref.read(liveSurfaceSyncProvider);
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(ref.read(liveSurfaceSyncProvider).run()),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GoRouter router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Uptrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
