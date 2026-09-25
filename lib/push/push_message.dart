/// A push alert parsed from a native payload.
///
/// Pure data: parsing and deep-link routing are unit-testable without any
/// platform channel. The native side sends string-keyed maps (APNs/FCM
/// extras flattened by Swift/Kotlin in T028); unknown keys are ignored.
class PushMessage {
  const PushMessage({
    this.title,
    this.body,
    this.incidentId,
    this.monitorId,
    this.severity,
    this.collapseKey,
  });

  /// Parses the argument map of [PushChannels] event methods.
  /// Returns null when [map] is null (e.g. a normal cold start).
  static PushMessage? fromMap(Map<Object?, Object?>? map) {
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

    return PushMessage(
      title: string('title'),
      body: string('body'),
      incidentId: string('incident_id'),
      monitorId: string('monitor_id'),
      severity: string('severity'),
      collapseKey: string('collapse_key'),
    );
  }

  /// Encodes back to the string-keyed map form (local-notification payload).
  Map<String, String> toMap() {
    final Map<String, String> map = <String, String>{};
    final String? title = this.title;
    if (title != null) {
      map['title'] = title;
    }
    final String? body = this.body;
    if (body != null) {
      map['body'] = body;
    }
    final String? incidentId = this.incidentId;
    if (incidentId != null) {
      map['incident_id'] = incidentId;
    }
    final String? monitorId = this.monitorId;
    if (monitorId != null) {
      map['monitor_id'] = monitorId;
    }
    final String? severity = this.severity;
    if (severity != null) {
      map['severity'] = severity;
    }
    final String? collapseKey = this.collapseKey;
    if (collapseKey != null) {
      map['collapse_key'] = collapseKey;
    }
    return map;
  }

  final String? title;
  final String? body;
  final String? incidentId;
  final String? monitorId;
  final String? severity;
  final String? collapseKey;

  /// Deep-link target for a notification tap: incident detail wins over
  /// monitor detail; null when the payload names neither.
  String? get routeLocation {
    if (incidentId != null) {
      return '/incidents/$incidentId';
    }
    if (monitorId != null) {
      return '/monitors/$monitorId';
    }
    return null;
  }

  /// Stable Android notification id so repeat alerts for one incident
  /// collapse onto a single notification (server collapse key when present).
  int get notificationId {
    final String key = collapseKey ?? incidentId ?? monitorId ?? 'uptrack';
    return key.hashCode & 0x7fffffff;
  }

  /// P1/P2 alerts interrupt; anything else (or unknown) shows quietly.
  bool get isHighPriority => severity == 'p1' || severity == 'p2';
}
