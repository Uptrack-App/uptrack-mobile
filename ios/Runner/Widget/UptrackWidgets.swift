import SwiftUI
import WidgetKit

/// Widget bundle aggregating the home-screen status widget and the incident
/// Live Activity.
///
/// Deliberately NOT `@main`: these sources compile inside the app target so
/// `xcodebuild -scheme Runner` verifies them, but a WidgetKit extension is
/// a separate binary. When the dedicated extension target is created, move
/// `ios/Runner/Widget/` into it and mark this bundle `@main` there (plus
/// the App Groups entitlement on that target).
@available(iOS 16.1, *)
struct UptrackWidgets: WidgetBundle {
  var body: some Widget {
    UptrackStatusWidget()
    UptrackIncidentActivityWidget()
  }
}
