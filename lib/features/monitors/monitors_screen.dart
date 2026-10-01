import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models/monitor.dart';
import 'monitor_widgets.dart';
import 'monitors_controller.dart';
import '../../theme/status_colors.dart';

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
                hintText: 'Search monitors',
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
              loading: () => const Center(child: CircularProgressIndicator()),
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
    if (data.monitors.isEmpty) {
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

    final List<Monitor> visible = filterMonitors(
      data.monitors,
      query: query,
      status: filter,
    );
    if (visible.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No monitors match your search.'),
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
          for (final Monitor monitor in visible) _MonitorRow(monitor: monitor),
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

class _MonitorRow extends StatelessWidget {
  const _MonitorRow({required this.monitor});

  final Monitor monitor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? uptime = monitor.uptimePercentage == null
        ? null
        : '${monitor.uptimePercentage!.toStringAsFixed(1)}% uptime';
    final String semanticsLabel = uptime == null
        ? 'Monitor ${monitor.name}, status ${statusLabel(monitor.status)}'
        : 'Monitor ${monitor.name}, status ${statusLabel(monitor.status)}, $uptime';
    return Semantics(
      label: semanticsLabel,
      child: Card(
        child: ListTile(
          title: Text(monitor.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(monitor.url, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  MonitorStatusChip(status: monitor.status),
                  if (uptime != null)
                    Text(uptime, style: theme.textTheme.bodySmall),
                  if (monitor.regionsRequired.isNotEmpty)
                    Text(
                      'Regions: ${monitor.regionsRequired}',
                      style: theme.textTheme.bodySmall,
                    ),
                  Text(monitor.monitorType, style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/monitors/${monitor.id}'),
        ),
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
