import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/monitor.dart';
import '../../api/uptrack_api.dart';
import '../../data/local/app_database.dart';
import '../../data/local/cache_repository.dart';
import '../../data/local/database_providers.dart';
import '../auth/auth_controller.dart';

/// Status filter for the monitor list.
enum MonitorStatusFilter {
  all,
  up,
  down;

  String get label => switch (this) {
    MonitorStatusFilter.all => 'All',
    MonitorStatusFilter.up => 'Up',
    MonitorStatusFilter.down => 'Down',
  };
}

/// Client-side filter over the loaded monitors: case-insensitive substring
/// match on name + url, plus an exact status match.
///
/// Filtering is client-side (not the API `search` param) so it keeps working
/// on the offline cache fallback.
List<Monitor> filterMonitors(
  List<Monitor> monitors, {
  String query = '',
  MonitorStatusFilter status = MonitorStatusFilter.all,
}) {
  final String needle = query.trim().toLowerCase();
  return monitors.where((Monitor m) {
    if (status == MonitorStatusFilter.up && m.status != 'up') {
      return false;
    }
    if (status == MonitorStatusFilter.down && m.status != 'down') {
      return false;
    }
    if (needle.isEmpty) {
      return true;
    }
    return m.name.toLowerCase().contains(needle) ||
        m.url.toLowerCase().contains(needle);
  }).toList();
}

/// Monitor list content: rows plus whether they came from the offline cache.
class MonitorsData {
  const MonitorsData({required this.monitors, required this.offline});

  final List<Monitor> monitors;
  final bool offline;
}

/// Maps a cached monitor row back to the API shape. The cache keeps the
/// subset of fields the list shows; fields outside that subset fall back to
/// neutral defaults (the detail screen refetches the full row when online).
Monitor monitorFromCached(CachedMonitor row) => Monitor(
  id: row.id,
  name: row.name,
  url: row.url,
  monitorType: row.monitorType,
  status: row.status,
  interval: row.interval,
  timeout: row.timeout,
  confirmationWindow: '',
  regionsRequired: '',
  createdAt: row.updatedAt,
  updatedAt: row.updatedAt,
  uptimePercentage: row.uptimePercentage,
  lastCheck: row.lastCheckStatus == null || row.lastCheckResponseTime == null
      ? null
      : LastCheck(
          status: row.lastCheckStatus!,
          responseTime: row.lastCheckResponseTime!,
          checkedAt: row.lastCheckAt ?? row.updatedAt,
        ),
);

/// Source of [MonitorsData] (faked in widget tests).
abstract class MonitorsRepository {
  Future<MonitorsData> load();
}

/// Loads the monitor list from the API, persists it to the offline cache,
/// and falls back to the cache when the API is unreachable. Rethrows the
/// API error when the cache is empty too.
class ApiMonitorsRepository implements MonitorsRepository {
  ApiMonitorsRepository({required this.api, required this.cache});

  final UptrackApi api;
  final CacheRepository cache;

  @override
  Future<MonitorsData> load() async {
    try {
      final MonitorListResponse res = await api.listMonitors(perPage: 100);
      await cache.saveMonitors(res.data);
      return MonitorsData(monitors: res.data, offline: false);
    } on DioException {
      final CachedList<CachedMonitor> cached = await cache.getMonitors();
      if (cached.data.isEmpty) {
        rethrow;
      }
      return MonitorsData(
        monitors: cached.data.map(monitorFromCached).toList(),
        offline: true,
      );
    }
  }
}

final Provider<MonitorsRepository> monitorsRepositoryProvider =
    Provider<MonitorsRepository>(
      (Ref ref) => ApiMonitorsRepository(
        api: ref.watch(uptrackApiProvider),
        cache: ref.watch(cacheRepositoryProvider),
      ),
    );

final FutureProvider<MonitorsData> monitorsProvider =
    FutureProvider<MonitorsData>(
      (Ref ref) => ref.watch(monitorsRepositoryProvider).load(),
      // No automatic retry: a failed load falls back to the offline cache
      // inside the repository, and any remaining error is retried
      // explicitly via the Retry button / pull-to-refresh.
      retry: (int retryCount, Object error) => null,
    );

/// User-facing message for a monitor-list load failure (prefers the
/// server's `error` field when present).
String monitorsErrorMessage(Object err) {
  if (err is DioException) {
    final Object? data = err.response?.data;
    if (data is Map<String, Object?>) {
      final Object? serverError = data['error'];
      if (serverError is String && serverError.isNotEmpty) {
        return serverError;
      }
    }
    if (err.response?.statusCode == 401) {
      return 'Session expired. Sign in again.';
    }
  }
  return 'Could not load monitors. Check your connection and try again.';
}
