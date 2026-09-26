import 'package:flutter/services.dart';

/// Method-channel contract between the native hosts (Swift APNs registration
/// lands in T028; Android FCM likewise) and the Dart push layer.
///
/// The native side *calls into* Dart on [events]; Dart *queries* the native
/// side on [token]. No Swift/Kotlin code is written here — these constants
/// are the interface T028 will implement against.
abstract final class PushChannels {
  /// Swift/Kotlin → Dart: token events, foreground messages, tap callbacks.
  static const String events = 'app.uptrack.mobile/push/events';

  /// Dart → Swift/Kotlin: current-token queries and cold-start state.
  static const String token = 'app.uptrack.mobile/push/token';

  /// The default [MethodChannel]s backing [PushService].
  static MethodChannel eventsChannel() =>
      const MethodChannel(PushChannels.events);

  /// The default [MethodChannel]s backing [PushService].
  static MethodChannel tokenChannel() =>
      const MethodChannel(PushChannels.token);
}

/// Method names on [PushChannels.events] (native → Dart).
abstract final class PushEventMethods {
  /// Fresh APNs/FCM token: `{token, platform, environment?}`.
  static const String onPushToken = 'onPushToken';

  /// Rotated APNs/FCM token: `{token}` (platform/environment unchanged).
  static const String onTokenRefresh = 'onTokenRefresh';

  /// Alert payload while the app is foregrounded:
  /// `{title?, body?, incident_id?, monitor_id?, severity?, collapse_key?}`.
  static const String onForegroundMessage = 'onForegroundMessage';

  /// User tapped a notification (background state):
  /// `{incident_id?, monitor_id?}`.
  static const String onNotificationTap = 'onNotificationTap';

  /// User tapped a lock-screen triage action (any app state):
  /// `{action, incident_id?, monitor_id?}` where `action` is one of
  /// `acknowledge`/`escalate`/`snooze` (or the native `UPTRACK_ACK`,
  /// `UPTRACK_ESCALATE`, `UPTRACK_SNOOZE` ids the T028 hosts send).
  static const String onNotificationAction = 'onNotificationAction';
}

/// Method names on [PushChannels.token] (Dart → native).
abstract final class PushTokenMethods {
  /// Returns the current push token (`{token, platform, environment?}`),
  /// or null when push is unavailable/denied.
  static const String getToken = 'getToken';

  /// Notification that cold-started the app (`{incident_id?, monitor_id?}`),
  /// or null for a normal launch.
  static const String getInitialNotification = 'getInitialNotification';
}
