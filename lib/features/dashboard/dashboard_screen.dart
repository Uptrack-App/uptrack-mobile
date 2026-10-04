import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models/incident.dart';
import 'dashboard_controller.dart';
import '../../design/uptrack_design.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DashboardData> dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: dashboard.when(
        loading: () =>
            const UptrackStateView(message: 'Loading dashboard', loading: true),
        error: (Object err, StackTrace _) => _DashboardError(
          message: dashboardErrorMessage(err),
          onRetry: () => ref.invalidate(dashboardProvider),
        ),
        data: (DashboardData data) => _DashboardBody(data: data),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.totalMonitors == 0 && data.recentIncidents.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('No monitors yet.'),
              SizedBox(height: 8),
              Text(
                'Add a monitor on the web dashboard to get started.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardProvider);
        await ref.read(dashboardProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (data.offline)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: _OfflineBanner(),
            ),
          _StatusCounts(data: data),
          const SizedBox(height: 12),
          _UptimeSummary(data: data),
          const SizedBox(height: 16),
          const _RecentIncidentsHeader(),
          const SizedBox(height: 8),
          if (data.recentIncidents.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No recent incidents.'),
              ),
            )
          else
            for (final Incident incident in data.recentIncidents)
              _IncidentRow(incident: incident),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => context.go('/monitors'),
                child: const Text('View monitors'),
              ),
              OutlinedButton(
                onPressed: () => context.go('/incidents'),
                child: const Text('View incidents'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Icon(Icons.cloud_off_outlined),
            SizedBox(width: 8),
            Expanded(child: Text('Offline — showing cached data')),
          ],
        ),
      ),
    );
  }
}

class _StatusCounts extends StatelessWidget {
  const _StatusCounts({required this.data});
  final DashboardData data;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
      final columns = constraints.maxWidth < 350 || largeText ? 1 : 3;
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in {
            'Up': data.upCount,
            'Down': data.downCount,
            'Total': data.totalMonitors,
          }.entries)
            SizedBox(
              width: width,
              child: UptrackMetricTile(
                label: entry.key,
                semanticLabel: '${entry.key} monitors: ${entry.value}',
                value: '${entry.value}',
              ),
            ),
        ],
      );
    },
  );
}

class _UptimeSummary extends StatelessWidget {
  const _UptimeSummary({required this.data});
  final DashboardData data;
  @override
  Widget build(BuildContext context) => UptrackMetricTile(
    label: 'Average uptime',
    semanticLabel:
        'Average uptime ${data.averageUptime == null ? 'not available' : '${data.averageUptime!.toStringAsFixed(1)}%'} across ${data.totalMonitors} monitors',
    value: data.averageUptime == null
        ? null
        : '${data.averageUptime!.toStringAsFixed(1)}%',
    detail: 'across ${data.totalMonitors} monitors',
  );
}

class _RecentIncidentsHeader extends StatelessWidget {
  const _RecentIncidentsHeader();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text('Recent incidents', style: theme.textTheme.titleMedium);
  }
}

class _IncidentRow extends StatelessWidget {
  const _IncidentRow({required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context) {
    return UptrackDataRow(
      title: incident.displayName,
      semanticLabel:
          'Incident ${incident.displayName}, status ${incident.isOngoing ? 'Open' : 'Resolved'}${incident.isAcknowledged ? ', acknowledged' : ''}',
      details: UptrackLifecycleBadge(
        open: incident.isOngoing,
        acknowledged: incident.isAcknowledged,
      ),
      onTap: () => context.go('/incidents/${incident.id}'),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return UptrackStateView(
      message: message,
      actionLabel: 'Retry',
      onAction: onRetry,
    );
  }
}
