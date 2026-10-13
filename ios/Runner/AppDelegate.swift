import Flutter
import UIKit
import UserNotifications
import AuthenticationServices

/// Native APNs host for the Dart push layer (T028).
///
/// Implements the `push/events` + `push/token` MethodChannel contract declared
/// in `lib/push/push_channels.dart` (T027):
///
/// * `push/token` (Dart → native): `getToken` returns the cached APNs device
///   token (`{token, platform, environment}`) or null when push is
///   unavailable/denied; `getInitialNotification` returns the tap
///   or action that cold-started the app (`{incident_id?, monitor_id?,
///   action?}`) once, then null.
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
  private var socialSession: ASWebAuthenticationSession?

  /// Hex-encoded APNs device token from the last successful registration.
  private var deviceTokenHex: String?

  /// Tap or action payload that arrived before Dart was ready (cold start);
  /// drained once via `getInitialNotification`. An action keeps its `action`
  /// key so Dart runs it instead of treating it as a body tap.
  private var initialNotification: [String: String]?

  /// `UptrackLiveActivityBridge` on iOS 16.1+, nil on 16.0 (no ActivityKit).
  /// Typed `AnyObject` because the bridge class is availability-gated.
  private var liveActivityBridge: AnyObject?
  /// Set when Dart drains `getInitialNotification` (its event handler is set
  /// by then). Before that, taps and actions are only buffered: a live event
  /// plus the drained buffer would run the same tap or action twice.
  private var dartReady = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.setNotificationCategories([Self.triageCategory()])
    // The permission prompt is raised by Dart's push setup (`getToken`), not
    // here, so the demo app (which never starts push) shows no prompt. An
    // existing grant still refreshes the APNs token on every launch.
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        DispatchQueue.main.async { application.registerForRemoteNotifications() }
      default:
        break
      }
    }

    if let remote = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      initialNotification = Self.tapPayload(from: remote)
    }

    startLiveActivityBridge()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    FlutterMethodChannel(name: "app.uptrack.mobile/auth/browser", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard call.method == "authenticate" else { result(FlutterMethodNotImplemented); return }
        guard let self, self.socialSession == nil,
              let args = call.arguments as? [String: String],
              let raw = args["url"], let url = URL(string: raw),
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host ?? ""))
        else { result(FlutterError(code: "UNAVAILABLE", message: "Sign-in unavailable", details: nil)); return }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "app.uptrack.mobile.auth") { [weak self] callback, error in
          DispatchQueue.main.async {
            self?.socialSession = nil
            if let callback { result(callback.absoluteString) }
            else { result(FlutterError(code: error == nil || (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin ? "CANCELLED" : "FAILED", message: "Sign-in did not complete", details: nil)) }
          }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        self.socialSession = session
        if !session.start() {
          self.socialSession = nil
          result(FlutterError(code: "UNAVAILABLE", message: "Cannot open sign-in", details: nil))
        }
      }
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
        // Asks only while undecided; once granted, APNs delivers the token
        // through `onPushToken` on the events channel.
        UNUserNotificationCenter.current()
          .requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
              DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            }
          }
        result(self.currentTokenPayload())
      case "getInitialNotification":
        self.dartReady = true
        let pending = self.initialNotification
        self.initialNotification = nil
        result(pending)
      case "getLiveActivityTokens":
        // Tokens ActivityKit reported before Dart set its handler.
        if #available(iOS 16.1, *),
          let bridge = self.liveActivityBridge as? UptrackLiveActivityBridge
        {
          result(bridge.currentTokens())
        } else {
          result([])
        }
      case "clearSessionNotifications":
        // R2.4 logout/401 hygiene: no old-account banners, badges or Live
        // Activities may linger for the next account on this device.
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
        // iOS 16.1 has activities too; the bridge ends them with the API
        // each version has (the old 16.2-only check left 16.1 ones running).
        if #available(iOS 16.1, *) {
          UptrackLiveActivityBridge.endAll()
        }
        UIApplication.shared.applicationIconBadgeNumber = 0
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    FlutterMethodChannel(
      name: UptrackLiveActivityLogic.channelName, binaryMessenger: messenger
    ).setMethodCallHandler { [weak self] call, result in
      if #available(iOS 16.1, *),
        let bridge = self?.liveActivityBridge as? UptrackLiveActivityBridge
      {
        bridge.handle(call, result: result)
      } else {
        // iOS 16.0: no ActivityKit. Nothing runs and nothing can start.
        result(call.method == "list" ? [] : "unsupported")
      }
    }
    // A tap that arrived before the engine existed stays buffered; Dart
    // drains it with `getInitialNotification` once its handler is set.
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
    guard notification.request.trigger is UNPushNotificationTrigger else {
      // A local notification, not a server push: show it plainly and do not
      // echo it to Dart as a push.
      return [.banner, .list, .sound]
    }
    let message = Self.messagePayload(from: notification.request.content.userInfo)
    eventsChannel?.invokeMethod("onForegroundMessage", arguments: message)
    // The OS presents the push itself, with the interruption level the server
    // resolved from severity, the user's overrides and quiet hours (plan 4.5).
    // Dart refreshes the widget and shows no second copy (`presented_by_os`).
    return Self.presentationOptions(
      forInterruptionLevel: message["interruption_level"])
  }

  /// Foreground presentation for one push. Mirrors
  /// `PushPresentation.iosForegroundOptions` in Dart (a contract test compares
  /// them): `passive` goes to the list only, as it would in the background.
  static func presentationOptions(forInterruptionLevel level: String?)
    -> UNNotificationPresentationOptions
  {
    switch level {
    case "passive": return [.list]
    default: return [.banner, .list, .sound, .badge]
    }
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

  // MARK: - Live Activity (T055, I2.2)

  /// Starts the Live Activity bridge on iOS 16.1+: update and push-to-start
  /// tokens go to Dart as `onLiveActivityToken`, ended activities as
  /// `onLiveActivityEnded` (see `UptrackLiveActivityBridge`). Events sent
  /// before the engine exists are not lost: Dart pulls the tokens with
  /// `getLiveActivityTokens`.
  private func startLiveActivityBridge() {
    guard #available(iOS 16.1, *) else { return }
    let bridge = UptrackLiveActivityBridge(environment: Self.apnsEnvironment()) {
      [weak self] method, payload in
      DispatchQueue.main.async {
        self?.eventsChannel?.invokeMethod(method, arguments: payload)
      }
    }
    liveActivityBridge = bridge
    bridge.start()
  }

  // MARK: - Helpers

  private static func triageCategory() -> UNNotificationCategory {
    // `.foreground` (plan 4.6): the app uses UIScene. A background action in
    // the killed state connects no scene, so the implicit Flutter engine never
    // runs Dart and the action is lost. Opening the app also requires an
    // unlock before any triage call runs.
    let ack = UNNotificationAction(
      identifier: ackActionId, title: "Acknowledge", options: [.foreground])
    let escalate = UNNotificationAction(
      identifier: escalateActionId, title: "Escalate", options: [.foreground])
    let snooze = UNNotificationAction(
      identifier: snoozeActionId, title: "Snooze 1h", options: [.foreground])
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
  /// production. Mirrors the backend `environment` column semantics. Used
  /// for the push token and for the Live Activity tokens.
  private static func apnsEnvironment() -> String {
    #if DEBUG
      return "sandbox"
    #else
      return "production"
    #endif
  }

  /// Forwards natively-received taps/actions to Dart once it is ready, or
  /// buffers them (action included) for `getInitialNotification`.
  private func forwardOrBuffer(method: String, payload: [String: String]) {
    guard dartReady, let channel = eventsChannel else {
      initialNotification = payload
      return
    }
    channel.invokeMethod(method, arguments: payload)
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
    if let aps = userInfo["aps"] as? [AnyHashable: Any],
      let level = aps["interruption-level"] as? String, !level.isEmpty
    {
      payload["interruption_level"] = level
    }
    if let incidentId = payload["incident_id"] {
      payload["collapse_key"] = incidentId
    }
    // `willPresent` presents it natively; Dart must not show a copy.
    payload["presented_by_os"] = "true"
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

// Uses the active scene for iOS 16+; no embedded webview or browser cookies
// are copied into the Flutter process.
extension AppDelegate: ASWebAuthenticationPresentationContextProviding {
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first(where: { $0.activationState == .foregroundActive })?.windows.first(where: { $0.isKeyWindow })
      ?? scenes.flatMap { $0.windows }.first ?? ASPresentationAnchor()
  }
}
