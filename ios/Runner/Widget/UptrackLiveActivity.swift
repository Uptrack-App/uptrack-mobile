import ActivityKit
import SwiftUI
import WidgetKit

/// Lock-screen and banner view of the incident Live Activity (design A):
/// a status stripe, the monitor name, the alert body and a status pill.
///
/// The elapsed time is not shown here. The activity state carries no start
/// time, and a live timer would need the server to send one (design B).
@available(iOS 16.1, *)
struct UptrackIncidentLockScreen: View {
  let context: ActivityViewContext<UptrackIncident>

  var body: some View {
    let style = UptrackStatusStyle.make(status: context.state.status)
    HStack(spacing: 0) {
      Rectangle().fill(style.color).frame(width: 5)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(context.attributes.monitorName)
          .font(.headline)
          .lineLimit(1)
        Text(context.state.body)
          .font(.subheadline)
          .foregroundStyle(UptrackInk.muted)
          .lineLimit(2)
        HStack {
          UptrackStatusPill(style: style)
          Spacer()
          Text("UPTRACK").font(.caption2).foregroundStyle(UptrackInk.muted)
            .accessibilityHidden(true)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
    }
    .foregroundStyle(UptrackInk.foreground)
    .accessibilityElement(children: .combine)
  }
}

@available(iOS 16.1, *)
struct UptrackIncidentActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: UptrackIncident.self) { context in
      UptrackIncidentLockScreen(context: context)
        .activityBackgroundTint(UptrackInk.surface)
        .activitySystemActionForegroundColor(UptrackInk.foreground)
    } dynamicIsland: { context in
      let style = UptrackStatusStyle.make(status: context.state.status)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.attributes.monitorName).font(.headline).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          UptrackStatusPill(style: style)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.body).font(.subheadline).lineLimit(2)
        }
      } compactLeading: {
        Circle().fill(style.color).frame(width: 10, height: 10)
          .accessibilityLabel("Incident \(style.spokenLabel)")
      } compactTrailing: {
        Image(systemName: style.symbol).foregroundStyle(style.color)
          .accessibilityHidden(true)
      } minimal: {
        Image(systemName: style.symbol).foregroundStyle(style.color)
          .accessibilityLabel("Incident \(style.spokenLabel)")
      }
    }
  }
}
