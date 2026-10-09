import Foundation

/// Shared App Group reader for the WidgetKit timeline + Live Activity UI.
///
/// Keys mirror `WidgetDataKeys` in `lib/widgets/widget_snapshot.dart`
/// (T054) — the Dart side writes primitives via `home_widget` after
/// registering the same suite (`WidgetGroup.appGroupId`); the `UptrackWidgets`
/// extension only reads.
///
/// This file imports Foundation only, so the date logic can be checked with a
/// plain `swiftc` script (see `tool/check_widget_dates.swift`).
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

  /// Age beyond which the widget admits staleness. Same value as
  /// `STALE_AFTER_MINUTES` in `UptrackStatusWidgetProvider.kt`: refreshes are
  /// event-driven, so a quiet hour is normal.
  static let staleAfterMinutes = 60

  /// Parses the timestamps Dart writes with `DateTime.toIso8601String`: a UTC
  /// value ends in `Z` and may carry microseconds; a local value has no
  /// offset. Returns nil when the text is empty or unreadable. An unknown time
  /// is never replaced by "now".
  static func parseISO(_ raw: String) -> Date? {
    guard !raw.isEmpty else { return nil }
    let internet = ISO8601DateFormatter()
    internet.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = internet.date(from: raw) { return date }
    internet.formatOptions = [.withInternetDateTime]
    if let date = internet.date(from: raw) { return date }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    let formats = [
      "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
      "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
      "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
      "yyyy-MM-dd'T'HH:mm:ss.SSS",
      "yyyy-MM-dd'T'HH:mm:ss",
    ]
    for format in formats {
      formatter.dateFormat = format
      if let date = formatter.date(from: raw) { return date }
    }
    return nil
  }

  /// `5m` / `2h` / `3d`, the buckets the Dart `elapsedLabel` uses.
  static func elapsedLabel(from raw: String, now: Date = Date()) -> String {
    guard let start = parseISO(raw) else { return "—" }
    let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
    if minutes < 60 { return "\(minutes)m" }
    if minutes < 48 * 60 { return "\(minutes / 60)h" }
    return "\(minutes / (60 * 24))d"
  }

  /// Truthful freshness line, worded like the Android widget:
  /// `Updated 5m ago` or `Stale · updated 2h ago`. Nil when the time is
  /// unknown, so the line is hidden instead of claiming "just now".
  static func updatedLine(from raw: String, now: Date = Date()) -> String? {
    guard let written = parseISO(raw) else { return nil }
    let minutes = max(0, Int(now.timeIntervalSince(written) / 60))
    let relative: String
    switch minutes {
    case ..<1: relative = "just now"
    case ..<60: relative = "\(minutes)m ago"
    case ..<2880: relative = "\(minutes / 60)h ago"
    default: relative = "\(minutes / 1440)d ago"
    }
    return minutes > staleAfterMinutes
      ? "Stale · updated \(relative)" : "Updated \(relative)"
  }

  /// Incident summary backing the home widget timeline entry.
  struct Snapshot {
    let incidentId: String
    let monitorId: String
    let monitorName: String
    let status: String
    let startedAt: String
    let acknowledged: Bool
    let updatedAt: String

    /// Short elapsed label anchored at the incident start ("—" when unknown).
    var elapsedLabel: String { UptrackWidgetData.elapsedLabel(from: startedAt) }

    /// Freshness line, or nil when the sync time is unknown.
    var updatedLine: String? { UptrackWidgetData.updatedLine(from: updatedAt) }
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
      acknowledged: defaults.bool(forKey: acknowledgedKey),
      updatedAt: defaults.string(forKey: updatedAtKey) ?? "")
  }
}
