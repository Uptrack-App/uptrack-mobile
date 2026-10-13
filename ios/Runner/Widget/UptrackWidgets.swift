import SwiftUI
import WidgetKit

/// Entry point of the `UptrackWidgets` WidgetKit extension: the home-screen
/// status widget plus the incident Live Activity.
///
/// The bundle itself is not availability-gated because the extension supports
/// iOS 16.0. The Live Activity needs iOS 16.1, so it sits behind
/// `#available`.
@main
struct UptrackWidgets: WidgetBundle {
  var body: some Widget {
    UptrackStatusWidget()
    if #available(iOS 16.1, *) {
      UptrackIncidentActivityWidget()
    }
  }
}
