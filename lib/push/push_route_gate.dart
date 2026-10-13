/// Holds a notification deep link until a session exists (plan 4.2).
///
/// A cold-start tap reaches Dart before the stored device token is restored,
/// so the auth status is still `signedOut`. A direct `router.go` then hits
/// the login redirect, and the restore sends the user to `/`: the incident
/// is lost. The gate parks the newest target and opens it at sign-in.
class PushRouteGate {
  PushRouteGate({required this.isSignedIn, required this.go});

  /// True while a device-token session exists.
  final bool Function() isSignedIn;

  /// The real navigation, e.g. `router.go`.
  final void Function(String location) go;

  String? _pending;

  /// The parked target, if any. Visible for tests.
  String? get pending => _pending;

  /// Opens [location] now, or parks it until [onAuthChanged] reports a
  /// session. A newer tap replaces an older parked one.
  void navigate(String location) {
    if (isSignedIn()) {
      _pending = null;
      go(location);
      return;
    }
    _pending = location;
  }

  /// Opens the parked target once a session exists.
  void onAuthChanged({required bool signedIn}) {
    final String? location = _pending;
    if (!signedIn || location == null) {
      return;
    }
    _pending = null;
    go(location);
  }
}
