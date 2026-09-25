import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/dashboard/dashboard_screen.dart';
import 'features/incidents/incidents_screen.dart';
import 'features/monitors/monitors_screen.dart';
import 'features/settings/settings_screen.dart';
import 'theme/app_theme.dart';

GoRouter createRouter() {
  return GoRouter(
    routes: <GoRoute>[
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

final Provider<GoRouter> routerProvider = Provider<GoRouter>(
  (Ref ref) => createRouter(),
);

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
