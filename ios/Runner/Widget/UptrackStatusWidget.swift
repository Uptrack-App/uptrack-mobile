import SwiftUI
import WidgetKit

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
    // fallback so a stale widget eventually clears after a resolve.
    let next = Date(timeIntervalSinceNow: 3600)
    completion(Timeline(entries: [entry], policy: .after(next)))
  }
}

struct UptrackStatusEntry: TimelineEntry {
  let date: Date
  let snapshot: UptrackWidgetData.Snapshot?
}

struct UptrackStatusWidgetEntryView: View {
  var entry: UptrackStatusEntry

  var body: some View {
    if let snapshot = entry.snapshot {
      VStack(alignment: .leading, spacing: 4) {
        Text(snapshot.monitorName.isEmpty ? "Incident \(snapshot.incidentId)" : snapshot.monitorName)
          .font(.headline)
          .lineLimit(1)
        HStack(spacing: 6) {
          Text(snapshot.status.uppercased())
            .font(.caption2.bold())
          if snapshot.acknowledged {
            Text("ACKED").font(.caption2.bold())
          }
          Spacer()
          Text(snapshot.elapsedLabel).font(.caption2.monospacedDigit())
        }
        .foregroundStyle(UptrackInk.muted)
      }
      .padding()
      .foregroundStyle(UptrackInk.foreground)
      .background(UptrackInk.surface)
    } else {
      VStack(spacing: 4) {
        Text("Uptrack").font(.headline)
        Text("No ongoing incidents").font(.caption).foregroundStyle(UptrackInk.muted)
      }
      .padding()
      .foregroundStyle(UptrackInk.foreground)
      .background(UptrackInk.surface)
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
