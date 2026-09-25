import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'push_channels.dart';
import 'push_message.dart';

/// Registers (or re-registers after a token refresh) the native push token
/// with the backend (`POST /api/push/devices`).
typedef PushTokenRegistration = Future<void> Function({
  required String platform,
  required String token,
  String? environment,
});

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
  FlutterLocalNotificationsNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  void Function(PushMessage message)? _onTap;

  @override
  Future<void> initialize({
    required void Function(PushMessage message) onTap,
  }) async {
    _onTap = onTap;
    const InitializationSettings settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _handleResponse,
    );
  }

  @override
  Future<void> showForeground(PushMessage message) async {
    final Importance importance = message.isHighPriority
        ? Importance.high
        : Importance.defaultImportance;
    final NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'uptrack_alerts',
        'Uptrack alerts',
        channelDescription: 'Incident and monitor alerts from Uptrack.',
        importance: importance,
        priority: message.isHighPriority
            ? Priority.high
            : Priority.defaultPriority,
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
    return _messageFromPayload(launch.notificationResponse?.payload);
  }

  void _handleResponse(NotificationResponse response) {
    final PushMessage? message = _messageFromPayload(response.payload);
    if (message != null) {
      _onTap?.call(message);
    }
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

  bool _initialized = false;

  /// Visible for testing.
  bool get isInitialized => _initialized;

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
        final PushMessage? message = PushMessage.fromMap(map);
        if (message != null) {
          await _notifier.showForeground(message);
        }
      case PushEventMethods.onNotificationTap:
        final PushMessage? message = PushMessage.fromMap(map);
        if (message != null) {
          _navigateFor(message);
        }
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
