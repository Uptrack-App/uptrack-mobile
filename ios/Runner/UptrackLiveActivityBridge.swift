import ActivityKit
import Flutter
import Foundation

/// Native side of the incident Live Activity (iOS 16.1+).
///
/// * Observes every `UptrackIncident` activity — started by this app (iOS
///   16.1 to 17.1) or by a push-to-start push (iOS 17.2+) — and forwards its
///   update token to Dart (`onLiveActivityToken`, kind `update`), so the
///   server can update and end it. Before this, no update token reached the
///   server, so a running activity could not be updated or ended remotely.
/// * Forwards the push-to-start token (iOS 17.2+).
/// * Reports an ended or dismissed activity (`onLiveActivityEnded`), so Dart
///   removes its token from the server.
/// * Serves `list` / `start` / `end` on [UptrackLiveActivityLogic.channelName]
///   for `LiveActivitySync` in Dart, and `endAll` for logout.
///
/// Tokens are kept here as well, because ActivityKit can report them before
/// Dart listens; Dart pulls them with `getLiveActivityTokens`.
@available(iOS 16.1, *)
final class UptrackLiveActivityBridge {
  typealias Send = (_ method: String, _ payload: [String: Any]) -> Void

  private let send: Send
  private var observed = Set<String>()
  private var updateTokens: [String: String] = [:]
  private var pushToStartToken: String?

  init(send: @escaping Send) {
    self.send = send
  }

  /// Starts the observers. Call once, at launch.
  func start() {
    Task { @MainActor in
      for activity in Activity<UptrackIncident>.activities {
        self.observe(activity)
      }
      await self.endDuplicates()
      for await activity in Activity<UptrackIncident>.activityUpdates {
        self.observe(activity)
        await self.endDuplicates()
      }
    }
    if #available(iOS 17.2, *) {
      Task { @MainActor in
        for await data in Activity<UptrackIncident>.pushToStartTokenUpdates {
          let hex = UptrackLiveActivityLogic.hex(data)
          self.pushToStartToken = hex
          self.send(
            "onLiveActivityToken", UptrackLiveActivityLogic.pushToStartPayload(token: hex))
        }
      }
    }
  }

  /// Every token known now, as `onLiveActivityToken` payloads.
  func currentTokens() -> [[String: Any]] {
    var tokens: [[String: Any]] = []
    if let token = pushToStartToken {
      tokens.append(UptrackLiveActivityLogic.pushToStartPayload(token: token))
    }
    for activity in Self.running() {
      let token = updateTokens[activity.id]
        ?? activity.pushToken.map(UptrackLiveActivityLogic.hex)
      if let token {
        tokens.append(
          UptrackLiveActivityLogic.updateTokenPayload(
            token: token, incidentId: activity.attributes.incidentId))
      }
    }
    return tokens
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "list":
      result(
        Self.running().map { activity -> [String: Any] in
          [
            "id": activity.id,
            "incident_id": activity.attributes.incidentId,
            "status": Self.state(of: activity).status,
          ]
        })
    case "start":
      guard let request = UptrackLiveActivityLogic.startRequest(from: call.arguments) else {
        result(FlutterError(code: "BAD_ARGS", message: "incident_id is required", details: nil))
        return
      }
      result(startLocally(request))
    case "end":
      guard let request = UptrackLiveActivityLogic.endRequest(from: call.arguments) else {
        result(FlutterError(code: "BAD_ARGS", message: "an id is required", details: nil))
        return
      }
      let targets = Self.running().filter {
        UptrackLiveActivityLogic.matches(
          request, activityId: $0.id, incidentId: $0.attributes.incidentId)
      }
      for activity in targets {
        Task { await Self.end(activity, resolved: request.resolved, immediate: request.immediate) }
      }
      result(targets.count)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Ends every incident activity at once (logout, R2.4).
  static func endAll() {
    for activity in Activity<UptrackIncident>.activities {
      Task { await end(activity, resolved: false, immediate: true) }
    }
  }

  // MARK: - Private

  private func startLocally(_ request: UptrackLiveActivityLogic.StartRequest) -> String {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    guard UptrackLiveActivityLogic.allowsLocalStart(major: os.majorVersion, minor: os.minorVersion)
    else { return "remote_only" }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return "disabled" }
    // One activity per incident: the last check before the request.
    if Self.running().contains(where: { $0.attributes.incidentId == request.incidentId }) {
      return "exists"
    }
    let attributes = UptrackIncident(
      incidentId: request.incidentId, monitorName: request.monitorName)
    let state = UptrackIncident.ContentState(
      title: request.title, body: request.body, status: request.status)
    do {
      let activity: Activity<UptrackIncident>
      if #available(iOS 16.2, *) {
        activity = try Activity.request(
          attributes: attributes,
          content: ActivityContent(state: state, staleDate: nil),
          pushType: .token)
      } else {
        activity = try Activity.request(
          attributes: attributes, contentState: state, pushType: .token)
      }
      observe(activity)
      return "started"
    } catch {
      return "failed"
    }
  }

  private func observe(_ activity: Activity<UptrackIncident>) {
    guard observed.insert(activity.id).inserted else { return }
    let id = activity.id
    let incidentId = activity.attributes.incidentId
    Task { @MainActor in
      for await data in activity.pushTokenUpdates {
        let hex = UptrackLiveActivityLogic.hex(data)
        self.updateTokens[id] = hex
        self.send(
          "onLiveActivityToken",
          UptrackLiveActivityLogic.updateTokenPayload(token: hex, incidentId: incidentId))
      }
    }
    Task { @MainActor in
      for await state in activity.activityStateUpdates {
        guard state == .ended || state == .dismissed else { continue }
        var payload: [String: Any] = ["incident_id": incidentId]
        if let token = self.updateTokens.removeValue(forKey: id) {
          payload["token"] = token
        }
        self.send("onLiveActivityEnded", payload)
        break
      }
    }
  }

  @MainActor
  private func endDuplicates() async {
    let running = Self.running()
    let extra = Set(
      UptrackLiveActivityLogic.duplicateIds(
        running.map { (id: $0.id, incidentId: $0.attributes.incidentId) }))
    for activity in running where extra.contains(activity.id) {
      await Self.end(activity, resolved: false, immediate: true)
    }
  }

  /// Activities that are still on screen.
  private static func running() -> [Activity<UptrackIncident>] {
    Activity<UptrackIncident>.activities.filter {
      $0.activityState != .ended && $0.activityState != .dismissed
    }
  }

  private static func state(of activity: Activity<UptrackIncident>) -> UptrackIncident.ContentState {
    if #available(iOS 16.2, *) {
      return activity.content.state
    }
    return activity.contentState
  }

  private static func end(
    _ activity: Activity<UptrackIncident>, resolved: Bool, immediate: Bool
  ) async {
    var final: UptrackIncident.ContentState?
    if resolved {
      let content = UptrackLiveActivityLogic.resolvedContent(
        monitorName: activity.attributes.monitorName)
      final = UptrackIncident.ContentState(
        title: content.title, body: content.body, status: "resolved")
    }
    let policy: ActivityUIDismissalPolicy = immediate ? .immediate : .default
    if #available(iOS 16.2, *) {
      await activity.end(
        final.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: policy)
    } else {
      await activity.end(using: final, dismissalPolicy: policy)
    }
  }
}
