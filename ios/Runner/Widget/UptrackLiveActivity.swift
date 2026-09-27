import ActivityKit
import SwiftUI
import WidgetKit

/// ActivityKit attributes for the incident Live Activity.
///
/// The struct name is load-bearing: the backend sends
/// `attributes-type: "UptrackIncident"` (see `LIVE_ACTIVITY_ATTRIBUTES_TYPE`
/// in `crates/api/src/push_live_activity.rs`), and the system matches a
/// remote start push (iOS 17.2+) to this type. `attributes` keys
/// (`incidentId`, `monitorName`) and `content-state` keys (`title`, `body`,
/// `status`) mirror the server's `build_live_activity_payload` 1:1 — the
/// Dart mirror lives in `lib/widgets/live_activity.dart` (T054).
///
/// NOTE: T054's `kLiveActivityAttributesType` says
/// `'UptrackIncidentAttributes'`, which does not match the server's
/// `"UptrackIncident"` — the Dart constant needs a follow-up correction;
/// the Swift name here follows the server (authoritative for APNs).
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

@available(iOS 16.1, *)
struct UptrackIncidentActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: UptrackIncident.self) { context in
      // Lock screen / banner: monitor header + alert body, acknowledged
      // state stays out (no sensitive data beyond the push itself).
      VStack(alignment: .leading, spacing: 4) {
        Text(context.attributes.monitorName)
          .font(.headline)
          .lineLimit(1)
        Text(context.state.body)
          .font(.subheadline)
          .lineLimit(2)
        HStack {
          Text(context.state.status.uppercased()).font(.caption2.bold())
          Spacer()
          Text("UPTRACK").font(.caption2).foregroundStyle(.secondary)
        }
      }
      .padding()
      .activityBackgroundTint(.black)
      .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.attributes.monitorName).font(.headline).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.state.status.uppercased()).font(.caption2.bold())
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.body).font(.subheadline).lineLimit(2)
        }
      } compactLeading: {
        Text("!").font(.headline.bold())
      } compactTrailing: {
        Text(context.state.status == "resolved" ? "✓" : "●")
          .font(.caption2.bold())
      } minimal: {
        Text(context.state.status == "resolved" ? "✓" : "●")
          .font(.caption2.bold())
      }
    }
  }
}
