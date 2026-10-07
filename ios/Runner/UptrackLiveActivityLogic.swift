import Foundation

/// Pure rules of the incident Live Activity bridge
/// (`UptrackLiveActivityBridge.swift`). Foundation only, so the rules can be
/// checked with a plain `swiftc` script (`tool/check_live_activity_logic.swift`)
/// on any Mac, without a simulator.
enum UptrackLiveActivityLogic {
  /// Channel served by [UptrackLiveActivityBridge]; mirrors
  /// `kLiveActivityChannel` in `lib/widgets/live_activity_sync.dart`.
  static let channelName = "app.uptrack.mobile/live_activity"

  /// Server row lifetime for an activity's update token. iOS keeps an
  /// activity live for at most 8 hours and on the lock screen for up to 4
  /// more, so the row never outlives the activity by much.
  static let updateTokenTtlSeconds = 12 * 60 * 60

  static func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }

  /// `onLiveActivityToken` payload for one activity's update token.
  /// [environment] is the APNs environment of the build (`sandbox` |
  /// `production`), sent to the server with the token.
  static func updateTokenPayload(
    token: String, incidentId: String, environment: String
  ) -> [String: Any] {
    [
      "token": token,
      "kind": "update",
      "incident_id": incidentId,
      "expires_in_seconds": updateTokenTtlSeconds,
      "environment": environment,
    ]
  }

  /// `onLiveActivityToken` payload for the push-to-start token (iOS 17.2+).
  /// It names no incident: the server keeps one per signed-in device, and
  /// Dart posts it as soon as a session exists.
  static func pushToStartPayload(token: String, environment: String) -> [String: Any] {
    ["token": token, "kind": "push_to_start", "environment": environment]
  }

  /// The local start exists for iOS 16.1 to 17.1 only. On 17.2 and later the
  /// server starts the activity with push-to-start, and a second, local start
  /// would show two activities for one incident.
  static func allowsLocalStart(major: Int, minor: Int) -> Bool {
    if major == 16 { return minor >= 1 }
    if major == 17 { return minor < 2 }
    return false
  }

  struct StartRequest: Equatable {
    let incidentId: String
    let monitorName: String
    let title: String
    let body: String
    let status: String
  }

  /// Parses `start` arguments (`LiveActivityStart.toMap` in Dart). Nil
  /// without an incident id.
  static func startRequest(from arguments: Any?) -> StartRequest? {
    guard let args = arguments as? [String: Any],
      let incidentId = args["incident_id"] as? String, !incidentId.isEmpty
    else { return nil }
    let monitor = (args["monitor_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      ?? "Incident"
    let status = (args["status"] as? String) == "resolved" ? "resolved" : "ongoing"
    return StartRequest(
      incidentId: incidentId,
      monitorName: monitor,
      title: (args["title"] as? String) ?? "",
      body: (args["body"] as? String) ?? "",
      status: status)
  }

  struct EndRequest: Equatable {
    let activityId: String?
    let incidentId: String?
    let resolved: Bool
    let immediate: Bool
  }

  /// Parses `end` arguments (`LiveActivityEnd.toMap` in Dart). Nil without
  /// an activity id and an incident id.
  static func endRequest(from arguments: Any?) -> EndRequest? {
    guard let args = arguments as? [String: Any] else { return nil }
    let activityId = (args["activity_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    let incidentId = (args["incident_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    guard activityId != nil || incidentId != nil else { return nil }
    return EndRequest(
      activityId: activityId,
      incidentId: incidentId,
      resolved: (args["status"] as? String) == "resolved",
      immediate: (args["immediate"] as? Bool) ?? true)
  }

  /// Whether an end request names this activity.
  static func matches(_ request: EndRequest, activityId: String, incidentId: String) -> Bool {
    if let id = request.activityId { return id == activityId }
    return request.incidentId == incidentId
  }

  /// The resolved content the server's `la_title_body(Resolved)` sends.
  static func resolvedContent(monitorName: String) -> (title: String, body: String) {
    ("✅ \(monitorName) recovered", "Incident resolved")
  }

  /// Activity ids to end so that each incident keeps one activity (the first
  /// one listed).
  static func duplicateIds(_ activities: [(id: String, incidentId: String)]) -> [String] {
    var seen = Set<String>()
    var extra: [String] = []
    for activity in activities {
      if !seen.insert(activity.incidentId).inserted {
        extra.append(activity.id)
      }
    }
    return extra
  }
}
