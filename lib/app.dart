import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/incidents/incidents_screen.dart';
import 'features/monitors/monitors_screen.dart';
import 'features/settings/settings_screen.dart';
import 'theme/app_theme.dart';

GoRouter createRouter({
  AuthStatus Function()? authStatusOf,
  String initialLocation = '/',
}) {
  return GoRouter(
    initialLocation: initialLocation,
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
        builder: (BuildContext context, GoRouterState state) =>
            const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            const DashboardScreen(),
        routes: <GoRoute>[
          GoRoute(
            path: 'monitors',
            builder: (BuildContext context, GoRouterState state) =>
                const MonitorsScreen(),
          ),
          GoRoute(
            path: 'incidents',
            builder: (BuildContext context, GoRouterState state) =>
                const IncidentsScreen(),
          ),
          GoRoute(
            path: 'settings',
            builder: (BuildContext context, GoRouterState state) =>
                const SettingsScreen(),
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
  return createRouter(authStatusOf: () => status);
});

class UptrackApp extends ConsumerWidget {
  const UptrackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Uptrack',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
