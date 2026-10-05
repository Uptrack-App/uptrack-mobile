import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models/incident.dart';
import 'dashboard_controller.dart';
import '../../design/uptrack_design.dart';
import '../incidents/incidents_controller.dart' show IncidentStatusFilter;

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

/// Section order is the response order: what is waiting on a person first,
/// what has an acknowledgement on record next, then the account's health, then
/// history.
///
/// The whole page is one scroll view, so no section can push the queue out of
/// reach, and every section that has rows offers a link into the full feed
/// rather than hiding the rest of the queue.
class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The copy comes from the data, not from the widget: only a
    // server-confirmed empty account may be described as empty. Missing data
    // and an empty cache get their own truthful wording, and the offline
    // indicator stays on screen (see [DashboardData.emptyCopy]).
    final DashboardEmptyCopy? empty = data.emptyCopy;
    if (empty != null) {
      return _DashboardEmpty(
        copy: empty,
        offline: data.offline,
        onRefresh: () => ref.invalidate(dashboardProvider),
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
          // When this page's data was actually last read from the API (R4), the
          // older of the two snapshot times it is built from. Stated even when
          // offline: it is the honest age of what is on screen, and it does not
          // change what a fallback read says about completeness.
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: UptrackSyncStamp(syncedAt: data.syncedAt),
          ),
          _IncidentSection(
            // Named so an acceptance test can ask which section a row is in,
            // instead of inferring it from sibling order on screen.
            key: const ValueKey<String>('dashboard-needs-acknowledgement'),
            title: 'Needs acknowledgement',
            // Neutral by construction: it states the predicate the section
            // filters on and the order it lists in, and never implies that an
            // acknowledgement belongs to a person ("nobody", "you", "yours").
            // An acknowledgement is a timestamp on the incident, not an
            // assignment, and the copy must not read as one.
            hint: 'Open, not yet acknowledged, oldest first.',
            incidents: data.incidents.needsAcknowledgement,
            emptyMessage: 'No incidents need acknowledgement.',
            filter: IncidentStatusFilter.needsAcknowledgement,
            viewAllLabel: 'View all needing acknowledgement',
          ),
          const SizedBox(height: 16),
          _IncidentSection(
            key: const ValueKey<String>('dashboard-acknowledged-open'),
            title: 'Acknowledged open incidents',
            // Says exactly what the server recorded and nothing more: an
            // acknowledgement is a timestamp, not an assignment.
            hint:
                'Still open. The acknowledgement is on record, and does not '
                'assign anyone.',
            incidents: data.incidents.acknowledgedOngoing,
            emptyMessage: 'No acknowledged open incidents.',
            filter: IncidentStatusFilter.open,
            viewAllLabel: 'View all open incidents',
          ),
          const SizedBox(height: 16),
          _MonitorMetrics(data: data),
          const SizedBox(height: 16),
          _IncidentSection(
            key: const ValueKey<String>('dashboard-recently-resolved'),
            title: 'Recently resolved',
            hint: 'History only — nothing here needs a response.',
            incidents: data.incidents.recentResolved,
            emptyMessage: 'No recently resolved incidents.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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

/// A dashboard with nothing in it.
///
/// Shows what the data actually supports: an onboarding line only when the
/// server confirmed the account is empty, "monitor data unavailable" plus a
/// refresh when monitors exist but this response carried none, and "no cached
/// monitor data" while offline — with the offline banner kept, so an empty
/// cache never reads as an empty account.
class _DashboardEmpty extends StatelessWidget {
  const _DashboardEmpty({
    required this.copy,
    required this.offline,
    required this.onRefresh,
  });

  final DashboardEmptyCopy copy;
  final bool offline;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (offline)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: _OfflineBanner(),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
          child: Column(
            children: <Widget>[
              Semantics(
                header: true,
                child: ExcludeSemantics(
                  child: Text(
                    copy.headline,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                copy.detail,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (copy.showRefresh) ...<Widget>[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRefresh,
                  child: const Text('Refresh'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One titled incident section: a heading with the row count, the rows in the
/// order the controller derived, a neutral line when there is nothing, and a
/// link to the matching feed filter when there is.
class _IncidentSection extends StatelessWidget {
  const _IncidentSection({
    required this.title,
    required this.incidents,
    required this.emptyMessage,
    this.hint,
    this.filter,
    this.viewAllLabel,
    super.key,
  });

  final String title;
  final List<Incident> incidents;
  final String emptyMessage;
  final String? hint;

  /// Feed filter this section is a preview of, if any.
  final IncidentStatusFilter? filter;

  /// Link text for [filter]; self-describing, because a screen-reader user has
  /// no section heading to read alongside it.
  final String? viewAllLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          label:
              '$title, ${incidents.length} '
              '${incidents.length == 1 ? 'incident' : 'incidents'}',
          child: ExcludeSemantics(
            child: Text(
              '$title (${incidents.length})',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(hint!, style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: 8),
        if (incidents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(emptyMessage, style: theme.textTheme.bodyMedium),
          )
        else
          for (final Incident incident in incidents)
            _IncidentRow(incident: incident),
        if (incidents.isNotEmpty && filter != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () =>
                  context.go('/incidents?filter=${filter!.queryValue}'),
              child: Text(viewAllLabel!),
            ),
          ),
      ],
    );
  }
}

/// Account health: status counts and average uptime, labelled with exactly how
/// much of the account those numbers cover.
class _MonitorMetrics extends StatelessWidget {
  const _MonitorMetrics({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: ExcludeSemantics(
            child: Text(
              'Monitor status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _StatusCounts(data: data),
        const SizedBox(height: 12),
        _UptimeSummary(data: data),
        const SizedBox(height: 8),
        Text(
          data.monitorScopeSummary,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
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
      // The total tile reports the server's total; when only one page is
      // loaded it says which part of it these numbers describe instead of
      // passing a page off as the account.
      final String totalLabel = data.totalMonitorsKnown ? 'Total' : 'Cached';
      final String? totalDetail = data.hasMoreMonitors
          ? 'of ${data.totalMonitors} in account'
          : null;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in <String, int>{
            'Up': data.upCount,
            'Down': data.downCount,
            totalLabel: data.totalMonitors,
          }.entries)
            SizedBox(
              width: width,
              child: UptrackMetricTile(
                label: entry.key,
                semanticLabel: entry.key == totalLabel && data.hasMoreMonitors
                    ? 'Showing ${data.loadedMonitors} of '
                          '${data.totalMonitors} monitors'
                    : '${entry.key} monitors: ${entry.value}',
                value: '${entry.value}',
                detail: entry.key == totalLabel ? totalDetail : null,
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
  Widget build(BuildContext context) {
    // The average only covers the rows this response carried, and the label
    // says so whenever that is not the whole account.
    final String coverage = data.hasMoreMonitors
        ? '${data.loadedMonitors} of ${data.totalMonitors} monitors'
        : data.totalMonitorsKnown
        ? '${data.loadedMonitors} monitors'
        : '${data.loadedMonitors} cached monitors';
    return UptrackMetricTile(
      label: 'Average uptime',
      semanticLabel:
          'Average uptime ${data.averageUptime == null ? 'not available' : '${data.averageUptime!.toStringAsFixed(1)}%'} across $coverage',
      value: data.averageUptime == null
          ? null
          : '${data.averageUptime!.toStringAsFixed(1)}%',
      detail: 'across $coverage',
    );
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
