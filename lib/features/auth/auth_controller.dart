import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/auth_interceptors.dart';
import '../../api/client.dart';
import '../../api/uptrack_api.dart';
import '../../data/local/database_providers.dart' show cacheRepositoryProvider;
import '../../push/push_channels.dart' show PushChannels;
import '../../widgets/widget_store.dart' show clearWidgetData;
import 'token_storage.dart';

/// Authentication status for the router redirect and login UI.
enum AuthStatus {
  /// No usable credential — the router sends the user to `/login`.
  signedOut,

  /// Password accepted, waiting for the TOTP/backup code.
  needsTwoFactor,

  /// Device token stored and attached to API calls.
  signedIn,
}

/// Immutable auth UI state.
class AuthState {
  const AuthState({
    this.status = AuthStatus.signedOut,
    this.email = '',
    this.deviceTokenId,
    this.errorMessage,
    this.isLoading = false,
    this.magicLinkSent = false,
  });

  final AuthStatus status;
  final String email;
  final String? deviceTokenId;
  final String? errorMessage;
  final bool isLoading;
  final bool magicLinkSent;

  AuthState copyWith({
    AuthStatus? status,
    String? email,
    String? deviceTokenId,
    String? errorMessage,
    bool? isLoading,
    bool? magicLinkSent,
  }) {
    return AuthState(
      status: status ?? this.status,
      email: email ?? this.email,
      deviceTokenId: deviceTokenId ?? this.deviceTokenId,
      errorMessage: errorMessage,
      isLoading: isLoading ?? this.isLoading,
      magicLinkSent: magicLinkSent ?? this.magicLinkSent,
    );
  }
}

/// Pure validators shared by the login screen (unit-tested).
String? validateEmail(String? value) {
  final String trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) {
    return 'Enter your email';
  }
  final List<String> parts = trimmed.split('@');
  if (parts.length != 2 || parts.any((String p) => p.isEmpty)) {
    return 'Enter a valid email';
  }
  if (!parts[1].contains('.')) {
    return 'Enter a valid email';
  }
  return null;
}

String? validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Enter your password';
  }
  return null;
}

String? validateTwoFactorCode(String? value) {
  final String trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) {
    return 'Enter your 2FA code';
  }
  if (trimmed.length < 6) {
    return 'Code must be at least 6 characters';
  }
  return null;
}

/// Parses a magic-link deep link into its `{email, token}` pair.
/// Expected shape: `<scheme>://auth/magic?email=…&token=…`
/// (the path prefix is ignored so hosts like `uptrack.app/magic` also work).
({String email, String token})? parseMagicLink(Uri uri) {
  final String? email = uri.queryParameters['email']?.trim();
  final String? token = uri.queryParameters['token'];
  if (email == null || email.isEmpty || token == null || token.isEmpty) {
    return null;
  }
  return (email: email, token: token);
}

/// Maps a failed auth call to a user-facing message, preferring the
/// server's `error` field when present.
String authErrorMessage(DioException err) {
  final Object? data = err.response?.data;
  if (data is Map<String, Object?>) {
    final Object? serverError = data['error'];
    if (serverError is String && serverError.isNotEmpty) {
      return serverError;
    }
  }
  switch (err.response?.statusCode) {
    case 400:
      return 'That code was not accepted. Try again.';
    case 401:
      return 'Invalid email or password.';
    case 403:
      return 'Sign-in is disabled for this organization. Try SSO or magic link.';
    case 422:
      return 'Check the highlighted fields and try again.';
    default:
      return 'Sign-in failed. Check your connection and try again.';
  }
}

/// In-memory holder for the device token.
///
/// The dio bearer interceptor needs a *synchronous* token lookup while
/// secure storage is async, so the controller mirrors the token here on
/// sign-in/restore and clears it on sign-out/401.
class AuthTokenHolder {
  String? token;
}

final Provider<TokenStore> tokenStoreProvider = Provider<TokenStore>(
  (Ref ref) => SecureTokenStore(),
);

final Provider<AuthTokenHolder> authTokenHolderProvider =
    Provider<AuthTokenHolder>((Ref ref) => AuthTokenHolder());

/// Builds the shared API [Dio]: bearer device token + session-cookie replay
/// (login → device-token exchange) + re-auth on 401.
Dio buildAppDio({
  required AuthTokenHolder holder,
  required void Function() onUnauthorized,
  HttpClientAdapter? adapter,
}) {
  final Dio dio = createApiClient(tokenProvider: () => holder.token);
  if (adapter != null) {
    dio.httpClientAdapter = adapter;
  }
  dio.interceptors.add(SessionCookieInterceptor());
  dio.interceptors.add(UnauthorizedInterceptor(onUnauthorized: onUnauthorized));
  return dio;
}

final Provider<Dio> dioProvider = Provider<Dio>((Ref ref) {
  final AuthTokenHolder holder = ref.watch(authTokenHolderProvider);
  return buildAppDio(
    holder: holder,
    onUnauthorized: () =>
        ref.read(authControllerProvider.notifier).handleUnauthorized(),
  );
});

final Provider<UptrackApi> uptrackApiProvider = Provider<UptrackApi>(
  (Ref ref) => UptrackApi(dio: ref.watch(dioProvider)),
);

final NotifierProvider<AuthController, AuthState> authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Owns the login → device-token → signed-in flow and logout revocation.
class AuthController extends Notifier<AuthState> {
  String? _pendingEmail;
  String? _pendingPassword;

  @override
  AuthState build() {
    // Best-effort restore of a previous session; stays signed out when
    // nothing is stored.
    unawaited(_restore());
    return const AuthState();
  }

  Future<void> _restore() async {
    final TokenStore store = ref.read(tokenStoreProvider);
    final String? token = await store.readDeviceToken();
    if (token == null || token.isEmpty) {
      return;
    }
    ref.read(authTokenHolderProvider).token = token;
    state = state.copyWith(
      status: AuthStatus.signedIn,
      deviceTokenId: await store.readDeviceTokenId(),
    );
  }

  /// Explicit restore for tests/app start when deterministic timing matters.
  Future<void> restore() => _restore();

  /// Password login. On success exchanges the session for a device token;
  /// when the account has 2FA, moves to [AuthStatus.needsTwoFactor] instead.
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      email: email.trim(),
      magicLinkSent: false,
    );
    try {
      final LoginResult result = await ref
          .read(uptrackApiProvider)
          .login(email: email.trim(), password: password);
      if (result.totpRequired) {
        _pendingEmail = email.trim();
        _pendingPassword = password;
        state = state.copyWith(
          status: AuthStatus.needsTwoFactor,
          isLoading: false,
        );
        return;
      }
      await _finishSignIn();
    } on DioException catch (err) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: authErrorMessage(err),
      );
    }
  }

  /// Second step of a 2FA login: resubmits the stored credentials plus code.
  Future<void> submitTwoFactorCode(String code) async {
    final String? email = _pendingEmail;
    final String? password = _pendingPassword;
    if (email == null || password == null) {
      state = state.copyWith(
        status: AuthStatus.signedOut,
        errorMessage: 'Session expired. Sign in again.',
      );
      return;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final LoginResult result = await ref
          .read(uptrackApiProvider)
          .login(email: email, password: password, totpCode: code.trim());
      if (result.totpRequired) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Invalid 2FA code.',
        );
        return;
      }
      await _finishSignIn();
    } on DioException catch (err) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: authErrorMessage(err),
      );
    }
  }

  /// Discards a pending 2FA step and returns to the password form.
  void cancelTwoFactor() {
    _pendingEmail = null;
    _pendingPassword = null;
    state = state.copyWith(status: AuthStatus.signedOut, errorMessage: null);
  }

  /// Sends the passwordless sign-in email.
  Future<void> requestMagicLink(String email) async {
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      email: email.trim(),
      magicLinkSent: false,
    );
    try {
      await ref.read(uptrackApiProvider).requestMagicLink(email: email.trim());
      state = state.copyWith(isLoading: false, magicLinkSent: true);
    } on DioException catch (err) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: authErrorMessage(err),
      );
    }
  }

  /// Consumes `{email, token}` from a magic-link deep link, then performs
  /// the same device-token exchange as password login.
  Future<void> verifyMagicLink({
    required String email,
    required String token,
  }) async {
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      email: email.trim(),
    );
    try {
      await ref
          .read(uptrackApiProvider)
          .verifyMagicLink(email: email.trim(), token: token);
      await _finishSignIn();
    } on DioException catch (err) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: authErrorMessage(err),
      );
    }
  }

  /// Exchanges the login session (replayed cookie) for a device token and
  /// persists it in secure storage.
  Future<void> _finishSignIn() async {
    final DeviceTokenIssuance issuance = await ref
        .read(uptrackApiProvider)
        .createDeviceToken();
    await ref
        .read(tokenStoreProvider)
        .writeDeviceToken(token: issuance.token, id: issuance.id);
    ref.read(authTokenHolderProvider).token = issuance.token;
    _pendingEmail = null;
    _pendingPassword = null;
    state = state.copyWith(
      status: AuthStatus.signedIn,
      deviceTokenId: issuance.id,
      isLoading: false,
      errorMessage: null,
      magicLinkSent: false,
    );
  }

  /// Logout: best-effort server revocation (device token + push
  /// registration + session), then local credential wipe. Server failures
  /// never block local sign-out.
  Future<void> signOut({String? pushToken}) async {
    final UptrackApi api = ref.read(uptrackApiProvider);
    final String? deviceTokenId = state.deviceTokenId;
    if (deviceTokenId != null) {
      try {
        await api.revokeDeviceToken(deviceTokenId);
      } on DioException {
        // Best effort: the local wipe below still signs the user out.
      }
    }
    if (pushToken != null && pushToken.isNotEmpty) {
      try {
        await api.unregisterPushDevice(pushToken);
      } on DioException {
        // Best effort (see above).
      }
    }
    try {
      await api.logout();
    } on DioException {
      // Best effort (see above).
    }
    await ref.read(tokenStoreProvider).clear();
    ref.read(authTokenHolderProvider).token = null;
    _pendingEmail = null;
    _pendingPassword = null;
    state = const AuthState();
    // R2.4: no signed-in incident may linger on the home widget, and no
    // cached monitors/incidents may survive for the next account.
    await clearWidgetData();
    try {
      await ref.read(cacheRepositoryProvider).clearAll();
    } catch (_) {
      // Cache wipe is hygiene, not correctness of sign-out.
    }
    await clearSessionNotifications();
  }

  /// Re-auth on 401: drops a signed-in session back to the login screen.
  /// No-op while signed out or mid-2FA so failed logins keep their
  /// field-level error instead of looping.
  void handleUnauthorized() {
    if (state.status != AuthStatus.signedIn) {
      return;
    }
    ref.read(authTokenHolderProvider).token = null;
    unawaited(ref.read(tokenStoreProvider).clear());
    unawaited(clearWidgetData());
    unawaited(
      ref.read(cacheRepositoryProvider).clearAll().catchError((_) {}),
    );
    unawaited(clearSessionNotifications());
    state = state.copyWith(
      status: AuthStatus.signedOut,
      deviceTokenId: null,
      errorMessage: 'Session expired. Sign in again.',
    );
  }
}

/// Asks the native host to drop the signed-out session's delivered
/// notifications, badge and Live Activities (R2.4; implemented in
/// `AppDelegate.clearSessionNotifications` — Android answers
/// MissingPlugin until it implements the method). Best-effort: never
/// throws, so sign-out can't fail on platform-channel issues.
Future<void> clearSessionNotifications() async {
  try {
    await PushChannels.tokenChannel().invokeMethod(
      'clearSessionNotifications',
    );
  } on MissingPluginException {
    // Host has no such method (Android, tests) — nothing to clear.
  } on PlatformException {
    // Native clear failed — sign-out proceeds regardless.
  }
}
