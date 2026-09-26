import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/check.dart';
import '../../api/models/monitor.dart';
import '../../api/models/monitor_analytics.dart';
import 'monitor_detail_controller.dart';
import 'monitor_widgets.dart';

/// Monitor detail: header, response-time chart (24h/7d/90d via `?days=`),
/// percentiles, and check history.
class MonitorDetailScreen extends ConsumerWidget {
  const MonitorDetailScreen({required this.monitorId, super.key});

  final String monitorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MonitorDetailData> detail = ref.watch(
      monitorDetailProvider(monitorId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Monitor')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object err, StackTrace _) => _DetailError(
          message: _errorMessage(err),
          onRetry: () => ref.invalidate(monitorDetailProvider(monitorId)),
        ),
        data: (MonitorDetailData data) => _DetailBody(
          data: data,
          onRetry: () => ref.invalidate(monitorDetailProvider(monitorId)),
          onRefresh: () async {
            ref.invalidate(monitorDetailProvider(monitorId));
            await ref.read(monitorDetailProvider(monitorId).future);
          },
        ),
      ),
    );
  }
}

String _errorMessage(Object err) {
  return 'Could not load this monitor. Check your connection and try again.';
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({
    required this.data,
    required this.onRetry,
    required this.onRefresh,
  });

  final MonitorDetailData data;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final Monitor monitor = data.monitor;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (data.offline)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Card(
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
              ),
            ),
          Semantics(
            label: 'Monitor ${monitor.name}',
            header: true,
            container: true,
            explicitChildNodes: true,
            child: Text(monitor.name, style: theme.textTheme.headlineSmall),
          ),
          const SizedBox(height: 4),
          Text(monitor.url, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              MonitorStatusChip(status: monitor.status),
              if (monitor.uptimePercentage != null)
                Text('${monitor.uptimePercentage!.toStringAsFixed(1)}% uptime'),
              if (monitor.regionsRequired.isNotEmpty)
                Text('Regions: ${monitor.regionsRequired}'),
              Text(monitor.monitorType),
            ],
          ),
          const SizedBox(height: 8),
          if (monitor.lastCheck != null)
            Text(
              'Last check: ${monitor.lastCheck!.status} · '
              '${monitor.lastCheck!.responseTime} ms',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 16),
          Text('Response time', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _RangeSwitcher(
            selected: ref.watch(monitorAnalyticsDaysProvider),
            onSelected: (int days) =>
                ref.read(monitorAnalyticsDaysProvider.notifier).days = days,
          ),
          const SizedBox(height: 8),
          _ResponseChart(analytics: data.analytics),
          const SizedBox(height: 16),
          Text('Check history', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (data.checks.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No checks recorded yet.'),
              ),
            )
          else
            for (final MonitorCheck check in data.checks)
              _CheckRow(check: check),
        ],
      ),
    );
  }
}

class _RangeSwitcher extends StatelessWidget {
  const _RangeSwitcher({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const <ButtonSegment<int>>[
        ButtonSegment<int>(value: 1, label: Text('24H')),
        ButtonSegment<int>(value: 7, label: Text('7D')),
        ButtonSegment<int>(value: 90, label: Text('90D')),
      ],
      selected: <int>{selected},
      onSelectionChanged: (Set<int> selected) => onSelected(selected.single),
    );
  }
}

class _ResponseChart extends StatelessWidget {
  const _ResponseChart({required this.analytics});

  final MonitorAnalytics? analytics;

  @override
  Widget build(BuildContext context) {
    final MonitorAnalytics? analytics = this.analytics;
    if (analytics == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Response-time chart unavailable. Pull to refresh to try again.',
          ),
        ),
      );
    }
    if (analytics.responseTimes.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No response-time samples in this window.'),
        ),
      );
    }

    final ThemeData theme = Theme.of(context);
    final List<FlSpot> spots = analytics.responseTimes
        .map(
          (ResponseTimePoint p) =>
              FlSpot(p.timestamp.toDouble(), p.responseTime),
        )
        .toList();
    final ResponsePercentiles percentiles = analytics.percentiles;
    final String summary =
        'Response-time chart, last ${analytics.periodDays} days: '
        'p50 ${percentiles.p50.toStringAsFixed(0)} ms, '
        'p95 ${percentiles.p95.toStringAsFixed(0)} ms, '
        'p99 ${percentiles.p99.toStringAsFixed(0)} ms';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              label: summary,
              image: true,
              container: true,
              explicitChildNodes: true,
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      lineBarsData: <LineChartBarData>[
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: theme.colorScheme.primary,
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.15,
                            ),
                          ),
                        ),
                      ],
                      titlesData: const FlTitlesData(
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: const FlGridData(show: true),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'p50 ${percentiles.p50.toStringAsFixed(0)} ms · '
              'p95 ${percentiles.p95.toStringAsFixed(0)} ms · '
              'p99 ${percentiles.p99.toStringAsFixed(0)} ms',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Showing last ${analytics.periodDays} days. '
              'The window may be clamped to your plan\u2019s retention.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final MonitorCheck check;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Semantics(
      label:
          'Check ${check.status}, ${check.responseTime} ms, '
          'HTTP ${check.statusCode}',
      child: Card(
        child: ListTile(
          leading: Icon(
            check.isUp ? Icons.check_circle : Icons.error,
            color: check.isUp ? scheme.primary : scheme.error,
          ),
          title: Text(
            '${check.status} · ${check.responseTime} ms · HTTP ${check.statusCode}',
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(check.checkedAt, style: theme.textTheme.bodySmall),
              if (check.errorMessage != null && check.errorMessage!.isNotEmpty)
                Text(check.errorMessage!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, required this.onRetry});

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
