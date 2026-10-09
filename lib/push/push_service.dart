import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'push_channels.dart';
import 'push_actions.dart';
import 'push_message.dart';
import '../widgets/live_activity.dart';

/// Registers (or re-registers after a token refresh) the native push token
/// with the backend (`POST /api/push/devices`).
typedef PushTokenRegistration = Future<void> Function({
  required String platform,
  required String token,
  String? environment,
});

/// Registers a Live Activity push token with the backend
/// (`POST /api/push/live-activities`, device-token Bearer auth).
typedef LiveActivityTokenRegistration = Future<void> Function(
  LiveActivityRegisterRequest request,
);

/// Deep-link navigation for a notification tap, e.g. `router.go`.
typedef PushNavigation = void Function(String location);

/// Foreground display + cold-start tap lookup behind a seam the tests fake.
///
/// The production implementation delegates to
/// [FlutterLocalNotificationsPlugin]; tests inject a fake.
abstract class LocalNotifier {
  /// Shows one foreground alert for [message] (the OS suppresses remote
  /// banners while the app is foregrounded, so Dart re-displays locally).
  Future<void> showForeground(PushMessage message);

  /// The tap that launched the app from a killed state, if any.
  Future<PushMessage?> initialNotification();

  /// Arms the plugin; [onTap] fires for taps in foreground/background.
  Future<void> initialize({required void Function(PushMessage message) onTap});
}

/// [LocalNotifier] backed by `flutter_local_notifications`.
class FlutterLocalNotificationsNotifier implements LocalNotifier {
  FlutterLocalNotificationsNotifier({
    FlutterLocalNotificationsPlugin? plugin,
    this.onAction,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  void Function(PushMessage message)? _onTap;

  /// Receives an action-button tap instead of a body tap (R3).
  ///
  /// Constructor-injected rather than added to [LocalNotifier.initialize] on
  /// purpose: `PushService` wires no callback here, so this early slice never
  /// navigates or calls an API from an action tap — it only refuses to
  /// pretend the tap was a body tap. The single owner that waits for auth and
  /// owns authoritative execution passes the callback in later, and can hand
  /// the parsed request straight to `PushActionHandler.handle`.
  final void Function(PushActionRequest request)? onAction;

  /// The last action tap that had no [onAction] owner, or an unusable/unknown
  /// action id. Visible for tests and diagnostics; R3's truthful outcome
  /// surfacing (performed/no-op/error/auth-expired) is deferred to the single
  /// owner, so nothing here claims an outcome.
  PushActionRequest? lastUnhandledAction;

  @override
  Future<void> initialize({
    required void Function(PushMessage message) onTap,
  }) async {
    _onTap = onTap;
    const InitializationSettings settings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _handleResponse,
    );
  }

  @override
  Future<void> showForeground(PushMessage message) async {
    final PushChannelSpec channel = message.severityChannel;
    final NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        // Requested per channel *at creation only* (the plugin calls
        // createNotificationChannel, which Android applies to new channels and
        // ignores for existing ones — a user-owned importance is never
        // changed). The notification-level priority must agree with the
        // channel, or the OS silently downgrades it.
        importance: importanceFor(channel.importance),
        priority: priorityFor(channel.importance),
        category: AndroidNotificationCategory.event,
        // No DND claim: this app never requests a bypass, so the user's own
        // Do Not Disturb / channel settings always win.
        channelBypassDnd: false,
        actions: androidActionsFor(message),
      ),
      iOS: const DarwinNotificationDetails(),
    );
    await _plugin.show(
      id: message.notificationId,
      title: message.title ?? 'Uptrack',
      body: message.body ?? '',
      notificationDetails: details,
      payload: jsonEncode(message.toMap()),
    );
  }

  @override
  Future<PushMessage?> initialNotification() async {
    final NotificationAppLaunchDetails? launch = await _plugin
        .getNotificationAppLaunchDetails();
    if (launch == null || !launch.didNotificationLaunchApp) {
      return null;
    }
    final NotificationResponse? response = launch.notificationResponse;
    // A cold start on an *action* button preserves the action, never the tap:
    // returning a PushMessage here would route it as a plain body tap. The
    // action is recorded and handed to [onAction] instead, and reporting the
    // incident detail (or executing anything) waits for the owner that waits
    // for auth.
    final String? actionId = response?.actionId;
    if (actionId != null && actionId.isNotEmpty) {
      final PushActionRequest? request = _requestFor(
        actionId,
        response?.payload,
      );
      if (request != null) {
        lastUnhandledAction = request;
        onAction?.call(request);
      }
      return null;
    }
    return _messageFromPayload(response?.payload);
  }

  /// Android importance for a channel definition.
  ///
  /// Public and static so the channel-contract test can assert the renderer
  /// maps every severity onto the exact `Importance` the channel declares.
  static Importance importanceFor(PushChannelImportance importance) {
    return switch (importance) {
      PushChannelImportance.high => Importance.high,
      PushChannelImportance.standard => Importance.defaultImportance,
      PushChannelImportance.low => Importance.low,
    };
  }

  /// Android notification priority matching [importanceFor].
  static Priority priorityFor(PushChannelImportance importance) {
    return switch (importance) {
      PushChannelImportance.high => Priority.high,
      PushChannelImportance.standard => Priority.defaultPriority,
      PushChannelImportance.low => Priority.low,
    };
  }

  /// Action buttons offered on an Android notification (R3), in a fixed order.
  ///
  /// * Incident target → Acknowledge, Escalate, Snooze. Snooze is
  ///   incident-scoped on the wire: the handler resolves the monitor
  ///   server-side, exactly like the existing deep-link fallback.
  /// * Monitor-only target → Snooze alone. Acknowledge/Escalate are
  ///   incident-scoped endpoints, so offering them here would advertise an
  ///   action that cannot apply.
  /// * No usable target → no actions. An alert with nothing to triage gets a
  ///   body tap only.
  ///
  /// `showsUserInterface: false`: this renderer only serves the foreground
  /// path, where the app is already in front, and an action must not pull the
  /// UI forward on its own.
  static List<AndroidNotificationAction> androidActionsFor(
    PushMessage message,
  ) {
    final PushTarget? target = message.target;
    if (target == null) {
      return const <AndroidNotificationAction>[];
    }
    final List<AndroidNotificationAction> actions =
        <AndroidNotificationAction>[];
    if (target.kind == PushTargetKind.incident) {
      actions
        ..add(_acknowledgeAction)
        ..add(_escalateAction);
    }
    actions.add(_snoozeAction);
    return List<AndroidNotificationAction>.unmodifiable(actions);
  }

  void _handleResponse(NotificationResponse response) {
    final String actionId = response.actionId ?? '';
    if (actionId.isNotEmpty) {
      // An action is never a tap: no `_onTap`, no navigation, no API call.
      final PushActionRequest? request = _requestFor(
        actionId,
        response.payload,
      );
      if (request == null) {
        // Unknown action id (or a payload with no usable target): ignored,
        // never downgraded into a body tap.
        return;
      }
      lastUnhandledAction = request;
      onAction?.call(request);
      return;
    }
    final PushMessage? message = _messageFromPayload(response.payload);
    if (message != null) {
      _onTap?.call(message);
    }
  }

  /// Parses an action-button tap into the approved [PushActionRequest] shape,
  /// reusing `PushAction.parse` for the action id and the notification payload
  /// for the target ids. Null for an unknown action id or an unusable target —
  /// the caller then ignores it rather than routing it as a tap.
  PushActionRequest? _requestFor(String actionId, String? payload) {
    final PushMessage? message = _messageFromPayload(payload);
    final PushTarget? target = message?.target;
    if (target == null) {
      return null;
    }
    final Map<String, Object?> map = <String, Object?>{
      'action': actionId,
      if (target.kind == PushTargetKind.incident)
        'incident_id': target.id
      else
        'monitor_id': target.id,
    };
    return PushActionRequest.fromMap(map);
  }

  /// Decodes a local-notification payload back into a [PushMessage];
  /// null for missing or malformed payloads (never throws).
  PushMessage? _messageFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(payload);
      if (decoded is Map<String, Object?>) {
        return PushMessage.fromMap(decoded);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static const AndroidNotificationAction _acknowledgeAction =
      AndroidNotificationAction(
        PushIntentIdentity.acknowledge,
        'Acknowledge',
        showsUserInterface: false,
      );
  static const AndroidNotificationAction _escalateAction =
      AndroidNotificationAction(
        PushIntentIdentity.escalate,
        'Escalate',
        showsUserInterface: false,
      );
  static const AndroidNotificationAction _snoozeAction =
      AndroidNotificationAction(
        PushIntentIdentity.snooze,
        'Snooze',
        showsUserInterface: false,
      );
}

/// Dart-side push plumbing: native token events, foreground display,
/// and deep-link routing for notification taps.
///
/// The native hosts (Swift APNs registration in T028, Android FCM likewise)
/// call into Dart over [PushChannels.events]; Dart queries the current token
/// and the cold-start notification over [PushChannels.token]. All platform
/// seams are constructor-injected so the whole flow is testable with a fake
/// [MethodChannel] — no Swift/Kotlin is written here.
class PushService {
  PushService({
    required this.registerToken,
    required this.onNavigate,
    MethodChannel? events,
    MethodChannel? tokenChannel,
    LocalNotifier? notifier,
    TargetPlatform? platform,
    this.actionHandler,
    this.onForegroundData,
    this.registerLiveActivity,
  }) : _events = events ?? PushChannels.eventsChannel(),
       _tokenChannel = tokenChannel ?? PushChannels.tokenChannel(),
       _notifier = notifier ?? FlutterLocalNotificationsNotifier(),
       _platformOverride = platform;

  final PushTokenRegistration registerToken;
  final PushNavigation onNavigate;
  final MethodChannel _events;
  final MethodChannel _tokenChannel;
  final LocalNotifier _notifier;
  final TargetPlatform? _platformOverride;

  /// Lock-screen triage executor (T031). Null in tests that only cover the
  /// T027 plumbing — action taps then fall back to a plain deep-link.
  final PushActionHandler? actionHandler;

  /// Live Activity token registration (T061): `POST
  /// /api/push/live-activities` via [UptrackApi.registerLiveActivity].
  /// Null when unwired — `onLiveActivityToken` arrivals are then parked
  /// (push-to-start) or dropped, never crash.
  final LiveActivityTokenRegistration? registerLiveActivity;

  /// FCM data-message handler (T056, Android): when present, foreground
  /// messages delegate here (widget refresh + local display) instead of the
  /// plain [LocalNotifier.showForeground] path.
  final Future<void> Function(Map<Object?, Object?> data)? onForegroundData;

  bool _initialized = false;

  /// Visible for testing.
  bool get isInitialized => _initialized;

  /// Parked push-to-start token: the native host (T055) reports it before
  /// any incident exists, but `POST /api/push/live-activities` requires an
  /// `incident_id` — so it waits here until the next incident-scoped push
  /// arrives, then registers once. Visible for testing.
  LiveActivityRegisterRequest? pendingLiveActivityToken;

  /// Arms the native→Dart handler, the local-notification plugin, drains any
  /// cold-start tap (killed state), and registers the current token.
  /// Safe to call once; native queries degrade to no-ops when the host side
  /// (T028) is not implemented yet.
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _events.setMethodCallHandler(_handleMethodCall);
    await _notifier.initialize(onTap: _navigateFor);
    final PushMessage? initial =
        await _nativeInitialNotification() ??
        await _notifier.initialNotification();
    if (initial != null) {
      _navigateFor(initial);
    }
    await registerCurrentToken();
  }

  /// Asks the native host for its current push token and registers it.
  /// No-op when push is unavailable or the host side is not implemented yet.
  Future<void> registerCurrentToken() async {
    final Map<Object?, Object?>? result = await _invokeToken(
      PushTokenMethods.getToken,
    );
    if (result == null) {
      return;
    }
    await _registerFromMap(result);
  }

  /// Handles one native→Dart call on [PushChannels.events] (also invoked
  /// directly by tests with a fake channel).
  Future<void> _handleMethodCall(MethodCall call) async {
    final Object? args = call.arguments;
    final Map<Object?, Object?>? map = args is Map<Object?, Object?>
        ? args
        : null;
    switch (call.method) {
      case PushEventMethods.onPushToken:
        if (map != null) {
          await _registerFromMap(map);
        }
      case PushEventMethods.onTokenRefresh:
        final String? token = map?['token'] is String
            ? map!['token']! as String
            : null;
        if (token != null && token.isNotEmpty) {
          final String? platform = _currentPlatform();
          if (platform != null) {
            await registerToken(platform: platform, token: token);
          }
        }
      case PushEventMethods.onForegroundMessage:
        if (map != null) {
          await _flushPendingLiveActivityToken(map);
          final Future<void> Function(Map<Object?, Object?> data)? onData =
              onForegroundData;
          if (onData != null) {
            await onData(map);
          } else {
            final PushMessage? message = PushMessage.fromMap(map);
            if (message != null) {
              await _notifier.showForeground(message);
            }
          }
        }
      case PushEventMethods.onNotificationTap:
        final PushMessage? message = PushMessage.fromMap(map);
        if (message != null) {
          if (map != null) {
            await _flushPendingLiveActivityToken(map);
          }
          _navigateFor(message);
        }
      case PushEventMethods.onLiveActivityToken:
        await _handleLiveActivityToken(map);
      case PushEventMethods.onNotificationAction:
        final PushActionRequest? request = PushActionRequest.fromMap(map);
        if (request == null) {
          return;
        }
        final PushActionHandler? handler = actionHandler;
        if (handler != null) {
          await handler.handle(request);
        } else {
          // Pre-wiring fallback: deep-link so the user can triage manually.
          final String? location = request.routeLocation;
          if (location != null) {
            onNavigate(location);
          }
        }
    }
  }

  /// Handles one native `onLiveActivityToken` call (T055 contract):
  /// `{token, kind?, incident_id?, expires_in_seconds?}`.
  ///
  /// The `POST /api/push/live-activities` endpoint requires an
  /// `incident_id`, but the push-to-start bootstrap token arrives before any
  /// incident exists — so an unscoped token is parked in
  /// [pendingLiveActivityToken] and flushed on the next incident push.
  /// Malformed payloads are dropped silently (never throws).
  Future<void> _handleLiveActivityToken(Map<Object?, Object?>? map) async {
    if (map == null) {
      return;
    }
    final Object? rawToken = map['token'];
    if (rawToken is! String || rawToken.trim().isEmpty) {
      return;
    }
    final Object? rawKind = map['kind'];
    final String kind = rawKind is String && rawKind.isNotEmpty
        ? rawKind
        : 'push_to_start';
    final Object? rawIncident = map['incident_id'];
    final String? incidentId = rawIncident is String && rawIncident.isNotEmpty
        ? rawIncident
        : null;
    final Object? rawTtl = map['expires_in_seconds'];
    final int? expiresInSeconds = rawTtl is num ? rawTtl.toInt() : null;
    if (incidentId == null) {
      // Bootstrap token with no incident to scope it to: park it for the
      // flush, but only for push_to_start (an unscoped `update` token names
      // no locally-started activity and is useless).
      if (kind == 'push_to_start') {
        pendingLiveActivityToken = LiveActivityRegisterRequest(
          incidentId: '',
          token: rawToken,
          kind: kind,
          expiresInSeconds: expiresInSeconds,
        );
      }
      return;
    }
    final LiveActivityRegisterRequest request = LiveActivityRegisterRequest(
      incidentId: incidentId,
      token: rawToken,
      kind: kind,
      expiresInSeconds: expiresInSeconds,
    );
    if (request.validate().isNotEmpty) {
      return;
    }
    await _registerLiveActivity(request);
  }

  /// Registers a parked push-to-start token against the incident named by
  /// an incoming push (`onForegroundMessage` / `onNotificationTap`); a
  /// no-op without a parked token or without an `incident_id`. One-shot:
  /// the server upserts on `(token)`, so the parked copy is cleared after
  /// the attempt regardless of outcome.
  Future<void> _flushPendingLiveActivityToken(Map<Object?, Object?> map) async {
    final LiveActivityRegisterRequest? pending = pendingLiveActivityToken;
    if (pending == null) {
      return;
    }
    final Object? rawIncident = map['incident_id'];
    if (rawIncident is! String || rawIncident.isEmpty) {
      return;
    }
    pendingLiveActivityToken = null;
    final LiveActivityRegisterRequest request = LiveActivityRegisterRequest(
      incidentId: rawIncident,
      token: pending.token,
      kind: pending.kind,
      expiresInSeconds: pending.expiresInSeconds,
    );
    if (request.validate().isNotEmpty) {
      return;
    }
    await _registerLiveActivity(request);
  }

  /// Best-effort server registration: provider-side pruning covers missed
  /// tokens, so failures (offline, 404 unknown incident, 422 resolved)
  /// never surface to the platform channel.
  Future<void> _registerLiveActivity(
    LiveActivityRegisterRequest request,
  ) async {
    try {
      await registerLiveActivity?.call(request);
    } catch (_) {
      // Best-effort only.
    }
  }

  void _navigateFor(PushMessage message) {
    final String? location = message.routeLocation;
    if (location != null) {
      onNavigate(location);
    }
  }

  Future<void> _registerFromMap(Map<Object?, Object?> map) async {
    final Object? rawToken = map['token'];
    if (rawToken is! String || rawToken.isEmpty) {
      return;
    }
    final Object? rawPlatform = map['platform'];
    final String? platform = rawPlatform is String && rawPlatform.isNotEmpty
        ? rawPlatform
        : _currentPlatform();
    final String platformName;
    if (platform is String && (platform == 'ios' || platform == 'android')) {
      platformName = platform;
    } else {
      // The backend only accepts ios|android; anything else (desktop builds,
      // simulators without push) must not reach `POST /api/push/devices`.
      return;
    }
    final Object? rawEnvironment = map['environment'];
    await registerToken(
      platform: platformName,
      token: rawToken,
      environment: rawEnvironment is String && rawEnvironment.isNotEmpty
          ? rawEnvironment
          : null,
    );
  }

  /// `ios`/`android` on supported devices, null elsewhere (incl. tests that
  /// pass no [platform] override).
  String? _currentPlatform() {
    final TargetPlatform platform = _platformOverride ?? defaultTargetPlatform;
    switch (platform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return null;
    }
  }

  Future<Map<Object?, Object?>?> _invokeToken(String method) async {
    try {
      final Object? result = await _tokenChannel.invokeMethod<Object?>(method);
      if (result is Map<Object?, Object?>) {
        return result;
      }
      return null;
    } on MissingPluginException {
      // Host side (T028) not implemented yet — not an error.
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<PushMessage?> _nativeInitialNotification() async {
    final Map<Object?, Object?>? result = await _invokeToken(
      PushTokenMethods.getInitialNotification,
    );
    return PushMessage.fromMap(result);
  }
}
