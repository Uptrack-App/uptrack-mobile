import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models/incident.dart';
import 'dashboard_controller.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DashboardData> dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: dashboard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _StatTile(label: 'Up', value: '${data.upCount}'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(label: 'Down', value: '${data.downCount}'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(label: 'Total', value: '${data.totalMonitors}'),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      label: '$label monitors: $value',
      container: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: <Widget>[
              Text(value, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _UptimeSummary extends StatelessWidget {
  const _UptimeSummary({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double? uptime = data.averageUptime;
    final String uptimeText = uptime == null
        ? '—'
        : '${uptime.toStringAsFixed(1)}%';
    return Semantics(
      label: 'Average uptime $uptimeText across ${data.totalMonitors} monitors',
      container: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Average uptime', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(uptimeText, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'across ${data.totalMonitors} monitors',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    return Semantics(
      label: 'Incident ${incident.displayName}, status ${incident.status}',
      child: Card(
        child: ListTile(
          title: Text(incident.displayName),
          subtitle: Text(incident.status),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/incidents'),
        ),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
