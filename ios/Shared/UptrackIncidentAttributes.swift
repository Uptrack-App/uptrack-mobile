import ActivityKit
import Foundation

/// ActivityKit attributes for the incident Live Activity.
///
/// Shared by the app target (which observes push-to-start tokens and ends
/// activities on logout) and the `UptrackWidgets` extension (which draws the
/// activity). Both targets must compile this exact file.
///
/// The struct name is load-bearing: the backend sends
/// `attributes-type: "UptrackIncident"` (see `LIVE_ACTIVITY_ATTRIBUTES_TYPE`
/// in `crates/api/src/push_live_activity.rs`), and the system matches a
/// remote start push (iOS 17.2+) to this type. `attributes` keys
/// (`incidentId`, `monitorName`) and `content-state` keys (`title`, `body`,
/// `status`) mirror the server's `build_live_activity_payload` 1:1 — the
/// Dart mirror lives in `lib/widgets/live_activity.dart`.
@available(iOS 16.1, *)
struct UptrackIncident: ActivityAttributes {
  /// Incident UUID string (also the `apns-collapse-id` / top-level
  /// `incident_id` reconciliation key).
  let incidentId: String
  /// Monitor display name for the lock-screen header.
  let monitorName: String

  struct ContentState: Codable, Hashable {
    var title: String
    var body: String
    /// `ongoing` or `resolved` (mirrors `LiveActivityState.status`).
    var status: String
  }
}
