import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One native push token (`POST /api/push/devices` body fields).
@immutable
class PushRegistration {
  const PushRegistration({
    required this.platform,
    required this.token,
    this.environment,
  });

  /// `ios` | `android`.
  final String platform;

  /// APNs hex token or FCM registration token.
  final String token;

  /// `sandbox` | `production` (iOS only).
  final String? environment;

  @override
  bool operator ==(Object other) =>
      other is PushRegistration &&
      other.platform == platform &&
      other.token == token &&
      other.environment == environment;

  @override
  int get hashCode => Object.hash(platform, token, environment);

  @override
  String toString() => 'PushRegistration($platform)';
}

/// Which push token this session registered with the server (plan 4.3).
///
/// The server keys `push_devices` by user. Revoking the device token does not
/// stop pushes, so sign-out must send `DELETE /api/push/devices` for this
/// token while the device-token bearer is still valid. [PushService] writes
/// here; `AuthController.signOut` reads and clears it.
///
/// It also records the Live Activity push-to-start token this session
/// posted (`POST /api/push/live-activities`), so the token is posted once
/// per token per session and sign-out knows it exists.
class PushRegistrationStore {
  PushRegistration? _registered;
  PushRegistration? _latest;
  String? _pushToStart;

  /// The token the server has for the current session, or null.
  PushRegistration? get registered => _registered;

  /// The newest token the native host reported, registered or not.
  PushRegistration? get latest => _latest;

  /// Records a token the native host reported (before any server call).
  void markSeen(PushRegistration registration) {
    _latest = registration;
  }

  /// Records a successful `POST /api/push/devices`.
  void markRegistered(PushRegistration registration) {
    _latest = registration;
    _registered = registration;
  }

  /// The push-to-start token the server has for the current session, or
  /// null.
  String? get registeredPushToStart => _pushToStart;

  /// Records a successful push-to-start `POST /api/push/live-activities`.
  void markPushToStartRegistered(String token) {
    _pushToStart = token;
  }

  /// Forgets the server registrations (sign-out or 401): the push device and
  /// the push-to-start token. The latest native token is kept so the next
  /// sign-in can register it again.
  void clearRegistered() {
    _registered = null;
    _pushToStart = null;
  }
}

/// Process-wide [PushRegistrationStore].
final Provider<PushRegistrationStore> pushRegistrationStoreProvider =
    Provider<PushRegistrationStore>((Ref ref) => PushRegistrationStore());
