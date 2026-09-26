import 'package:dio/dio.dart';

import '../api/models/incident.dart';
import '../api/uptrack_api.dart';

/// Deep-link navigation for a completed (or dropped) triage action,
/// e.g. `router.go`.
typedef PushActionNavigation = void Function(String location);

/// Lock-screen triage actions (T031).
///
/// The native hosts (Swift categories in T028, Android likewise) send the
/// platform action ids (`UPTRACK_ACK`, `UPTRACK_ESCALATE`, `UPTRACK_SNOOZE` —
/// the ids the backend APNs sender advertises under its `UPTRACK_INCIDENT`
/// category); the lowercase aliases are accepted for forward-compatibility
/// with future hosts. Unknown ids parse to null and are ignored.
enum PushAction {
  acknowledge,
  escalate,
  snooze;

  /// Parses a raw action id from the native host; null when unknown.
  static PushAction? parse(String? raw) {
    return switch (raw) {
      'acknowledge' || 'UPTRACK_ACK' => PushAction.acknowledge,
      'escalate' || 'UPTRACK_ESCALATE' => PushAction.escalate,
      'snooze' || 'UPTRACK_SNOOZE' => PushAction.snooze,
      _ => null,
    };
  }
}

/// One lock-screen action tap parsed from a native payload.
///
/// Pure data: parsing and routing are unit-testable without any platform
/// channel. The native side sends string-keyed maps
/// (`{action, incident_id?, monitor_id?}`); unknown keys are ignored.
class PushActionRequest {
  const PushActionRequest({
    required this.action,
    this.incidentId,
    this.monitorId,
  });

  /// Parses the argument map of [PushEventMethods.onNotificationAction].
  /// Returns null when [map] is null or the action id is unknown.
  static PushActionRequest? fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return null;
    }
    String? string(String key) {
      final Object? value = map[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
      return null;
    }

    final PushAction? action = PushAction.parse(string('action'));
    if (action == null) {
      return null;
    }
    return PushActionRequest(
      action: action,
      incidentId: string('incident_id'),
      monitorId: string('monitor_id'),
    );
  }

  final PushAction action;
  final String? incidentId;
  final String? monitorId;

  /// Deep-link fallback for the tap: incident detail wins over monitor
  /// detail; null when the payload names neither.
  String? get routeLocation {
    if (incidentId != null) {
      return '/incidents/$incidentId';
    }
    if (monitorId != null) {
      return '/monitors/$monitorId';
    }
    return null;
  }
}

/// How a lock-screen triage action resolved.
enum PushActionOutcome {
  /// The API call succeeded (or the incident was already triaged server-side
  /// and the call was an idempotent no-op).
  performed,

  /// The API answered 401: the action was dropped and the user was
  /// deep-linked to the incident detail for manual retry after re-auth.
  authExpired,

  /// The request named no actionable ids (or the error was not auth-related
  /// but the user was still deep-linked for a manual retry).
  ignored,

  /// A non-401 API error: the action may not have applied; the user was
  /// deep-linked to the detail screen for a manual retry.
  failed,
}

/// Executes lock-screen triage actions against the API (T031).
///
/// * acknowledge → `POST /api/incidents/{id}/acknowledge` (exists)
/// * escalate → `POST /api/incidents/{id}/escalate` (T030)
/// * snooze → `POST /api/monitors/{id}/snooze` (T030), monitor-scoped;
///   when the payload carries only an incident id, the monitor is resolved
///   via `GET /api/incidents/{id}` first.
///
/// On 401 the action is dropped and the incident detail is opened for manual
/// retry after re-auth (per spec); other API errors deep-link the same way
/// but report [PushActionOutcome.failed].
class PushActionHandler {
  PushActionHandler({required this.api, required this.onNavigate});

  final UptrackApi api;
  final PushActionNavigation onNavigate;

  Future<PushActionOutcome> handle(PushActionRequest request) async {
    try {
      switch (request.action) {
        case PushAction.acknowledge:
          final String? incidentId = request.incidentId;
          if (incidentId == null) {
            return _ignored(request);
          }
          await api.acknowledgeIncident(incidentId);
        case PushAction.escalate:
          final String? incidentId = request.incidentId;
          if (incidentId == null) {
            return _ignored(request);
          }
          await api.escalateIncident(incidentId);
        case PushAction.snooze:
          final String? monitorId = await _snoozeMonitorId(request);
          if (monitorId == null) {
            return _ignored(request);
          }
          await api.snoozeMonitor(monitorId);
      }
    } on DioException catch (err) {
      _navigateFallback(request);
      if (err.response?.statusCode == 401) {
        return PushActionOutcome.authExpired;
      }
      return PushActionOutcome.failed;
    }
    _navigateFallback(request);
    return PushActionOutcome.performed;
  }

  /// Monitor id for a snooze: the payload's `monitor_id` when present,
  /// otherwise resolved from the incident detail.
  Future<String?> _snoozeMonitorId(PushActionRequest request) async {
    if (request.monitorId != null) {
      return request.monitorId;
    }
    final String? incidentId = request.incidentId;
    if (incidentId == null) {
      return null;
    }
    final IncidentDetail detail = await api.getIncident(incidentId);
    return detail.incident.monitorId;
  }

  PushActionOutcome _ignored(PushActionRequest request) {
    _navigateFallback(request);
    return PushActionOutcome.ignored;
  }

  void _navigateFallback(PushActionRequest request) {
    final String? location = request.routeLocation;
    if (location != null) {
      onNavigate(location);
    }
  }
}
