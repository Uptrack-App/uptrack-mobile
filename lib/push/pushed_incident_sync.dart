import '../api/models/incident.dart';
import '../data/local/cache_repository.dart';
import '../features/dashboard/dashboard_controller.dart'
    show incidentToSnapshot;
import '../widgets/widget_snapshot.dart' show isSampleFixtureId;

/// Reads one incident a foreground push named and stores it in the cache.
///
/// An APNs alert carries only the incident id, the monitor name and a
/// severity — not whether the incident is open or resolved. Reading the
/// incident once gives the widget and the Live Activity the server's answer:
/// the stored row fires [CacheRepository.incidentsChanged], and
/// `LiveSurfaceSync` then refreshes the widget and starts (iOS 16.1 to 17.1)
/// or ends the Live Activity.
///
/// Uses the same session, revision and read fences as the detail screen, so a
/// logout or a newer acknowledgement during the read wins. Returns whether
/// the row was stored. Never throws.
Future<bool> syncPushedIncident({
  required CacheRepository cache,
  required Future<IncidentDetail> Function(String id) fetch,
  required String incidentId,
}) async {
  if (incidentId.isEmpty || isSampleFixtureId(incidentId)) {
    return false;
  }
  final int session = cache.sessionEpoch;
  final int revision = cache.incidentRevision;
  final int readGeneration = cache.incidentReadGeneration;
  try {
    final IncidentDetail detail = await fetch(incidentId);
    return await cache.saveIncidentDetail(
      incidentToSnapshot(detail.incident),
      detail.updates,
      session: session,
      revision: revision,
      readGeneration: readGeneration,
      syncedAt: DateTime.now(),
    );
  } on Object {
    return false;
  }
}
