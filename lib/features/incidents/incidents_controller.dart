import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/incident.dart';
import '../../api/uptrack_api.dart';
import '../../data/local/app_database.dart';
import '../../data/local/cache_repository.dart';
import '../../data/local/database_providers.dart';
import '../auth/auth_controller.dart';
import '../dashboard/dashboard_controller.dart'
    show incidentFromCached, incidentToSnapshot;

/// Feed filter for the incident list.
enum IncidentStatusFilter {
  all,
  open;

  String get label => switch (this) {
    IncidentStatusFilter.all => 'All',
    IncidentStatusFilter.open => 'Open',
  };
}

/// Client-side filter over the loaded incidents: open means still ongoing
/// (`resolved_at` unset).
///
/// Filtering is client-side (not the API `status` param) so it keeps working
/// on the offline cache fallback.
List<Incident> filterIncidents(
  List<Incident> incidents, {
  IncidentStatusFilter status = IncidentStatusFilter.all,
}) {
  if (status == IncidentStatusFilter.all) {
    return incidents.toList();
  }
  return incidents.where((Incident i) => i.isOngoing).toList();
}

/// Incident feed content: rows plus whether they came from the offline cache.
class IncidentsData {
  const IncidentsData({required this.incidents, required this.offline});

  final List<Incident> incidents;
  final bool offline;
}

/// Source of [IncidentsData] (faked in widget tests).
abstract class IncidentsRepository {
  Future<IncidentsData> load();
}

/// Loads the incident feed from the API, persists it to the offline cache,
/// and falls back to the cache when the API is unreachable. Rethrows the
/// API error when the cache is empty too.
class ApiIncidentsRepository implements IncidentsRepository {
  ApiIncidentsRepository({required this.api, required this.cache});

  final UptrackApi api;
  final CacheRepository cache;

  @override
  Future<IncidentsData> load() async {
    try {
      final IncidentListResponse res = await api.listIncidents();
      await cache.saveIncidents(res.data.map(incidentToSnapshot).toList());
      return IncidentsData(incidents: res.data, offline: false);
    } on DioException {
      final CachedList<CachedIncident> cached = await cache.getIncidents();
      if (cached.data.isEmpty) {
        rethrow;
      }
      final List<CachedIncident> byRecency = cached.data.toList()
        ..sort(
          (CachedIncident a, CachedIncident b) =>
              b.insertedAt.compareTo(a.insertedAt),
        );
      return IncidentsData(
        incidents: byRecency.map(incidentFromCached).toList(),
        offline: true,
      );
    }
  }
}

final Provider<IncidentsRepository> incidentsRepositoryProvider =
    Provider<IncidentsRepository>(
      (Ref ref) => ApiIncidentsRepository(
        api: ref.watch(uptrackApiProvider),
        cache: ref.watch(cacheRepositoryProvider),
      ),
    );

final FutureProvider<IncidentsData> incidentsProvider =
    FutureProvider<IncidentsData>(
      (Ref ref) => ref.watch(incidentsRepositoryProvider).load(),
      // No automatic retry: a failed load falls back to the offline cache
      // inside the repository, and any remaining error is retried
      // explicitly via the Retry button / pull-to-refresh.
      retry: (int retryCount, Object error) => null,
    );

/// User-facing message for an incident-feed load failure (prefers the
/// server's `error` field when present).
String incidentsErrorMessage(Object err) {
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
  return 'Could not load incidents. Check your connection and try again.';
}

/// Incident detail content: the incident, its posted updates, and whether
/// the incident row came from the offline cache (updates are API-only —
/// the cache stores incident rows but no updates table, so offline detail
/// shows an empty updates list).
class IncidentDetailData {
  const IncidentDetailData({
    required this.incident,
    required this.updates,
    required this.offline,
  });

  final Incident incident;
  final List<IncidentUpdate> updates;
  final bool offline;

  IncidentDetailData copyWith({Incident? incident}) => IncidentDetailData(
    incident: incident ?? this.incident,
    updates: updates,
    offline: offline,
  );
}

/// Optimistic acknowledge update: marks the incident acknowledged immediately
/// (the caller sends the request and rolls back to the previous data — by
/// invalidating the provider — when it fails). Already-acknowledged
/// incidents are returned unchanged so a stale optimistic flag never
/// overwrites the server timestamp after a refetch.
IncidentDetailData optimisticAcknowledge(
  IncidentDetailData data, {
  DateTime? now,
}) {
  if (data.incident.isAcknowledged) {
    return data;
  }
  return data.copyWith(
    incident: data.incident.copyWith(
      acknowledgedAt: (now ?? DateTime.now().toUtc()).toIso8601String(),
    ),
  );
}

/// Source of [IncidentDetailData] (faked in widget tests).
abstract class IncidentDetailRepository {
  Future<IncidentDetailData> load(String id);

  /// Acknowledges the incident and returns the refreshed detail.
  Future<IncidentDetailData> acknowledge(String id);
}

/// Loads incident detail from the API with an offline row fallback, and
/// acknowledges via the API (no offline path — the mutation needs the
/// server; failures roll back the optimistic update in the UI).
class ApiIncidentDetailRepository implements IncidentDetailRepository {
  ApiIncidentDetailRepository({required this.api, required this.cache});

  final UptrackApi api;
  final CacheRepository cache;

  @override
  Future<IncidentDetailData> load(String id) async {
    try {
      final IncidentDetail detail = await api.getIncident(id);
      return IncidentDetailData(
        incident: detail.incident,
        updates: detail.updates,
        offline: false,
      );
    } on DioException {
      final CachedList<CachedIncident> cached = await cache.getIncidents();
      CachedIncident? row;
      for (final CachedIncident candidate in cached.data) {
        if (candidate.id == id) {
          row = candidate;
          break;
        }
      }
      if (row == null) {
        rethrow;
      }
      return IncidentDetailData(
        incident: incidentFromCached(row),
        updates: const <IncidentUpdate>[],
        offline: true,
      );
    }
  }

  @override
  Future<IncidentDetailData> acknowledge(String id) async {
    final IncidentDetail detail = await api.acknowledgeIncident(id);
    return IncidentDetailData(
      incident: detail.incident,
      updates: detail.updates,
      offline: false,
    );
  }
}

final Provider<IncidentDetailRepository> incidentDetailRepositoryProvider =
    Provider<IncidentDetailRepository>(
      (Ref ref) => ApiIncidentDetailRepository(
        api: ref.watch(uptrackApiProvider),
        cache: ref.watch(cacheRepositoryProvider),
      ),
    );

/// Detail content for one incident.
final incidentDetailProvider =
    FutureProvider.family<IncidentDetailData, String>(
      (Ref ref, String id) =>
          ref.watch(incidentDetailRepositoryProvider).load(id),
      retry: (int retryCount, Object error) => null,
    );

/// User-facing message for an acknowledge failure (prefers the server's
/// `error` field when present).
String acknowledgeErrorMessage(Object err) {
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
  return 'Could not acknowledge this incident. Try again.';
}
