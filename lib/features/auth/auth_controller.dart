import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/auth_interceptors.dart';
import '../../api/client.dart';
import '../../api/uptrack_api.dart';
import '../../data/local/database_providers.dart' show cacheRepositoryProvider;
import '../../push/push_channels.dart' show PushChannels;
import '../../push/push_registration.dart';
import '../../widgets/live_activity.dart' show LiveActivityRemoveRequest;
import '../../widgets/widget_store.dart' show clearWidgetData;
import 'token_storage.dart';
import 'social_login.dart';

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
/// Accept only Uptrack app callbacks and the actual HTTPS email route.
({String email, String token})? parseMagicLink(Uri uri) {
  final isApp =
      uri.scheme == 'uptrack' && uri.host == 'auth' && uri.path == '/magic';
  final isWeb =
      uri.scheme == 'https' &&
      uri.host == 'uptrack.app' &&
      uri.path == '/auth/verify-magic-link';
  if (!isApp && !isWeb) return null;
  final String? email = uri.queryParameters['email']?.trim();
  final String? token = uri.queryParameters['token'];
  if (validateEmail(email) != null || token == null || token.isEmpty) {
    return null;
  }
  return (email: email!, token: token);
}

/// Web-created accounts have no password. Accept the actual emailed sign-in
/// link as well as its raw token, without asking users to extract URL fields.
String? magicLinkInputToken({required String input, required String email}) {
  final String value = input.trim();
  if (value.isEmpty) return null;
  if (!value.contains('://')) return value;
  final Uri? uri = Uri.tryParse(value);
  if (uri == null) return null;
  final parsed = parseMagicLink(uri);
  return parsed != null &&
          parsed.email.toLowerCase() == email.trim().toLowerCase()
      ? parsed.token
      : null;
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
      return 'This sign-in link or code is invalid or has expired. Request a new link.';
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

/// Nullary wrapper so the widget wipe can be handed out as a plain callback.
Future<void> _clearHomeWidgetData() => clearWidgetData();

/// Seam for the home-widget wipe sign-out performs, so a test can hold
/// sign-out open — or make it fail — after the session epoch has advanced.
final Provider<Future<void> Function()> clearWidgetDataProvider =
    Provider<Future<void> Function()>((Ref ref) => _clearHomeWidgetData);

/// Owns the login → device-token → signed-in flow and logout revocation.
class AuthController extends Notifier<AuthState> {
  String? _pendingEmail;
  String? _pendingPassword;
  String? _pendingMagicToken;
  SocialAuthorization? _pendingSocial;
  int _socialAttempt = 0;
  late Future<void> _initialRestore;

  @override
  AuthState build() {
    // Best-effort restore of a previous session; stays signed out when
    // nothing is stored.
    _initialRestore = _restore();
    unawaited(_initialRestore);
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

  /// Wait for storage before consuming a cold-start link so restore cannot
  /// overwrite a newly authenticated account or its pending 2FA state.
  Future<void> receiveMagicLink({
    required String email,
    required String token,
  }) async {
    await _initialRestore;
    if (state.isLoading) return;
    await verifyMagicLink(email: email, token: token);
  }

  /// Completes when the stored session (if any) has been read at start-up.
  /// Push actions wait for it so they never run without the bearer.
  Future<void> get restored => _initialRestore;

  /// Explicit restore for tests/app start when deterministic timing matters.
  Future<void> restore() => _restore();

  /// Both first-time signup and existing-account login use the web providers.
  Future<void> signInWithSocial(String provider) async {
    if (state.isLoading) return;
    final attempt = ++_socialAttempt;
    _pendingSocial = null;
    _pendingEmail = null;
    _pendingPassword = null;
    _pendingMagicToken = null;
    state = state.copyWith(
      status: AuthStatus.signedOut,
      email: '',
      isLoading: true,
      errorMessage: null,
      magicLinkSent: false,
    );
    try {
      final api = ref.read(uptrackApiProvider);
      final providers = await api.getAuthProviders();
      if (!providers.contains(provider)) {
        throw const FormatException('Provider unavailable');
      }
      if (attempt != _socialAttempt) return;
      final request = SocialLoginRequest.create();
      final callback = await ref
          .read(socialBrowserProvider)
          .authenticate(
            api.socialLoginUrl(provider, request.state, request.challenge),
          );
      if (attempt != _socialAttempt) return;
      _pendingSocial = request.parseCallback(callback);
      await _exchangeSocial();
    } on SocialLoginCancelled {
      if (attempt == _socialAttempt) state = state.copyWith(isLoading: false);
    } on DioException catch (err) {
      if (attempt == _socialAttempt) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: authErrorMessage(err),
        );
      }
    } catch (_) {
      if (attempt == _socialAttempt) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Social sign-in could not finish. Please try again.',
        );
      }
    }
  }

  Future<void> _exchangeSocial({String? totpCode}) async {
    final attempt = _socialAttempt;
    final pending = _pendingSocial;
    if (pending == null) throw const FormatException('Sign-in expired');
    final result = await ref
        .read(uptrackApiProvider)
        .exchangeSocialCode(
          code: pending.code,
          verifier: pending.verifier,
          totpCode: totpCode,
        );
    if (attempt != _socialAttempt) return;
    if (result.totpRequired) {
      state = state.copyWith(
        status: AuthStatus.needsTwoFactor,
        isLoading: false,
      );
      return;
    }
    await _storeIssuance(result.issuance!);
  }

  /// Password login. On success exchanges the session for a device token;
  /// when the account has 2FA, moves to [AuthStatus.needsTwoFactor] instead.
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    _pendingSocial = null;
    _socialAttempt++;
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
        _pendingMagicToken = null;
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

  /// Second step of either login: resubmits the in-memory credentials plus code.
  Future<void> submitTwoFactorCode(String code) async {
    if (_pendingSocial != null) {
      state = state.copyWith(isLoading: true, errorMessage: null);
      try {
        await _exchangeSocial(totpCode: code.trim());
      } on DioException catch (err) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: authErrorMessage(err),
        );
      } catch (_) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Sign-in could not finish. Please try again.',
        );
      }
      return;
    }
    final String? email = _pendingEmail;
    final String? password = _pendingPassword;
    final String? magicToken = _pendingMagicToken;
    if (email == null || (password == null && magicToken == null)) {
      state = state.copyWith(
        status: AuthStatus.signedOut,
        errorMessage: 'Session expired. Sign in again.',
      );
      return;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final api = ref.read(uptrackApiProvider);
      final LoginResult result = magicToken != null
          ? await api.verifyMagicLink(
              email: email,
              token: magicToken,
              totpCode: code.trim(),
            )
          : await api.login(
              email: email,
              password: password!,
              totpCode: code.trim(),
            );
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

  /// Discards a pending 2FA step and returns to email sign-in.
  void cancelTwoFactor() {
    _pendingEmail = null;
    _pendingPassword = null;
    _pendingMagicToken = null;
    _pendingSocial = null;
    _socialAttempt++;
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
    _pendingSocial = null;
    _socialAttempt++;
    state = state.copyWith(
      status: AuthStatus.signedOut,
      isLoading: true,
      errorMessage: null,
      email: email.trim(),
    );
    try {
      final LoginResult result = await ref
          .read(uptrackApiProvider)
          .verifyMagicLink(email: email.trim(), token: token);
      if (result.totpRequired) {
        _pendingEmail = email.trim();
        _pendingPassword = null;
        _pendingMagicToken = token;
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

  /// Exchanges the login session (replayed cookie) for a device token and
  /// persists it in secure storage.
  Future<void> _finishSignIn() async {
    final DeviceTokenIssuance issuance = await ref
        .read(uptrackApiProvider)
        .createDeviceToken();
    await _storeIssuance(issuance);
  }

  Future<void> _storeIssuance(DeviceTokenIssuance issuance) async {
    await ref
        .read(tokenStoreProvider)
        .writeDeviceToken(token: issuance.token, id: issuance.id);
    ref.read(authTokenHolderProvider).token = issuance.token;
    _pendingEmail = null;
    _pendingPassword = null;
    _pendingMagicToken = null;
    _pendingSocial = null;
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
  ///
  /// The push device is unregistered first: `DELETE /api/push/devices` needs
  /// the device-token bearer, and the server keys push devices by user, so a
  /// revoked device token alone keeps the old account's alerts coming. With
  /// no [pushToken], the token [PushRegistrationStore] recorded is used.
  ///
  /// Live Activity tokens: the server deletes this device's push-to-start
  /// and update tokens on that unregister and on the device-token revoke.
  /// Only when neither can run (no push device registered, no stored
  /// device-token id) is the posted push-to-start token deleted by itself.
  Future<void> signOut({String? pushToken}) async {
    final UptrackApi api = ref.read(uptrackApiProvider);
    final PushRegistrationStore pushStore = ref.read(
      pushRegistrationStoreProvider,
    );
    final String? tokenToUnregister = pushToken != null && pushToken.isNotEmpty
        ? pushToken
        : pushStore.registered?.token;
    final String? pushToStart = pushStore.registeredPushToStart;
    pushStore.clearRegistered();
    bool deviceForgotten = false;
    if (tokenToUnregister != null && tokenToUnregister.isNotEmpty) {
      try {
        await api.unregisterPushDevice(tokenToUnregister);
        deviceForgotten = true;
      } on DioException {
        // Best effort: the local wipe below still signs the user out.
      }
    }
    final String? deviceTokenId = state.deviceTokenId;
    if (!deviceForgotten && deviceTokenId == null && pushToStart != null) {
      try {
        await api.unregisterLiveActivity(
          LiveActivityRemoveRequest(token: pushToStart),
        );
      } on DioException {
        // Best effort (see above).
      }
    }
    if (deviceTokenId != null) {
      try {
        await api.revokeDeviceToken(deviceTokenId);
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
    _pendingMagicToken = null;
    _pendingSocial = null;
    _socialAttempt++;
    // R2.4: no signed-in incident may linger on the home widget, and no
    // cached monitors/incidents may survive for the next account.
    //
    // The wipe is *started* before signed-out is published, never awaited
    // first: clearAll() advances the session epoch synchronously, so the
    // moment anything can observe the new state (the router redirecting to
    // /login, the user starting a fresh sign-in) every response still in
    // flight from the old session is already fenced. Awaiting it before the
    // state change would leave a window in which a new sign-in runs under the
    // previous session's epoch.
    //
    // Error handling is attached immediately, and the future is awaited
    // separately below so a slow — or failing — widget clear cannot skip the
    // cache cleanup.
    final Future<void> cacheWipe = ref
        .read(cacheRepositoryProvider)
        .clearAll()
        .catchError((Object _) {
          // Cache wipe is hygiene, not correctness of sign-out.
        });
    state = const AuthState();
    try {
      await ref.read(clearWidgetDataProvider)();
    } catch (_) {
      // Widget clearing is hygiene, not correctness of sign-out, and must not
      // skip the cache cleanup awaited below.
    }
    await cacheWipe;
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
    // The bearer is dead, so the server row cannot be removed from here; the
    // next sign-in re-registers (the server upsert moves the row's owner).
    ref.read(pushRegistrationStoreProvider).clearRegistered();
    unawaited(ref.read(tokenStoreProvider).clear());
    unawaited(ref.read(clearWidgetDataProvider)());
    unawaited(ref.read(cacheRepositoryProvider).clearAll().catchError((_) {}));
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
    await PushChannels.tokenChannel().invokeMethod('clearSessionNotifications');
  } on MissingPluginException {
    // Host has no such method (Android, tests) — nothing to clear.
  } on PlatformException {
    // Native clear failed — sign-out proceeds regardless.
  }
}
