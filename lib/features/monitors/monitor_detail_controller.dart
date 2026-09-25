import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/check.dart';
import '../../api/models/monitor.dart';
import '../../api/models/monitor_analytics.dart';
import '../../api/uptrack_api.dart';
import '../../data/local/app_database.dart';
import '../../data/local/cache_repository.dart';
import '../../data/local/database_providers.dart';
import '../auth/auth_controller.dart';
import 'monitors_controller.dart';

/// Monitor detail content: the monitor row, its recent checks, and the
/// response-time analytics for the selected window (null when the analytics
/// call failed — e.g. offline — while the rest loaded).
class MonitorDetailData {
  const MonitorDetailData({
    required this.monitor,
    required this.checks,
    required this.analytics,
    required this.offline,
  });

  final Monitor monitor;
  final List<MonitorCheck> checks;
  final MonitorAnalytics? analytics;
  final bool offline;
}

/// Maps an API check to a cache snapshot for the offline store.
CheckSnapshot checkToSnapshot(String monitorId, MonitorCheck check) =>
    CheckSnapshot(
      monitorId: monitorId,
      status: check.status,
      responseTime: check.responseTime,
      statusCode: check.statusCode,
      checkedAt: check.checkedAt,
      errorMessage: check.errorMessage,
    );

/// Maps a cached check row back to the API shape.
MonitorCheck checkFromCached(CachedCheck row) => MonitorCheck(
  status: row.status,
  responseTime: row.responseTime,
  statusCode: row.statusCode,
  checkedAt: row.checkedAt,
  errorMessage: row.errorMessage,
);

/// Source of [MonitorDetailData] (faked in widget tests).
abstract class MonitorDetailRepository {
  Future<MonitorDetailData> load(String id, {required int days});
}

/// Loads the monitor + checks + analytics from the API, caches the checks,
/// and falls back to the cached rows when the API is unreachable. Rethrows
/// the API error when the monitor is not in the cache either.
///
/// An analytics failure alone never fails the load: the chart shows an
/// "unavailable" state instead ([MonitorDetailData.analytics] is null).
class ApiMonitorDetailRepository implements MonitorDetailRepository {
  ApiMonitorDetailRepository({required this.api, required this.cache});

  final UptrackApi api;
  final CacheRepository cache;

  @override
  Future<MonitorDetailData> load(String id, {required int days}) async {
    try {
      final Monitor monitor = await api.getMonitor(id);
      final CheckListResponse checks = await api.listChecks(id);
      MonitorAnalytics? analytics;
      try {
        analytics = await api.getMonitorAnalytics(id, days: days);
      } on DioException {
        analytics = null;
      }
      await cache.saveChecks(
        id,
        checks.data.map((MonitorCheck c) => checkToSnapshot(id, c)).toList(),
      );
      return MonitorDetailData(
        monitor: monitor,
        checks: checks.data,
        analytics: analytics,
        offline: false,
      );
    } on DioException {
      final CachedList<CachedMonitor> cachedMonitors = await cache
          .getMonitors();
      CachedMonitor? row;
      for (final CachedMonitor candidate in cachedMonitors.data) {
        if (candidate.id == id) {
          row = candidate;
          break;
        }
      }
      if (row == null) {
        rethrow;
      }
      final CachedList<CachedCheck> cachedChecks = await cache.getChecks(id);
      return MonitorDetailData(
        monitor: monitorFromCached(row),
        checks: cachedChecks.data.map(checkFromCached).toList(),
        analytics: null,
        offline: true,
      );
    }
  }
}

final Provider<MonitorDetailRepository> monitorDetailRepositoryProvider =
    Provider<MonitorDetailRepository>(
      (Ref ref) => ApiMonitorDetailRepository(
        api: ref.watch(uptrackApiProvider),
        cache: ref.watch(cacheRepositoryProvider),
      ),
    );

/// Selected chart window for the detail screen (`?days=` value).
class AnalyticsDays extends Notifier<int> {
  @override
  int build() => 7;

  set days(int value) => state = value;
}

final NotifierProvider<AnalyticsDays, int> monitorAnalyticsDaysProvider =
    NotifierProvider<AnalyticsDays, int>(AnalyticsDays.new);

/// Detail content for one monitor, refetching when the chart window changes.
final monitorDetailProvider = FutureProvider.family<MonitorDetailData, String>((
  Ref ref,
  String id,
) {
  final int days = ref.watch(monitorAnalyticsDaysProvider);
  return ref.watch(monitorDetailRepositoryProvider).load(id, days: days);
}, retry: (int retryCount, Object error) => null);
