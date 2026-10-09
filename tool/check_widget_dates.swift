// Plain-Swift check for the widget date logic. Foundation only, so it needs no
// Xcode target:
//   swiftc -parse-as-library -o /tmp/check_widget_dates \
//     ios/Runner/Widget/UptrackWidgetData.swift tool/check_widget_dates.swift \
//     && /tmp/check_widget_dates
import Foundation

@main
struct CheckWidgetDates {
  static var failures = 0

  static func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    if actual != expected {
      failures += 1
      print("FAIL \(label): got \(actual), expected \(expected)")
    }
  }

  static func main() {
    let start = ISO8601DateFormatter().date(from: "2026-10-06T10:00:00Z")!
    func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }
    let utc = "2026-10-06T10:00:00Z"

    // Parsing: the shapes Dart's toIso8601String can produce.
    expect(UptrackWidgetData.parseISO(utc) != nil, true, "utc")
    expect(UptrackWidgetData.parseISO("2026-10-06T10:00:00.123Z") != nil, true, "utc ms")
    expect(UptrackWidgetData.parseISO("2026-10-06T10:00:00.123456Z") != nil, true, "utc us")
    expect(UptrackWidgetData.parseISO("2026-10-06T10:00:00.123456") != nil, true, "local us")
    expect(UptrackWidgetData.parseISO("2026-10-06T10:00:00") != nil, true, "local")
    expect(UptrackWidgetData.parseISO("") == nil, true, "empty")
    expect(UptrackWidgetData.parseISO("not a date") == nil, true, "garbage")

    // Elapsed buckets.
    expect(UptrackWidgetData.elapsedLabel(from: utc, now: at(0)), "0m", "0m")
    expect(UptrackWidgetData.elapsedLabel(from: utc, now: at(5)), "5m", "5m")
    expect(UptrackWidgetData.elapsedLabel(from: utc, now: at(125)), "2h", "2h")
    expect(UptrackWidgetData.elapsedLabel(from: utc, now: at(3 * 1440)), "3d", "3d")
    expect(UptrackWidgetData.elapsedLabel(from: utc, now: at(-10)), "0m", "future clamps")
    expect(UptrackWidgetData.elapsedLabel(from: "", now: at(5)), "—", "unknown")

    // Freshness wording matches the Android widget.
    expect(UptrackWidgetData.updatedLine(from: utc, now: at(0)), "Updated just now", "fresh")
    expect(UptrackWidgetData.updatedLine(from: utc, now: at(5)), "Updated 5m ago", "5m")
    expect(UptrackWidgetData.updatedLine(from: utc, now: at(60)), "Updated 1h ago", "60m is not stale")
    expect(UptrackWidgetData.updatedLine(from: utc, now: at(61)), "Stale · updated 1h ago", "61m stale")
    expect(UptrackWidgetData.updatedLine(from: utc, now: at(3000)), "Stale · updated 2d ago", "2d")
    expect(UptrackWidgetData.updatedLine(from: "", now: at(5)), nil, "unknown hides line")
    expect(UptrackWidgetData.updatedLine(from: "garbage", now: at(5)), nil, "garbage hides line")

    if failures == 0 { print("all widget date checks passed") } else { exit(1) }
  }
}
