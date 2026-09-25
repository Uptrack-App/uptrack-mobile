/// Per-monitor analytics from
/// `GET /api/analytics/monitors/{monitor_id}?days` (subset of
/// `MonitorAnalyticsOut`: response-time series + percentiles + the
/// server-echoed window).
///
/// Note: `days` is clamped server-side to the org plan's retention, so the
/// echoed [periodDays] (not the requested value) is the source of truth for
/// the "showing last N days" label.
class ResponseTimePoint {
  const ResponseTimePoint({
    required this.timestamp,
    required this.responseTime,
  });

  factory ResponseTimePoint.fromJson(Map<String, Object?> json) {
    return ResponseTimePoint(
      timestamp: (json['timestamp']! as num).toInt(),
      responseTime: (json['response_time']! as num).toDouble(),
    );
  }

  /// Unix seconds.
  final int timestamp;

  /// Milliseconds.
  final double responseTime;
}

/// Response-time percentiles (`{ p50, p95, p99 }`, milliseconds).
class ResponsePercentiles {
  const ResponsePercentiles({
    required this.p50,
    required this.p95,
    required this.p99,
  });

  factory ResponsePercentiles.fromJson(Map<String, Object?> json) {
    return ResponsePercentiles(
      p50: (json['p50']! as num).toDouble(),
      p95: (json['p95']! as num).toDouble(),
      p99: (json['p99']! as num).toDouble(),
    );
  }

  final double p50;
  final double p95;
  final double p99;
}

class MonitorAnalytics {
  const MonitorAnalytics({
    required this.monitorId,
    required this.periodDays,
    required this.responseTimes,
    required this.percentiles,
  });

  factory MonitorAnalytics.fromJson(Map<String, Object?> json) {
    final Object? points = json['response_times'];
    if (points is! List) {
      throw FormatException('Unexpected shape for MonitorAnalytics');
    }
    final Object? percentiles = json['percentiles'];
    if (percentiles is! Map) {
      throw FormatException('Unexpected shape for MonitorAnalytics');
    }
    return MonitorAnalytics(
      monitorId: json['monitor_id']! as String,
      periodDays: (json['period_days']! as num).toInt(),
      responseTimes: points
          .map(
            (Object? e) =>
                ResponseTimePoint.fromJson((e! as Map).cast<String, Object?>()),
          )
          .toList(),
      percentiles: ResponsePercentiles.fromJson(
        percentiles.cast<String, Object?>(),
      ),
    );
  }

  final String monitorId;
  final int periodDays;
  final List<ResponseTimePoint> responseTimes;
  final ResponsePercentiles percentiles;
}
