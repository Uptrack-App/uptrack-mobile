import Flutter
import UIKit
import UserNotifications
import ActivityKit

/// Native APNs host for the Dart push layer (T028).
///
/// Implements the `push/events` + `push/token` MethodChannel contract declared
/// in `lib/push/push_channels.dart` (T027):
///
/// * `push/token` (Dart → native): `getToken` returns the cached APNs device
///   token (`{token, platform, environment}`) or null when push is
///   unavailable/denied; `getInitialNotification` returns the tap that
///   cold-started the app (`{incident_id?, monitor_id?}`) once, then null.
/// * `push/events` (native → Dart): `onPushToken` on registration,
///   `onTokenRefresh` never fires on iOS (APNs tokens are stable per install;
///   a re-registration re-sends `onPushToken`), `onForegroundMessage` from
///   `willPresent`, `onNotificationTap` / `onNotificationAction` from the
///   response handler.
///
/// Server contract (T017/T019): `apns-collapse-id` equals the incident id, so
/// the client forwards `incident_id` as `collapse_key` — Dart collapses repeat
/// alerts for one incident onto a single notification. Category
/// `UPTRACK_INCIDENT` carries the `UPTRACK_ACK` / `UPTRACK_ESCALATE` /
/// `UPTRACK_SNOOZE` lock-screen actions the backend advertises.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Channel names mirror `PushChannels` in Dart — keep in sync.
  static let eventsChannelName = "app.uptrack.mobile/push/events"
  static let tokenChannelName = "app.uptrack.mobile/push/token"

  /// Category id mirror of `TRIAGE_CATEGORY` in `push_apns.rs`.
  static let triageCategoryId = "UPTRACK_INCIDENT"
  static let ackActionId = "UPTRACK_ACK"
  static let escalateActionId = "UPTRACK_ESCALATE"
  static let snoozeActionId = "UPTRACK_SNOOZE"

  private var eventsChannel: FlutterMethodChannel?
  private var tokenChannel: FlutterMethodChannel?

  /// Hex-encoded APNs device token from the last successful registration.
  private var deviceTokenHex: String?

  /// Tap payload that cold-started the app; drained once via
  /// `getInitialNotification`. Also buffers taps that arrive before the
  /// implicit engine vends its messenger.
  private var initialNotification: [String: String]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.setNotificationCategories([Self.triageCategory()])
    center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
      if granted {
        DispatchQueue.main.async {
          application.registerForRemoteNotifications()
        }
      }
    }

    if let remote = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      initialNotification = Self.tapPayload(from: remote)
    }

    observeLiveActivityPushToStart()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    let events = FlutterMethodChannel(
      name: Self.eventsChannelName, binaryMessenger: messenger)
    let token = FlutterMethodChannel(
      name: Self.tokenChannelName, binaryMessenger: messenger)
    eventsChannel = events
    tokenChannel = token
    token.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "getToken":
        result(self.currentTokenPayload())
      case "getInitialNotification":
        let pending = self.initialNotification
        self.initialNotification = nil
        result(pending)
      case "clearSessionNotifications":
        // R2.4 logout/401 hygiene: no old-account banners, badges or Live
        // Activities may linger for the next account on this device.
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
        if #available(iOS 16.2, *) {
          for activity in Activity<UptrackIncident>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
          }
        }
        UIApplication.shared.applicationIconBadgeNumber = 0
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    // A tap may have arrived before the engine existed; keep it buffered as
    // the initial notification and forward it now that Dart can listen.
    if let pending = initialNotification {
      events.invokeMethod("onNotificationTap", arguments: pending)
    }
  }

  // MARK: - APNs registration

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    deviceTokenHex = hex
    eventsChannel?.invokeMethod(
      "onPushToken", arguments: tokenPayload(token: hex))
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    deviceTokenHex = nil
  }

  // MARK: - UNUserNotificationCenterDelegate

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    let message = Self.messagePayload(from: notification.request.content.userInfo)
    eventsChannel?.invokeMethod("onForegroundMessage", arguments: message)
    // The OS suppresses remote banners while foregrounded; Dart re-displays
    // locally via flutter_local_notifications, but present natively as well so
    // nothing is lost when the Dart isolate is paused.
    return [.banner, .list, .sound, .badge]
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let userInfo = response.notification.request.content.userInfo
    let actionId = response.actionIdentifier
    switch actionId {
    case UNNotificationDefaultActionIdentifier, UNNotificationDismissActionIdentifier:
      if actionId == UNNotificationDismissActionIdentifier { return }
      let payload = Self.tapPayload(from: userInfo)
      forwardOrBuffer(method: "onNotificationTap", payload: payload)
    case Self.ackActionId, Self.escalateActionId, Self.snoozeActionId:
      var payload = Self.tapPayload(from: userInfo)
      payload["action"] = actionId
      forwardOrBuffer(method: "onNotificationAction", payload: payload)
    default:
      return
    }
  }

  // MARK: - Live Activity push-to-start (T055)

  /// Observes ActivityKit push-to-start tokens (iOS 17.2+) and forwards them
  /// to Dart over the `push/events` channel as `onLiveActivityToken`
  /// `{token, kind: push_to_start}`. Dart registers the token with
  /// `POST /api/push/live-activities` (see `LiveActivityRegisterRequest` in
  /// `lib/widgets/live_activity.dart`); the current Dart `_handleMethodCall`
  /// ignores unknown methods, so a Dart handler can land as a follow-up
  /// without breaking this build. Update-token rotation for already-running
  /// activities is out of scope (the server prunes stale rows).
  private func observeLiveActivityPushToStart() {
    if #available(iOS 17.2, *) {
      Task {
        for await data in Activity<UptrackIncident>.pushToStartTokenUpdates {
          let hex = data.map { String(format: "%02x", $0) }.joined()
          let payload = ["token": hex, "kind": "push_to_start"]
          await MainActor.run {
            self.eventsChannel?.invokeMethod("onLiveActivityToken", arguments: payload)
          }
        }
      }
    }
  }

  // MARK: - Helpers

  private static func triageCategory() -> UNNotificationCategory {
    let ack = UNNotificationAction(
      identifier: ackActionId, title: "Acknowledge")
    let escalate = UNNotificationAction(
      identifier: escalateActionId, title: "Escalate")
    let snooze = UNNotificationAction(
      identifier: snoozeActionId, title: "Snooze 1h")
    return UNNotificationCategory(
      identifier: triageCategoryId,
      actions: [ack, escalate, snooze],
      intentIdentifiers: [],
      options: [])
  }

  /// `{token, platform, environment}` for `onPushToken` / `getToken`.
  private func tokenPayload(token: String) -> [String: String] {
    ["token": token, "platform": "ios", "environment": Self.apnsEnvironment()]
  }

  private func currentTokenPayload() -> [String: String]? {
    guard let hex = deviceTokenHex, !hex.isEmpty else { return nil }
    return tokenPayload(token: hex)
  }

  /// Debug builds talk to the sandbox APNs host; everything else is
  /// production. Mirrors the backend `environment` column semantics.
  private static func apnsEnvironment() -> String {
    #if DEBUG
      return "sandbox"
    #else
      return "production"
    #endif
  }

  /// Forwards natively-received taps/actions to Dart, or buffers them as the
  /// cold-start notification when the engine channel is not ready yet.
  private func forwardOrBuffer(method: String, payload: [String: String]) {
    initialNotification = tapOnly(payload)
    eventsChannel?.invokeMethod(method, arguments: payload)
  }

  /// Strips the `action` key: the cold-start deep link only needs routing ids.
  private func tapOnly(_ payload: [String: String]) -> [String: String] {
    var tap = payload
    tap.removeValue(forKey: "action")
    return tap
  }

  /// Foreground payload for `onForegroundMessage`. `collapse_key` mirrors the
  /// server `apns-collapse-id` (== incident id) so Dart can replace the
  /// delivered notification with the same identifier.
  private static func messagePayload(from userInfo: [AnyHashable: Any]) -> [String: String] {
    var payload = tapPayload(from: userInfo)
    if let aps = userInfo["aps"] as? [AnyHashable: Any],
      let alert = aps["alert"] as? [AnyHashable: Any]
    {
      if let title = alert["title"] as? String, !title.isEmpty {
        payload["title"] = title
      }
      if let body = alert["body"] as? String, !body.isEmpty {
        payload["body"] = body
      }
    } else if let alert = userInfo["aps"] as? [AnyHashable: Any],
      let body = alert["alert"] as? String, !body.isEmpty
    {
      payload["body"] = body
    }
    if let severity = userInfo["severity"] as? String, !severity.isEmpty {
      payload["severity"] = severity
    }
    if let incidentId = payload["incident_id"] {
      payload["collapse_key"] = incidentId
    }
    return payload
  }

  /// Routing ids for taps and cold starts.
  private static func tapPayload(from userInfo: [AnyHashable: Any]) -> [String: String] {
    var payload: [String: String] = [:]
    if let incidentId = userInfo["incident_id"] as? String, !incidentId.isEmpty {
      payload["incident_id"] = incidentId
    }
    if let monitorId = userInfo["monitor_id"] as? String, !monitorId.isEmpty {
      payload["monitor_id"] = monitorId
    }
    return payload
  }
}
