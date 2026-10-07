/// How loud one push is (plan 4.5), shared by the iOS and Android renderers.
///
/// The server resolves severity, the user's `severity_overrides` and the
/// quiet-hours downgrade into one level (`resolve_interruption_level` and
/// `effective_interruption_override` in uptrack-server) and sends it as
/// `aps.interruption-level` (iOS) or as FCM `android.priority` NORMAL for
/// `passive` (Android). The native hosts forward it as `interruption_level`.
enum PushInterruptionLevel {
  passive('passive'),
  active('active'),
  timeSensitive('time-sensitive');

  const PushInterruptionLevel(this.wire);

  /// The APNs `interruption-level` value.
  final String wire;

  /// Parses a wire value; null for anything else (`critical` included: the
  /// app holds no Critical Alerts entitlement).
  static PushInterruptionLevel? parse(Object? raw) {
    if (raw is! String) {
      return null;
    }
    final String value = raw.trim();
    for (final PushInterruptionLevel level in values) {
      if (level.wire == value) {
        return level;
      }
    }
    return null;
  }
}

abstract final class PushPresentation {
  /// The level for one push: the server-resolved [interruptionLevel] when it
  /// is a known value, else the server's severity default (`p1`/`p2`
  /// time-sensitive, `p3` active, `info` passive, anything else active).
  static PushInterruptionLevel levelFor({
    String? severity,
    String? interruptionLevel,
  }) {
    final PushInterruptionLevel? resolved = PushInterruptionLevel.parse(
      interruptionLevel,
    );
    if (resolved != null) {
      return resolved;
    }
    return switch (severity?.trim()) {
      'p1' || 'p2' => PushInterruptionLevel.timeSensitive,
      'p3' => PushInterruptionLevel.active,
      'info' => PushInterruptionLevel.passive,
      _ => PushInterruptionLevel.active,
    };
  }

  /// `UNNotificationPresentationOptions` names for a push that arrives while
  /// the app is in the foreground. Mirrored by
  /// `AppDelegate.presentationOptions(forInterruptionLevel:)`; a contract test
  /// compares the two. `passive` goes to the list only, as it would in the
  /// background: no banner and no sound.
  static List<String> iosForegroundOptions(PushInterruptionLevel level) {
    return switch (level) {
      PushInterruptionLevel.passive => const <String>['list'],
      PushInterruptionLevel.active || PushInterruptionLevel.timeSensitive =>
        const <String>['banner', 'list', 'sound', 'badge'],
    };
  }

  /// Android has no interruption level. A `passive` push stays on the
  /// channel the user owns for its severity but makes no sound or vibration.
  static bool silentOnAndroid(PushInterruptionLevel level) =>
      level == PushInterruptionLevel.passive;
}
