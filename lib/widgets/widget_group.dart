import 'package:home_widget/home_widget.dart';

/// Shared App Group backing the iOS WidgetKit extension + Live Activity
/// (T055) — must match the `com.apple.security.application-groups` entry
/// in `ios/Runner/UptrackMobile.entitlements` and the suite name the
/// WidgetKit timeline + Activity UI read (`UptrackWidgetData.suiteName`).
abstract final class WidgetGroup {
  /// App Group id shared by the app, the WidgetKit extension (future
  /// dedicated target; sources live in `ios/Runner/Widget/` until then),
  /// and the Dart side via `home_widget`.
  static const String appGroupId = 'group.app.uptrack.mobile';

  static bool _configured = false;

  /// Registers the App Group with `home_widget` once; safe to call before
  /// every store op — host errors (tests, unsupported platform) are
  /// swallowed so widget sync never breaks the app path.
  static Future<void> ensureConfigured() async {
    if (_configured) {
      return;
    }
    try {
      await HomeWidget.setAppGroupId(appGroupId);
      _configured = true;
    } on Exception {
      // No platform host (flutter_test, unsupported platform) — the
      // caller still writes best-effort; the extension reads last-known.
    } on StateError {
      // Called before the bindings exist (plain unit test) — same deal.
    }
  }
}
