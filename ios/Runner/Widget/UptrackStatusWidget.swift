import SwiftUI
import WidgetKit

/// Colors, label and symbol for one incident status. Design A: a status
/// color plus a text label and a symbol, so color is never the only cue.
///
/// The activity and the widget only know `ongoing` or `resolved`, so the
/// label says ONGOING, not DOWN: an ongoing incident can be degraded.
struct UptrackStatusStyle {
  let label: String
  let spokenLabel: String
  let symbol: String
  let color: Color
  let soft: Color

  static func make(status: String) -> UptrackStatusStyle {
    if status == "resolved" {
      return UptrackStatusStyle(
        label: "RESOLVED", spokenLabel: "resolved",
        symbol: "checkmark.circle.fill",
        color: UptrackInk.up, soft: UptrackInk.upSoft)
    }
    return UptrackStatusStyle(
      label: "ONGOING", spokenLabel: "ongoing",
      symbol: "exclamationmark.triangle.fill",
      color: UptrackInk.down, soft: UptrackInk.downSoft)
  }
}

/// Small rounded label used by the widget and the Live Activity.
struct UptrackStatusPill: View {
  let text: String
  let color: Color
  let soft: Color
  var spoken: String? = nil

  init(style: UptrackStatusStyle) {
    self.text = style.label
    self.color = style.color
    self.soft = style.soft
    self.spoken = "Status: \(style.spokenLabel)"
  }

  init(text: String, color: Color, soft: Color) {
    self.text = text
    self.color = color
    self.soft = soft
  }

  var body: some View {
    Text(text)
      .font(.caption2.weight(.bold))
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .foregroundStyle(color)
      .background(soft, in: Capsule())
      .accessibilityLabel(spoken ?? text.capitalized)
  }
}

extension View {
  /// iOS 17 widgets must draw their background with `containerBackground`;
  /// a plain `.background` shows an "adopt containerBackground" notice.
  @ViewBuilder
  func uptrackWidgetBackground() -> some View {
    if #available(iOS 17.0, *) {
      self.containerBackground(UptrackInk.surface, for: .widget)
    } else {
      self.background(UptrackInk.surface)
    }
  }
}

/// Home-screen status widget: the single most-recent ongoing incident the
/// Dart side snapshots into the shared App Group (`UptrackWidgetData`).
///
/// Refresh contract (see `WidgetRefresher` in
/// `lib/widgets/widget_store.dart`): Dart calls `updateWidget` after every
/// cache refresh / push merge, so the timeline reloads on foreground plus
/// best-effort background pushes — no background fetch is scheduled here.
struct UptrackStatusProvider: TimelineProvider {
  func placeholder(in context: Context) -> UptrackStatusEntry {
    UptrackStatusEntry(date: Date(), snapshot: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (UptrackStatusEntry) -> Void) {
    completion(UptrackStatusEntry(date: Date(), snapshot: UptrackWidgetData.load()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<UptrackStatusEntry>) -> Void) {
    let entry = UptrackStatusEntry(date: Date(), snapshot: UptrackWidgetData.load())
    // Dart drives refreshes via updateWidget; the hourly reload is only a
    // fallback so a stale widget eventually clears after a resolve and the
    // "Stale" wording can appear.
    let next = Date(timeIntervalSinceNow: 3600)
    completion(Timeline(entries: [entry], policy: .after(next)))
  }
}

struct UptrackStatusEntry: TimelineEntry {
  let date: Date
  let snapshot: UptrackWidgetData.Snapshot?
}

struct UptrackStatusWidgetEntryView: View {
  @Environment(\.widgetFamily) private var family
  var entry: UptrackStatusEntry

  var body: some View {
    Group {
      if let snapshot = entry.snapshot {
        incident(snapshot)
      } else {
        empty
      }
    }
    .foregroundStyle(UptrackInk.foreground)
    .uptrackWidgetBackground()
  }

  private func name(_ snapshot: UptrackWidgetData.Snapshot) -> String {
    snapshot.monitorName.isEmpty ? "Incident \(snapshot.incidentId)" : snapshot.monitorName
  }

  private func pills(_ snapshot: UptrackWidgetData.Snapshot, _ style: UptrackStatusStyle) -> some View {
    HStack(spacing: 4) {
      UptrackStatusPill(style: style)
      if snapshot.acknowledged {
        UptrackStatusPill(text: "ACKED", color: UptrackInk.primary, soft: UptrackInk.muted.opacity(0.15))
          .accessibilityLabel("Acknowledged")
      }
    }
  }

  @ViewBuilder
  private func incident(_ snapshot: UptrackWidgetData.Snapshot) -> some View {
    let style = UptrackStatusStyle.make(status: snapshot.status)
    if family == .systemSmall {
      VStack(alignment: .leading, spacing: 4) {
        pills(snapshot, style)
        Spacer(minLength: 0)
        Text(name(snapshot)).font(.subheadline.weight(.semibold)).lineLimit(1)
        Text(snapshot.elapsedLabel)
          .font(.system(size: 28, weight: .semibold, design: .monospaced))
          .foregroundStyle(style.color)
          .accessibilityLabel("Ongoing for \(snapshot.elapsedLabel)")
        if let line = snapshot.updatedLine {
          Text(line).font(.caption2).foregroundStyle(UptrackInk.muted).lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text(name(snapshot)).font(.headline).lineLimit(1)
          pills(snapshot, style)
          if let line = snapshot.updatedLine {
            Text(line).font(.caption2).foregroundStyle(UptrackInk.muted).lineLimit(1)
          }
        }
        Spacer(minLength: 0)
        Text(snapshot.elapsedLabel)
          .font(.system(size: 40, weight: .semibold, design: .monospaced))
          .foregroundStyle(style.color)
          .accessibilityLabel("Ongoing for \(snapshot.elapsedLabel)")
      }
    }
  }

  private var empty: some View {
    VStack(spacing: 4) {
      Text("Uptrack").font(.headline)
      Text("No ongoing incidents").font(.caption).foregroundStyle(UptrackInk.muted)
    }
  }
}

struct UptrackStatusWidget: Widget {
  let kind = "UptrackStatusWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: UptrackStatusProvider()) { entry in
      UptrackStatusWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Uptrack status")
    .description("The most recent ongoing incident.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
