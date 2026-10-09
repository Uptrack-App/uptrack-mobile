import '../../design/uptrack_design.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models/monitor.dart';
import 'monitor_widgets.dart';
import 'monitors_controller.dart';

/// Monitor list: status, uptime, regions, search + status filter.
///
/// Filtering is client-side over the loaded (or cached) rows so search keeps
/// working on the offline fallback.
class MonitorsScreen extends ConsumerStatefulWidget {
  const MonitorsScreen({super.key});

  @override
  ConsumerState<MonitorsScreen> createState() => _MonitorsScreenState();
}

class _MonitorsScreenState extends ConsumerState<MonitorsScreen> {
  String _query = '';
  MonitorStatusFilter _filter = MonitorStatusFilter.all;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<MonitorsData> monitors = ref.watch(monitorsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Monitors')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search monitors',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (String value) => setState(() => _query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<MonitorStatusFilter>(
              segments: MonitorStatusFilter.values
                  .map(
                    (MonitorStatusFilter f) =>
                        ButtonSegment<MonitorStatusFilter>(
                          value: f,
                          label: Text(f.label),
                        ),
                  )
                  .toList(),
              selected: <MonitorStatusFilter>{_filter},
              onSelectionChanged: (Set<MonitorStatusFilter> selected) =>
                  setState(() => _filter = selected.single),
            ),
          ),
          Expanded(
            child: monitors.when(
              loading: () => const UptrackStateView(
                message: 'Loading monitors',
                loading: true,
              ),
              error: (Object err, StackTrace _) => _MonitorsError(
                message: monitorsErrorMessage(err),
                onRetry: () => ref.invalidate(monitorsProvider),
              ),
              data: (MonitorsData data) => _MonitorsBody(
                data: data,
                query: _query,
                filter: _filter,
                onRefresh: () async {
                  ref.invalidate(monitorsProvider);
                  await ref.read(monitorsProvider.future);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonitorsBody extends StatelessWidget {
  const _MonitorsBody({
    required this.data,
    required this.query,
    required this.filter,
    required this.onRefresh,
  });

  final MonitorsData data;
  final String query;
  final MonitorStatusFilter filter;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final visible = filterMonitors(data.monitors, query: query, status: filter);
    final emptyMessage = data.monitors.isEmpty
        ? 'No monitors yet. Add a monitor on the web dashboard to get started.'
        : 'No monitors match your search.';
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
          for (final Monitor monitor in visible) _MonitorRow(monitor: monitor),
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

class _MonitorRow extends StatelessWidget {
  const _MonitorRow({required this.monitor});

  final Monitor monitor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return UptrackDataRow(
      title: monitor.name,
      semanticLabel:
          'Monitor ${monitor.name}, status ${statusLabel(monitor.status)}${monitor.uptimePercentage == null ? '' : ', ${monitor.uptimePercentage!.toStringAsFixed(1)}% uptime'}',
      onTap: () => context.go('/monitors/${monitor.id}'),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UptrackCodeText(monitor.url),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MonitorStatusChip(status: monitor.status),
              if (monitor.uptimePercentage != null)
                UptrackDataText(
                  '${monitor.uptimePercentage!.toStringAsFixed(1)}% uptime',
                  style: theme.textTheme.bodySmall,
                ),
              if (monitor.regionsRequired.isNotEmpty)
                UptrackDataText(
                  'Regions: ${monitor.regionsRequired}',
                  style: theme.textTheme.bodySmall,
                ),
              Text(monitor.monitorType, style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonitorsError extends StatelessWidget {
  const _MonitorsError({required this.message, required this.onRetry});

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
