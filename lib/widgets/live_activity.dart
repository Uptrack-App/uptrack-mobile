/// Dart representation of the iOS Live Activity the backend drives via
/// APNs (`crates/api/src/push_live_activity.rs`, T019) — Dart side only.
///
/// The server sends start/update/end pushes with `apns-push-type:
/// liveactivity` and a per-bundle live-activity topic; the payload
/// shape below mirrors `build_live_activity_payload` 1:1 so Dart can build
/// matching requests and parse incoming pushes without guessing. The
/// WidgetKit `ActivityConfiguration` itself lands in T055.
library;

/// `attributes-type` identifying our ActivityKit attributes struct — must
/// match `LIVE_ACTIVITY_ATTRIBUTES_TYPE` on the server.
const String kLiveActivityAttributesType = 'UptrackIncidentAttributes';

/// `POST/DELETE /api/push/live-activities` (device-token Bearer auth).
const String kLiveActivitiesPath = '/api/push/live-activities';

/// Token kinds accepted by the server (`push_to_start` bootstraps a
/// remotely-started activity on iOS 17.2+; `update` refreshes a locally-
/// or remotely-started one).
const Set<String> kLiveActivityKinds = <String>{'push_to_start', 'update'};

/// Client-reported token lifetime bounds enforced by the server
/// (`expires_in_seconds`: at least a minute, at most 7 days).
const int kLiveActivityMinTtlSeconds = 60;
const int kLiveActivityMaxTtlSeconds = 604800;

/// One Live Activity lifecycle transition — maps 1:1 onto `aps.event`.
enum LiveActivityEvent {
  start,
  update,
  end;

  String get name => toString().split('.').last;

  static LiveActivityEvent? fromName(String? name) {
    for (final LiveActivityEvent event in LiveActivityEvent.values) {
      if (event.name == name) {
        return event;
      }
    }
    return null;
  }
}

/// Incident lifecycle events the server may turn into a Live Activity push
/// (mirrors `allows_live_activity_push`: open/update/resolve — never
/// per-check). Dart uses this as a cadence guard before registering local
/// activity state.
bool allowsLiveActivityPush(String event) {
  return event == 'open' ||
      event == 'start' ||
      event == 'update' ||
      event == 'resolve' ||
      event == 'end';
}

/// Fixed attributes of the incident activity (present only on `start`).
class LiveActivityAttributes {
  const LiveActivityAttributes({
    required this.incidentId,
    required this.monitorName,
  });

  factory LiveActivityAttributes.fromJson(Map<String, Object?> json) {
    return LiveActivityAttributes(
      incidentId: json['incidentId']! as String,
      monitorName: json['monitorName']! as String,
    );
  }

  final String incidentId;
  final String monitorName;

  Map<String, Object?> toJson() => <String, Object?>{
    'incidentId': incidentId,
    'monitorName': monitorName,
  };
}

/// Mutable content state carried by every start/update/end push
/// (`aps.content-state`); `status` is `ongoing` or `resolved`.
class LiveActivityState {
  const LiveActivityState({
    required this.title,
    required this.body,
    required this.status,
  });

  factory LiveActivityState.fromJson(Map<String, Object?> json) {
    return LiveActivityState(
      title: json['title']! as String,
      body: json['body']! as String,
      status: json['status']! as String,
    );
  }

  final String title;
  final String body;
  final String status;

  bool get isResolved => status == 'resolved';

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'body': body,
    'status': status,
  };
}

/// A parsed Live Activity push: the event, its content state, attributes
/// (start only), and the custom top-level keys the app uses to reconcile
/// the push with its local activity without parsing alert text.
class LiveActivityPush {
  const LiveActivityPush({
    required this.event,
    required this.state,
    required this.incidentId,
    required this.monitorName,
    this.attributes,
    this.timestamp,
  });

  /// Parses a payload shaped like the server's
  /// `build_live_activity_payload` output; throws [FormatException] on a
  /// missing `aps.event` or `aps.content-state`.
  factory LiveActivityPush.fromJson(Map<String, Object?> json) {
    final Object? apsValue = json['aps'];
    if (apsValue is! Map) {
      throw const FormatException('Missing aps in Live Activity push');
    }
    final Map<String, Object?> aps = apsValue.cast<String, Object?>();
    final Object? eventValue = aps['event'];
    final LiveActivityEvent? event = eventValue is String
        ? LiveActivityEvent.fromName(eventValue)
        : null;
    if (event == null) {
      throw FormatException('Unknown Live Activity event: $eventValue');
    }
    final Object? stateValue = aps['content-state'];
    if (stateValue is! Map) {
      throw const FormatException(
        'Missing content-state in Live Activity push',
      );
    }
    LiveActivityAttributes? attributes;
    final Object? attributesValue = aps['attributes'];
    if (attributesValue is Map) {
      attributes = LiveActivityAttributes.fromJson(
        attributesValue.cast<String, Object?>(),
      );
    }
    final Object? timestampValue = aps['timestamp'];
    return LiveActivityPush(
      event: event,
      state: LiveActivityState.fromJson(stateValue.cast<String, Object?>()),
      incidentId: json['incident_id']! as String,
      monitorName: json['monitor_name']! as String,
      attributes: attributes,
      timestamp: timestampValue is num ? timestampValue.toInt() : null,
    );
  }

  final LiveActivityEvent event;
  final LiveActivityState state;
  final String incidentId;
  final String monitorName;
  final LiveActivityAttributes? attributes;
  final int? timestamp;
}

/// Builds an APNs JSON body for one Live Activity push, mirroring the
/// server's `build_live_activity_payload` (`nowSecs` is `aps.timestamp`,
/// passed in so tests stay deterministic). `start` carries
/// `attributes-type` + `attributes`; all events carry `content-state` plus
/// the custom top-level reconciliation keys.
Map<String, Object?> buildLiveActivityPayload({
  required LiveActivityEvent event,
  required String incidentId,
  required String monitorName,
  required String title,
  required String body,
  required String status,
  required int nowSecs,
}) {
  final Map<String, Object?> aps = <String, Object?>{
    'timestamp': nowSecs,
    'event': event.name,
    'content-state': <String, Object?>{
      'title': title,
      'body': body,
      'status': status,
    },
  };
  if (event == LiveActivityEvent.start) {
    aps['attributes-type'] = kLiveActivityAttributesType;
    aps['attributes'] = <String, Object?>{
      'incidentId': incidentId,
      'monitorName': monitorName,
    };
  }
  return <String, Object?>{
    'aps': aps,
    'incident_id': incidentId,
    'monitor_name': monitorName,
  };
}

/// `POST /api/push/live-activities` body — registers the activity push
/// token when a Live Activity starts. [kind] is `push_to_start` (remote
/// start, iOS 17.2+) or `update`; [expiresInSeconds] optionally bounds the
/// row lifetime.
class LiveActivityRegisterRequest {
  const LiveActivityRegisterRequest({
    required this.incidentId,
    required this.token,
    required this.kind,
    this.expiresInSeconds,
  });

  final String incidentId;
  final String token;
  final String kind;
  final int? expiresInSeconds;

  /// Mirrors the server validation: non-empty token, known kind, TTL within
  /// 60s..7d when present. Returns the field errors (empty = valid).
  List<String> validate() {
    final List<String> errors = <String>[];
    if (token.trim().isEmpty) {
      errors.add('token: must be present');
    }
    if (!kLiveActivityKinds.contains(kind)) {
      errors.add('kind: must be one of: push_to_start, update');
    }
    final int? ttl = expiresInSeconds;
    if (ttl != null &&
        (ttl < kLiveActivityMinTtlSeconds ||
            ttl > kLiveActivityMaxTtlSeconds)) {
      errors.add('expires_in_seconds: must be between 60 and 604800');
    }
    return errors;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'incident_id': incidentId,
    'token': token,
    if (expiresInSeconds != null) 'expires_in_seconds': expiresInSeconds,
    'kind': kind,
  };
}

/// `DELETE /api/push/live-activities` body — the activity is identified by
/// its push token (globally unique per activity). Called when the activity
/// ends on-device; provider-side pruning covers the rest.
class LiveActivityRemoveRequest {
  const LiveActivityRemoveRequest({required this.token});

  final String token;

  List<String> validate() {
    if (token.trim().isEmpty) {
      return <String>['token: must be present'];
    }
    return <String>[];
  }

  Map<String, Object?> toJson() => <String, Object?>{'token': token};
}
