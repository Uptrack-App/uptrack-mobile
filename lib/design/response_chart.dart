import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'components.dart';

class UptrackChartPoint {
  const UptrackChartPoint({required this.time, required this.milliseconds});
  final DateTime time;
  final double milliseconds;
}

/// Measured samples only. Caller supplies data, period and percentile summary.
class UptrackResponseChart extends StatelessWidget {
  const UptrackResponseChart({
    super.key,
    required this.points,
    required this.period,
    required this.summary,
    this.displayTime,
    this.periodNote,
  });
  final List<UptrackChartPoint> points;
  final String period, summary;
  final String? periodNote;
  final DateTime Function(DateTime)? displayTime;
  DateTime _time(DateTime value) => displayTime?.call(value) ?? value.toLocal();
  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const UptrackStateView(
        message: 'No response-time samples in this window.',
      );
    }
    final theme = Theme.of(context);
    final ordered = [...points]..sort((a, b) => a.time.compareTo(b.time));
    final first = ordered.first.time.millisecondsSinceEpoch / 1000;
    final last = ordered.last.time.millisecondsSinceEpoch / 1000;
    final span = last - first;
    // Relative x values avoid billion-scale numeric labels and precision loss.
    final spots = _withGaps([
      for (final point in ordered)
        FlSpot(
          point.time.millisecondsSinceEpoch / 1000 - first,
          point.milliseconds,
        ),
    ]);
    final color = theme.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Response time (ms) · $period',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            Semantics(
              label: '$period. ${points.length} measured samples. $summary',
              image: true,
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: span == 0 ? 1 : span,
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: false,
                          // Lines join neighbouring samples only; _withGaps
                          // breaks the line where samples are missing, so an
                          // unmeasured gap stays blank instead of interpolated.
                          barWidth: 1.5,
                          color: color,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, bar, index) =>
                                FlDotCirclePainter(
                                  radius: 2.5,
                                  color: color,
                                  strokeWidth: 0,
                                ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            color: color.withValues(alpha: 0.08),
                          ),
                        ),
                      ],
                      lineTouchData: const LineTouchData(enabled: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 48,
                            minIncluded: false,
                            maxIncluded: false,
                            getTitlesWidget: (value, meta) => SideTitleWidget(
                              meta: meta,
                              child: UptrackDataText(
                                value.toStringAsFixed(0),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            interval: span > 0 ? span / 2 : 1,
                            getTitlesWidget: (value, meta) => SideTitleWidget(
                              meta: meta,
                              fitInside: SideTitleFitInsideData.fromTitleMeta(
                                meta,
                                distanceFromEdge: 4,
                              ),
                              child: UptrackDataText(
                                DateFormat(span > 86400 ? 'MMM d' : 'HH:mm')
                                    .format(
                                      _time(
                                        DateTime.fromMillisecondsSinceEpoch(
                                          ((first + value) * 1000).round(),
                                          isUtc: true,
                                        ),
                                      ),
                                    ),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ),
                        ),
                      ),
                      gridData: const FlGridData(
                        show: true,
                        drawVerticalLine: false,
                      ),
                      borderData: FlBorderData(show: false),
                    ),
                    duration: Duration.zero,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            UptrackDataText(summary, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              ['Measured samples, in your time zone.', ?periodNote].join(' '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            ExpansionTile(
              title: const Text('View recorded samples'),
              tilePadding: EdgeInsets.zero,
              children: [
                for (final point in ordered)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        UptrackDataText(
                          '${DateFormat('yyyy-MM-dd HH:mm:ss').format(_time(point.time))} ${_time(point.time).timeZoneName}',
                        ),
                        UptrackDataText(
                          '${point.milliseconds.toStringAsFixed(1)} ms',
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Inserts a break ([FlSpot.nullSpot]) wherever two neighbouring samples are
/// more than three typical intervals apart, so the line never bridges a span
/// with no measurements.
List<FlSpot> _withGaps(List<FlSpot> spots) {
  if (spots.length < 3) return spots;
  final gaps = <double>[
    for (var i = 1; i < spots.length; i++) spots[i].x - spots[i - 1].x,
  ]..sort();
  final typical = gaps[gaps.length ~/ 2];
  if (typical <= 0) return spots;
  final out = <FlSpot>[spots.first];
  for (var i = 1; i < spots.length; i++) {
    if (spots[i].x - spots[i - 1].x > typical * 3) out.add(FlSpot.nullSpot);
    out.add(spots[i]);
  }
  return out;
}
