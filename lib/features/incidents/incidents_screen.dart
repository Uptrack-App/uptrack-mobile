import '../../design/uptrack_design.dart';

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
              loading: () => const UptrackStateView(
                message: 'Loading incidents',
                loading: true,
              ),
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
    final visible = filterIncidents(data.incidents, status: filter);
    final emptyMessage = data.incidents.isEmpty
        ? 'No incidents.'
        : 'No open incidents.';
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (data.offline)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: _OfflineBanner(),
            ),
          if (visible.isEmpty)
            UptrackStateView(
              message: emptyMessage,
              actionLabel: 'Refresh',
              onAction: () {
                onRefresh();
              },
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
  Widget build(BuildContext context) => const UptrackNotice(
    message: 'Offline — showing cached data',
    kind: UptrackNoticeKind.offline,
  );
}

class _IncidentRow extends StatelessWidget {
  const _IncidentRow({required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context) {
    return UptrackDataRow(
      title: incident.displayName,
      semanticLabel:
          'Incident ${incident.displayName}, ${incident.isOngoing ? 'Open' : 'Resolved'}${incident.isAcknowledged ? ', acknowledged' : ''}',
      onTap: () => context.go('/incidents/${incident.id}'),
      details: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          UptrackLifecycleBadge(
            open: incident.isOngoing,
            acknowledged: incident.isAcknowledged,
          ),
          UptrackDataText(
            formatTimestamp(incident.insertedAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _IncidentsError extends StatelessWidget {
  const _IncidentsError({required this.message, required this.onRetry});

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
