import '../../theme/status_colors.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models/incident.dart';
import 'incidents_controller.dart';
import '../../util/date_format.dart';

/// Incident feed: ongoing/resolved rows with an All/Open filter, newest
/// first, with cache fallback when offline.
class IncidentsScreen extends ConsumerStatefulWidget {
  const IncidentsScreen({super.key});

  @override
  ConsumerState<IncidentsScreen> createState() => _IncidentsScreenState();
}

class _IncidentsScreenState extends ConsumerState<IncidentsScreen> {
  IncidentStatusFilter _filter = IncidentStatusFilter.all;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<IncidentsData> incidents = ref.watch(incidentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Incidents')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<IncidentStatusFilter>(
              segments: IncidentStatusFilter.values
                  .map(
                    (IncidentStatusFilter f) =>
                        ButtonSegment<IncidentStatusFilter>(
                          value: f,
                          label: Text(f.label),
                        ),
                  )
                  .toList(),
              selected: <IncidentStatusFilter>{_filter},
              onSelectionChanged: (Set<IncidentStatusFilter> selected) =>
                  setState(() => _filter = selected.single),
            ),
          ),
          Expanded(
            child: incidents.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object err, StackTrace _) => _IncidentsError(
                message: incidentsErrorMessage(err),
                onRetry: () => ref.invalidate(incidentsProvider),
              ),
              data: (IncidentsData data) => _IncidentsBody(
                data: data,
                filter: _filter,
                onRefresh: () async {
                  ref.invalidate(incidentsProvider);
                  await ref.read(incidentsProvider.future);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IncidentsBody extends StatelessWidget {
  const _IncidentsBody({
    required this.data,
    required this.filter,
    required this.onRefresh,
  });

  final IncidentsData data;
  final IncidentStatusFilter filter;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (data.incidents.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No incidents. Your monitors are quiet.'),
        ),
      );
    }

    final List<Incident> visible = filterIncidents(
      data.incidents,
      status: filter,
    );
    if (visible.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No open incidents.'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (data.offline)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: _OfflineBanner(),
            ),
          for (final Incident incident in visible)
            _IncidentRow(incident: incident),
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

class _IncidentRow extends StatelessWidget {
  const _IncidentRow({required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String state = incident.isOngoing ? 'Open' : 'Resolved';
    final String label = incident.isAcknowledged
        ? 'Incident ${incident.displayName}, $state, acknowledged'
        : 'Incident ${incident.displayName}, $state';
    return Semantics(
      label: label,
      child: Card(
        child: ListTile(
          title: Text(incident.displayName),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  _StatusChip(incident: incident),
                  if (incident.isAcknowledged)
                    Text('Acknowledged', style: theme.textTheme.bodySmall),
                  Text(
                    formatTimestamp(incident.insertedAt),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/incidents/${incident.id}'),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context) {
    final String label = incident.isOngoing ? 'Open' : 'Resolved';
    final UptrackStatusColors colors = UptrackStatusColors.of(context);
    final UptrackStatus look = incident.isOngoing
        ? colors.down
        : colors.unknown;
    return Chip(
      avatar: Icon(look.icon, size: 14, color: look.color),
      label: Text(label),
      backgroundColor: look.soft,
      side: BorderSide.none,
      labelStyle: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: look.color),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _IncidentsError extends StatelessWidget {
  const _IncidentsError({required this.message, required this.onRetry});

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
