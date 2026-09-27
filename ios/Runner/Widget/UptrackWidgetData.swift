import Foundation

/// Shared App Group reader for the WidgetKit timeline + Live Activity UI.
///
/// Keys mirror `WidgetDataKeys` in `lib/widgets/widget_snapshot.dart`
/// (T054) — the Dart side writes primitives via `home_widget` after
/// registering the same suite (`WidgetGroup.appGroupId`); the widget
/// extension (future dedicated target; these sources compile inside the
/// app target until then) only reads.
enum UptrackWidgetData {
  /// Must match `WidgetGroup.appGroupId` and the
  /// `com.apple.security.application-groups` entitlement.
  static let suiteName = "group.app.uptrack.mobile"

  private static let prefix = "uptrack_widget_"
  private static let incidentIdKey = prefix + "incident_id"
  private static let monitorIdKey = prefix + "monitor_id"
  private static let monitorNameKey = prefix + "monitor_name"
  private static let statusKey = prefix + "status"
  private static let startedAtKey = prefix + "started_at"
  private static let acknowledgedKey = prefix + "acknowledged"
  private static let updatedAtKey = prefix + "updated_at"

  /// Incident summary backing the home widget timeline entry.
  struct Snapshot {
    let incidentId: String
    let monitorId: String
    let monitorName: String
    let status: String
    let startedAt: String
    let acknowledged: Bool

    /// Short elapsed label (`5m`/`2h`/`3d`) anchored at the incident start
    /// (falls back to "—" when the timestamp is missing or unparseable).
    var elapsedLabel: String {
      let formatter = ISO8601DateFormatter()
      guard !startedAt.isEmpty,
        let start = formatter.date(from: startedAt)
      else { return "—" }
      let minutes = max(0, Int(Date().timeIntervalSince(start) / 60))
      if minutes < 60 { return "\(minutes)m" }
      if minutes < 48 * 60 { return "\(minutes / 60)h" }
      return "\(minutes / (60 * 24))d"
    }
  }

  /// Reads the last snapshot the Dart side wrote; nil on a fresh install
  /// or after a resolve cleared the widget.
  static func load() -> Snapshot? {
    guard let defaults = UserDefaults(suiteName: suiteName),
      let incidentId = defaults.string(forKey: incidentIdKey),
      !incidentId.isEmpty,
      let monitorId = defaults.string(forKey: monitorIdKey),
      !monitorId.isEmpty,
      let status = defaults.string(forKey: statusKey),
      !status.isEmpty
    else { return nil }
    return Snapshot(
      incidentId: incidentId,
      monitorId: monitorId,
      monitorName: defaults.string(forKey: monitorNameKey) ?? "",
      status: status,
      startedAt: defaults.string(forKey: startedAtKey) ?? "",
      acknowledged: defaults.bool(forKey: acknowledgedKey))
  }
}
