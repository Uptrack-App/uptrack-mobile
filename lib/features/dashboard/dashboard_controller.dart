import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/incident.dart';
import '../../api/models/monitor.dart';
import '../../api/uptrack_api.dart';
import '../../data/local/app_database.dart';
import '../../data/local/cache_repository.dart';
import '../../data/local/database_providers.dart';
import '../auth/auth_controller.dart';

/// Dashboard content: monitor counts by status, an uptime summary, and
/// the most recent incidents.
class DashboardData {
  const DashboardData({
    required this.totalMonitors,
    required this.countsByStatus,
    required this.averageUptime,
    required this.recentIncidents,
    required this.offline,
  });

  final int totalMonitors;
  final Map<String, int> countsByStatus;
  final double? averageUptime;
  final List<Incident> recentIncidents;

  /// True when served from the offline cache because the API was
  /// unreachable (cache fallback).
  final bool offline;

  int get upCount => countsByStatus['up'] ?? 0;
  int get downCount => countsByStatus['down'] ?? 0;
  int get otherCount => totalMonitors - upCount - downCount;
}

/// Counts rows by their exact status string.
Map<String, int> countByStatus(Iterable<String> statuses) {
  final Map<String, int> counts = <String, int>{};
  for (final String status in statuses) {
    counts[status] = (counts[status] ?? 0) + 1;
  }
  return counts;
}

/// Mean of the non-null uptime values, or `null` when there are none.
double? averageUptime(Iterable<double?> values) {
  double sum = 0;
  int count = 0;
  for (final double? value in values) {
    if (value == null) {
      continue;
    }
    sum += value;
    count++;
  }
  if (count == 0) {
    return null;
  }
  return sum / count;
}

/// Maps API incidents to cache snapshots for the offline store.
IncidentSnapshot incidentToSnapshot(Incident incident) => IncidentSnapshot(
  id: incident.id,
  monitorId: incident.monitorId,
  monitorName: incident.monitorName,
  status: incident.status,
  startedAt: incident.startedAt,
  resolvedAt: incident.resolvedAt,
  acknowledgedAt: incident.acknowledgedAt,
  insertedAt: incident.insertedAt,
);

/// Maps a cached incident row back to the API shape.
Incident incidentFromCached(CachedIncident row) => Incident(
  id: row.id,
  monitorId: row.monitorId,
  status: row.status,
  insertedAt: row.insertedAt,
  monitorName: row.monitorName,
  startedAt: row.startedAt,
  resolvedAt: row.resolvedAt,
  acknowledgedAt: row.acknowledgedAt,
);

/// Source of [DashboardData] (faked in widget tests).
abstract class DashboardRepository {
  Future<DashboardData> load();
}

/// Loads monitors + incidents from the API, persists them to the offline
/// cache, and falls back to the cache when the API is unreachable.
/// Rethrows the API error when the cache is empty too.
class ApiDashboardRepository implements DashboardRepository {
  ApiDashboardRepository({required this.api, required this.cache});

  final UptrackApi api;
  final CacheRepository cache;

  /// Recent incidents shown on the dashboard (API order is newest first).
  static const int maxRecentIncidents = 5;

  @override
  Future<DashboardData> load() async {
    try {
      final MonitorListResponse monitors = await api.listMonitors(perPage: 100);
      final IncidentListResponse incidents = await api.listIncidents();
      await cache.saveMonitors(monitors.data);
      await cache.saveIncidents(
        incidents.data.map(incidentToSnapshot).toList(),
      );
      return DashboardData(
        totalMonitors: monitors.data.length,
        countsByStatus: countByStatus(
          monitors.data.map((Monitor m) => m.status),
        ),
        averageUptime: averageUptime(
          monitors.data.map((Monitor m) => m.uptimePercentage),
        ),
        recentIncidents: incidents.data.take(maxRecentIncidents).toList(),
        offline: false,
      );
    } on DioException {
      final CachedList<CachedMonitor> monitors = await cache.getMonitors();
      final CachedList<CachedIncident> incidents = await cache.getIncidents();
      if (monitors.data.isEmpty && incidents.data.isEmpty) {
        rethrow;
      }
      final List<CachedIncident> byRecency = incidents.data.toList()
        ..sort(
          (CachedIncident a, CachedIncident b) =>
              b.insertedAt.compareTo(a.insertedAt),
        );
      return DashboardData(
        totalMonitors: monitors.data.length,
        countsByStatus: countByStatus(
          monitors.data.map((CachedMonitor m) => m.status),
        ),
        averageUptime: averageUptime(
          monitors.data.map((CachedMonitor m) => m.uptimePercentage),
        ),
        recentIncidents: byRecency
            .take(maxRecentIncidents)
            .map(incidentFromCached)
            .toList(),
        offline: true,
      );
    }
  }
}

final Provider<DashboardRepository> dashboardRepositoryProvider =
    Provider<DashboardRepository>(
      (Ref ref) => ApiDashboardRepository(
        api: ref.watch(uptrackApiProvider),
        cache: ref.watch(cacheRepositoryProvider),
      ),
    );

final FutureProvider<DashboardData> dashboardProvider =
    FutureProvider<DashboardData>(
      (Ref ref) => ref.watch(dashboardRepositoryProvider).load(),
      // No automatic retry: a failed load falls back to the offline cache
      // inside the repository, and any remaining error is retried
      // explicitly via the Retry button / pull-to-refresh.
      retry: (int retryCount, Object error) => null,
    );

/// User-facing message for a dashboard load failure (prefers the
/// server's `error` field when present).
String dashboardErrorMessage(Object err) {
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
  return 'Could not load the dashboard. Check your connection and try again.';
}
