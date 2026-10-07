// Plain-Swift check for the Live Activity bridge rules. Foundation only, so it
// needs no Xcode target and no simulator:
//   swiftc -parse-as-library -o /tmp/check_live_activity_logic \
//     ios/Runner/UptrackLiveActivityLogic.swift tool/check_live_activity_logic.swift \
//     && /tmp/check_live_activity_logic
import Foundation

@main
struct CheckLiveActivityLogic {
  static var failures = 0

  static func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    if actual != expected {
      failures += 1
      print("FAIL \(label): got \(actual), expected \(expected)")
    }
  }

  static func main() {
    typealias L = UptrackLiveActivityLogic

    // Channel name mirrors kLiveActivityChannel in Dart.
    expect(L.channelName, "app.uptrack.mobile/live_activity", "channel")

    // Local start: iOS 16.1 to 17.1 only (17.2+ is push-to-start).
    expect(L.allowsLocalStart(major: 16, minor: 0), false, "16.0 has no ActivityKit")
    expect(L.allowsLocalStart(major: 16, minor: 1), true, "16.1")
    expect(L.allowsLocalStart(major: 16, minor: 7), true, "16.7")
    expect(L.allowsLocalStart(major: 17, minor: 0), true, "17.0")
    expect(L.allowsLocalStart(major: 17, minor: 1), true, "17.1")
    expect(L.allowsLocalStart(major: 17, minor: 2), false, "17.2")
    expect(L.allowsLocalStart(major: 18, minor: 0), false, "18.0")
    expect(L.allowsLocalStart(major: 15, minor: 9), false, "15.9")

    // Token payloads match the Dart onLiveActivityToken contract and the
    // server's 60 s .. 7 d TTL bounds.
    expect(L.hex(Data([0x00, 0xab, 0x10])), "00ab10", "hex")
    let update = L.updateTokenPayload(token: "abc", incidentId: "inc-1")
    expect(update["token"] as? String, "abc", "update token")
    expect(update["kind"] as? String, "update", "update kind")
    expect(update["incident_id"] as? String, "inc-1", "update incident")
    let ttl = update["expires_in_seconds"] as? Int ?? 0
    expect(ttl >= 60 && ttl <= 604_800, true, "update ttl in server bounds")
    expect(ttl >= 8 * 3600, true, "update ttl covers the 8 h live window")
    let pts = L.pushToStartPayload(token: "p")
    expect(pts["kind"] as? String, "push_to_start", "pts kind")
    expect(pts["incident_id"] == nil, true, "pts has no incident")

    // start arguments (LiveActivityStart.toMap in Dart).
    let start = L.startRequest(from: [
      "incident_id": "inc-1", "monitor_name": "API", "title": "🚨 API is DOWN",
      "body": "Incident opened", "status": "ongoing",
    ] as [String: Any])
    expect(
      start,
      L.StartRequest(
        incidentId: "inc-1", monitorName: "API", title: "🚨 API is DOWN",
        body: "Incident opened", status: "ongoing"),
      "start parse")
    expect(L.startRequest(from: ["monitor_name": "API"] as [String: Any]) == nil, true, "start needs id")
    expect(L.startRequest(from: nil) == nil, true, "start nil")
    expect(
      L.startRequest(from: ["incident_id": "i", "status": "weird"] as [String: Any])?.status,
      "ongoing", "unknown status is ongoing")
    expect(
      L.startRequest(from: ["incident_id": "i", "monitor_name": ""] as [String: Any])?.monitorName,
      "Incident", "empty monitor name falls back")

    // end arguments (LiveActivityEnd.toMap in Dart).
    let resolved = L.endRequest(from: [
      "activity_id": "act-1", "incident_id": "inc-1", "status": "resolved", "immediate": false,
    ] as [String: Any])
    expect(
      resolved,
      L.EndRequest(activityId: "act-1", incidentId: "inc-1", resolved: true, immediate: false),
      "end parse resolved")
    let byIncident = L.endRequest(from: ["incident_id": "inc-1"] as [String: Any])
    expect(byIncident?.immediate, true, "end defaults to immediate")
    expect(L.endRequest(from: ["status": "resolved"] as [String: Any]) == nil, true, "end needs an id")

    // Matching: an activity id wins over the incident id.
    expect(L.matches(resolved!, activityId: "act-1", incidentId: "inc-1"), true, "match id")
    expect(L.matches(resolved!, activityId: "act-2", incidentId: "inc-1"), false, "id is exact")
    expect(L.matches(byIncident!, activityId: "act-9", incidentId: "inc-1"), true, "match incident")
    expect(L.matches(byIncident!, activityId: "act-9", incidentId: "inc-2"), false, "other incident")

    // Resolved content mirrors the server's la_title_body(Resolved).
    let content = L.resolvedContent(monitorName: "API")
    expect(content.title, "✅ API recovered", "resolved title")
    expect(content.body, "Incident resolved", "resolved body")

    // One activity per incident: the first stays, the rest end.
    expect(
      L.duplicateIds([
        (id: "a", incidentId: "inc-1"), (id: "b", incidentId: "inc-2"),
        (id: "c", incidentId: "inc-1"), (id: "d", incidentId: "inc-1"),
      ]),
      ["c", "d"], "duplicates")
    expect(L.duplicateIds([]), [], "no activities")

    if failures == 0 {
      print("OK")
    } else {
      print("\(failures) failure(s)")
      exit(1)
    }
  }
}
