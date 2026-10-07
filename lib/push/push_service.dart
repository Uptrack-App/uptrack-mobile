import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'push_channels.dart';
import 'push_actions.dart';
import 'push_message.dart';
import 'push_presentation.dart';
import 'push_registration.dart';
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

/// Removes an ended activity's token from the backend
/// (`DELETE /api/push/live-activities`).
typedef LiveActivityTokenRemoval = Future<void> Function(
  LiveActivityRemoveRequest request,
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

  /// Android 13+ `POST_NOTIFICATIONS` runtime prompt (no-op elsewhere).
  /// Returns whether notifications are allowed.
  Future<bool> requestAndroidPermission() async {
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) {
      return true;
    }
    return await android.requestNotificationsPermission() ?? false;
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
        // A `passive` push (user override or info) keeps its severity
        // channel but must not make a sound or vibrate (plan 4.5).
        silent: PushPresentation.silentOnAndroid(message.interruption),
        // Buttons only with an owner for their taps. The app wires none: a
        // plugin response arrives through the exported launcher activity and
        // can be forged, so triage buttons are drawn natively instead.
        actions: onAction == null
            ? const <AndroidNotificationAction>[]
            : androidActionsFor(message),
      ),
      iOS: darwinDetailsFor(message),
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

  /// iOS details for a local copy of [message].
  ///
  /// On iOS the OS presents remote pushes itself (`willPresent`), so this is
  /// a fallback only; it still keeps the level, the triage actions and the
  /// per-incident thread.
  static DarwinNotificationDetails darwinDetailsFor(PushMessage message) {
    final PushInterruptionLevel level = message.interruption;
    final bool loud = level != PushInterruptionLevel.passive;
    return DarwinNotificationDetails(
      presentBanner: loud,
      presentList: true,
      presentSound: loud,
      interruptionLevel: switch (level) {
        PushInterruptionLevel.passive => InterruptionLevel.passive,
        PushInterruptionLevel.active => InterruptionLevel.active,
        PushInterruptionLevel.timeSensitive => InterruptionLevel.timeSensitive,
      },
      categoryIdentifier: message.target?.kind == PushTargetKind.incident
          ? _iosTriageCategory
          : null,
      threadIdentifier: message.target?.id,
    );
  }

  /// `UNNotificationCategory` with the triage actions (`AppDelegate`).
  static const String _iosTriageCategory = 'UPTRACK_INCIDENT';

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
  /// `showsUserInterface: true` (plan 4.6): with `false` the plugin's
  /// `ActionBroadcastReceiver` starts a background engine for a
  /// background-isolate callback that this app does not register, so the
  /// plugin drops the action ("Callback information could not be
  /// retrieved"). With `true` the tap opens the app and reaches the
  /// main-isolate callback, which hands it to [onAction]; this matches the
  /// iOS actions (`.foreground`) and the native Android action intents.
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
        showsUserInterface: true,
      );
  static const AndroidNotificationAction _escalateAction =
      AndroidNotificationAction(
        PushIntentIdentity.escalate,
        'Escalate',
        showsUserInterface: true,
      );
  static const AndroidNotificationAction _snoozeAction =
      AndroidNotificationAction(
        PushIntentIdentity.snooze,
        'Snooze',
        showsUserInterface: true,
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
    this.unregisterLiveActivity,
    PushRegistrationStore? registrationStore,
    this.isSignedIn,
    this.requestPermission,
    this.waitForSession,
  }) : _events = events ?? PushChannels.eventsChannel(),
       _tokenChannel = tokenChannel ?? PushChannels.tokenChannel(),
       _notifier = notifier ?? FlutterLocalNotificationsNotifier(),
       _platformOverride = platform,
       _store = registrationStore ?? PushRegistrationStore();

  final PushTokenRegistration registerToken;
  final PushNavigation onNavigate;
  final MethodChannel _events;
  final MethodChannel _tokenChannel;
  final LocalNotifier _notifier;
  final TargetPlatform? _platformOverride;
  final PushRegistrationStore _store;

  /// True while a device-token session exists. `POST /api/push/devices`
  /// needs that bearer, so tokens seen while signed out are only recorded
  /// and registered at the next sign-in ([onAuthChanged]). Null (tests of
  /// the plain plumbing) means always signed in.
  final bool Function()? isSignedIn;

  /// Asks for the Android 13+ `POST_NOTIFICATIONS` runtime permission. Without
  /// a grant Android drops every notification, FCM ones included. iOS asks in
  /// the native `getToken` handler instead, so this runs on Android only.
  final Future<bool> Function()? requestPermission;

  bool get _canRegister => isSignedIn?.call() ?? true;

  /// Completes with true once a session is known to exist (the stored device
  /// token was restored, or the user signed in). A lock-screen action waits
  /// for it: on a cold start it arrives before the restore, and a call with
  /// no bearer is a 401 that drops the action. Null means no wait (tests of
  /// the plain plumbing).
  final Future<bool> Function()? waitForSession;

  /// Lock-screen triage executor (T031). Null in tests that only cover the
  /// T027 plumbing — action taps then fall back to a plain deep-link.
  final PushActionHandler? actionHandler;

  /// Live Activity token registration (T061): `POST
  /// /api/push/live-activities` via [UptrackApi.registerLiveActivity].
  /// Null when unwired — `onLiveActivityToken` arrivals are then kept
  /// (push-to-start) or dropped, never crash.
  final LiveActivityTokenRegistration? registerLiveActivity;

  /// Removes an ended activity's token (`onLiveActivityEnded`). Null when
  /// unwired; the server prunes resolved incidents' rows anyway.
  final LiveActivityTokenRemoval? unregisterLiveActivity;

  /// Update `token|incident` pairs the server accepted in this session, so
  /// a token that arrives twice (start-up pull plus the live event) is posted
  /// once. Cleared on sign-out.
  final Set<String> _registeredLiveActivityTokens = <String>{};

  /// FCM data-message handler (T056, Android): when present, foreground
  /// messages delegate here (widget refresh + local display) instead of the
  /// plain [LocalNotifier.showForeground] path.
  final Future<void> Function(Map<Object?, Object?> data)? onForegroundData;

  bool _initialized = false;

  /// Visible for testing.
  bool get isInitialized => _initialized;

  /// Newest push-to-start token the native host reported (iOS 17.2+), and
  /// the APNs environment it came with. The server keeps one per signed-in
  /// device, so it is posted as soon as a session exists, once per token per
  /// session ([PushRegistrationStore.registeredPushToStart]).
  String? _pushToStartToken;
  String? _pushToStartEnvironment;

  /// The push-to-start token being posted now, if any.
  String? _pushToStartInFlight;

  /// Visible for testing.
  String? get pushToStartToken => _pushToStartToken;

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
    final Map<Object?, Object?>? native = await _invokeToken(
      PushTokenMethods.getInitialNotification,
    );
    // The native hosts keep the action of an action button that launched the
    // app (killed state); run it instead of treating it as a body tap.
    final PushActionRequest? initialAction = PushActionRequest.fromMap(native);
    if (initialAction != null) {
      await handleAction(initialAction);
    } else {
      final PushMessage? initial =
          PushMessage.fromMap(native) ?? await _notifier.initialNotification();
      if (initial != null) {
        _navigateFor(initial);
      }
    }
    await registerCurrentToken();
    // Only with a session: signed out, the native buffer keeps the tokens
    // and [onAuthChanged] drains them after sign-in.
    if (_canRegister) {
      await _drainLiveActivityTokens();
    }
  }

  /// Runs one lock-screen action (plan 4.6) from any source: the native
  /// `onNotificationAction` event, the native cold-start payload, or a button
  /// on a notification the Dart renderer showed. Waits for the session first;
  /// with no session nothing runs and the target opens after sign-in.
  Future<void> handleAction(PushActionRequest request) async {
    final Future<bool> Function()? wait = waitForSession;
    final PushActionHandler? handler = actionHandler;
    if (handler == null || (wait != null && !await wait())) {
      // Deep-link so the user can triage manually (after sign-in).
      final String? location = request.routeLocation;
      if (location != null) {
        onNavigate(location);
      }
      return;
    }
    await handler.handle(request);
  }

  /// Follows the auth session (plan 4.3): a sign-in (or a restored session)
  /// registers the device and the Live Activity tokens. Sign-out is handled
  /// by `AuthController.signOut`, which unregisters the token recorded in
  /// [PushRegistrationStore]; here it only forgets what this session posted,
  /// so the next session posts again.
  Future<void> onAuthChanged({required bool signedIn}) async {
    if (!signedIn) {
      _registeredLiveActivityTokens.clear();
      _store.clearRegistered();
      return;
    }
    if (!_initialized) {
      // Not initialized yet: [initialize] registers when it runs.
      return;
    }
    await registerCurrentToken();
    await _drainLiveActivityTokens();
    // A token seen while signed out (or a failed post) when the native pull
    // has nothing new.
    await _postPushToStart();
  }

  /// Registers the Live Activity tokens the native host saw before
  /// [_handleMethodCall] was set. Best-effort.
  Future<void> _drainLiveActivityTokens() async {
    final Object? raw;
    try {
      raw = await _tokenChannel.invokeMethod<Object?>(
        PushTokenMethods.getLiveActivityTokens,
      );
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
    if (raw is! List) {
      return;
    }
    for (final Object? entry in raw) {
      if (entry is Map<Object?, Object?>) {
        await _handleLiveActivityToken(entry);
      }
    }
  }

  /// Asks the native host for its current push token and registers it.
  /// No-op while signed out (no permission prompt on the login screen),
  /// when push is unavailable, or when the host side is not implemented.
  /// Falls back to the last token the host reported (iOS delivers the APNs
  /// token asynchronously, after the permission prompt).
  Future<void> registerCurrentToken() async {
    if (!_canRegister) {
      return;
    }
    if (_currentPlatform() == 'android') {
      await _requestPermission();
    }
    final Map<Object?, Object?>? result = await _invokeToken(
      PushTokenMethods.getToken,
    );
    final PushRegistration? current = result == null
        ? _store.latest
        : _registrationFromMap(result);
    if (current == null) {
      return;
    }
    await _register(current);
  }

  Future<void> _requestPermission() async {
    try {
      await requestPermission?.call();
    } on PlatformException {
      // A denied or failed prompt still lets the token register: the user
      // can enable notifications in Settings later.
    } on MissingPluginException {
      // No plugin host (tests).
    }
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
            // The refresh event carries only the token: keep the
            // environment of the token it replaces (same install).
            final PushRegistration? previous = _store.latest;
            await _seen(
              PushRegistration(
                platform: platform,
                token: token,
                environment: previous?.platform == platform
                    ? previous?.environment
                    : null,
              ),
            );
          }
        }
      case PushEventMethods.onForegroundMessage:
        if (map != null) {
          // An incoming push is a chance to retry a failed post.
          await _postPushToStart();
          final Future<void> Function(Map<Object?, Object?> data)? onData =
              onForegroundData;
          if (onData != null) {
            await onData(map);
          } else {
            final PushMessage? message = PushMessage.fromMap(map);
            // iOS presented it already (willPresent): no second copy.
            if (message != null && !message.presentedByOs) {
              await _notifier.showForeground(message);
            }
          }
        }
      case PushEventMethods.onNotificationTap:
        final PushMessage? message = PushMessage.fromMap(map);
        if (message != null) {
          await _postPushToStart();
          _navigateFor(message);
        }
      case PushEventMethods.onLiveActivityToken:
        await _handleLiveActivityToken(map);
      case PushEventMethods.onLiveActivityEnded:
        await _handleLiveActivityEnded(map);
      case PushEventMethods.onNotificationAction:
        final PushActionRequest? request = PushActionRequest.fromMap(map);
        if (request == null) {
          return;
        }
        await handleAction(request);
    }
  }

  /// Handles one native `onLiveActivityToken` call (T055 contract):
  /// `{token, kind?, incident_id?, expires_in_seconds?, environment?}`.
  ///
  /// * `push_to_start` (the default kind) belongs to the install, not to an
  ///   incident: it is kept and posted as soon as a session exists. An
  ///   `incident_id` on it (old native payload) is ignored.
  /// * `update` names one running activity and needs its `incident_id`.
  ///
  /// Nothing is posted while signed out. Malformed payloads are dropped
  /// silently (never throws).
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
    final String? environment = _knownEnvironment(map['environment']);
    if (kind == 'push_to_start') {
      _pushToStartToken = rawToken;
      _pushToStartEnvironment = environment;
      await _postPushToStart();
      return;
    }
    final Object? rawIncident = map['incident_id'];
    final Object? rawTtl = map['expires_in_seconds'];
    final LiveActivityRegisterRequest request = LiveActivityRegisterRequest(
      incidentId: rawIncident is String && rawIncident.isNotEmpty
          ? rawIncident
          : null,
      token: rawToken,
      kind: kind,
      expiresInSeconds: rawTtl is num ? rawTtl.toInt() : null,
      environment: environment ?? _registrationEnvironment(),
    );
    if (request.validate().isNotEmpty || !_canRegister) {
      return;
    }
    await _registerLiveActivity(request);
  }

  /// Posts the push-to-start token once per token per session: only with a
  /// session, only when the server does not have this token for it yet, and
  /// never twice at once. A failure leaves it unrecorded, so the next
  /// opportunity (token event, incoming push, sign-in, app start) retries.
  Future<void> _postPushToStart() async {
    final LiveActivityTokenRegistration? register = registerLiveActivity;
    final String? token = _pushToStartToken;
    if (register == null ||
        token == null ||
        !_canRegister ||
        _pushToStartInFlight != null ||
        _store.registeredPushToStart == token) {
      return;
    }
    _pushToStartInFlight = token;
    try {
      await register(
        LiveActivityRegisterRequest(
          token: token,
          kind: 'push_to_start',
          environment: _pushToStartEnvironment ?? _registrationEnvironment(),
        ),
      );
      if (_canRegister) {
        _store.markPushToStartRegistered(token);
      }
    } catch (error) {
      debugPrint('push: push-to-start registration failed: $error');
    } finally {
      _pushToStartInFlight = null;
    }
    if (_pushToStartToken != token) {
      // The token rotated during the post.
      await _postPushToStart();
    }
  }

  /// `sandbox` | `production`, or null for anything else.
  static String? _knownEnvironment(Object? raw) =>
      raw is String && kApnsEnvironments.contains(raw) ? raw : null;

  /// The APNs environment of the iOS push-token registration (same
  /// install, same build), for a Live Activity payload without one.
  String? _registrationEnvironment() {
    final PushRegistration? latest = _store.latest;
    return latest?.platform == 'ios'
        ? _knownEnvironment(latest?.environment)
        : null;
  }

  /// Best-effort server registration of an `update` token: provider-side
  /// pruning covers missed tokens, so failures (offline, 404 unknown
  /// incident, 422 resolved) never surface to the platform channel. A pair
  /// the server already accepted in this session is not posted again; a
  /// failed one is retried on the next delivery.
  Future<void> _registerLiveActivity(
    LiveActivityRegisterRequest request,
  ) async {
    final LiveActivityTokenRegistration? register = registerLiveActivity;
    if (register == null) {
      return;
    }
    final String key = '${request.token}|${request.incidentId}';
    if (_registeredLiveActivityTokens.contains(key)) {
      return;
    }
    try {
      await register(request);
      _registeredLiveActivityTokens.add(key);
    } catch (_) {
      // Best-effort only.
    }
  }

  /// Handles one native `onLiveActivityEnded` call (`{token?,
  /// incident_id?}`): removes the ended activity's token from the server.
  /// Not while signed out: logout ends every activity after the session is
  /// gone, and the server already deleted the device's tokens. Never throws.
  Future<void> _handleLiveActivityEnded(Map<Object?, Object?>? map) async {
    final Object? rawToken = map?['token'];
    if (rawToken is! String || rawToken.trim().isEmpty) {
      return;
    }
    _registeredLiveActivityTokens.removeWhere(
      (String key) => key.startsWith('$rawToken|'),
    );
    if (!_canRegister) {
      return;
    }
    final LiveActivityRemoveRequest request = LiveActivityRemoveRequest(
      token: rawToken,
    );
    try {
      await unregisterLiveActivity?.call(request);
    } catch (_) {
      // Best-effort: the server prunes rows of resolved incidents.
    }
  }

  void _navigateFor(PushMessage message) {
    final String? location = message.routeLocation;
    if (location != null) {
      onNavigate(location);
    }
  }

  Future<void> _registerFromMap(Map<Object?, Object?> map) async {
    final PushRegistration? registration = _registrationFromMap(map);
    if (registration != null) {
      await _seen(registration);
    }
  }

  /// Records a token from the native host; registers it when signed in.
  /// The APNs token also brings the environment a push-to-start post may be
  /// missing, so a failed one is retried here too.
  Future<void> _seen(PushRegistration registration) async {
    _store.markSeen(registration);
    if (_canRegister) {
      await _register(registration);
      await _postPushToStart();
    }
  }

  /// Best-effort `POST /api/push/devices`. A failure (offline, 5xx) never
  /// escapes into a platform-channel reply or an unawaited future; the next
  /// sign-in or token event tries again.
  Future<void> _register(PushRegistration registration) async {
    if (_store.registered == registration) {
      return;
    }
    try {
      await registerToken(
        platform: registration.platform,
        token: registration.token,
        environment: registration.environment,
      );
    } on Exception catch (error) {
      debugPrint('push: device registration failed: $error');
      return;
    }
    _store.markRegistered(registration);
  }

  PushRegistration? _registrationFromMap(Map<Object?, Object?> map) {
    final Object? rawToken = map['token'];
    if (rawToken is! String || rawToken.isEmpty) {
      return null;
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
      return null;
    }
    final Object? rawEnvironment = map['environment'];
    return PushRegistration(
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
}
