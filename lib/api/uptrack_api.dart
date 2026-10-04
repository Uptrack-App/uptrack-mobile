import 'package:dio/dio.dart';

import 'client.dart';
import 'models/billing_subscription.dart';
import 'models/check.dart';
import 'models/current_user.dart';
import 'models/device_token.dart';
import 'models/incident.dart';
import 'models/monitor.dart';
import 'models/monitor_analytics.dart';
import 'models/notification_preferences.dart';
import 'models/status_page.dart';
import '../widgets/live_activity.dart';

/// Paths used by the mobile API client (mirrored in the contract test).
const String kGetMePath = '/api/auth/me';
const String kListMonitorsPath = '/api/monitors';
const String kLoginPath = '/api/auth/login';
const String kMagicLinkPath = '/api/auth/magic-link';
const String kMagicLinkVerifyPath = '/api/auth/magic-link/verify';
const String kLogoutPath = '/api/auth/logout';
const String kDeleteAccountPath = '/api/auth/account';
const String kDeviceTokensPath = '/api/auth/device-tokens';
const String kPushDevicesPath = '/api/push/devices';
const String kIncidentsPath = '/api/incidents';
const String kNotificationPreferencesPath =
    '/api/users/me/notification-preferences';
const String kBillingSubscriptionPath = '/api/billing/subscription';

/// OpenAPI path template for the public status page (mirrored in the
/// contract test). The runtime call interpolates the slug via
/// [statusPagePath].
const String kStatusPagePath = '/api/status/{slug}';

/// Concrete path for `GET /api/status/{slug}`.
String statusPagePath(String slug) => '/api/status/$slug';

/// OpenAPI path templates for the monitor detail flows (mirrored in the
/// contract test). Runtime calls interpolate the concrete id via the
/// `monitor*Path` helpers below.
const String kMonitorDetailPath = '/api/monitors/{id}';
const String kMonitorChecksPath = '/api/monitors/{id}/checks';
const String kMonitorAnalyticsPath = '/api/analytics/monitors/{monitor_id}';

/// Concrete path for `GET /api/monitors/{id}`.
String monitorDetailPath(String id) => '/api/monitors/$id';

/// OpenAPI path template for `GET /api/incidents/{id}` (mirrored in the
/// contract test). The runtime call interpolates the id via
/// [incidentDetailPath].
const String kIncidentDetailPath = '/api/incidents/{id}';

/// Concrete path for `GET /api/incidents/{id}`.
String incidentDetailPath(String id) => '/api/incidents/$id';

/// OpenAPI path template for `POST /api/incidents/{id}/acknowledge`
/// (mirrored in the contract test).
const String kIncidentAcknowledgePath = '/api/incidents/{id}/acknowledge';

/// Concrete path for `POST /api/incidents/{id}/acknowledge`.
String incidentAcknowledgePath(String id) => '/api/incidents/$id/acknowledge';

/// OpenAPI path template for `POST /api/incidents/{id}/escalate`
/// (lock-screen triage; device-token Bearer auth only).
const String kIncidentEscalatePath = '/api/incidents/{id}/escalate';

/// Concrete path for `POST /api/incidents/{id}/escalate`.
String incidentEscalatePath(String id) => '/api/incidents/$id/escalate';

/// OpenAPI path template for `POST /api/monitors/{id}/snooze`
/// (lock-screen triage; device-token Bearer auth only).
const String kMonitorSnoozePath = '/api/monitors/{id}/snooze';

/// Concrete path for `POST /api/monitors/{id}/snooze`.
String monitorSnoozePath(String id) => '/api/monitors/$id/snooze';

/// Concrete path for `GET /api/monitors/{id}/checks`.
String monitorChecksPath(String id) => '/api/monitors/$id/checks';

/// Concrete path for `GET /api/analytics/monitors/{monitor_id}`.
String monitorAnalyticsPath(String id) => '/api/analytics/monitors/$id';

/// Chart windows offered by the monitor detail screen (`?days=` values).
const Set<int> analyticsDayOptions = <int>{1, 7, 90};

/// Result of password or magic-link verification: either a 2FA prompt or an
/// authenticated session (session cookie, captured by
/// [SessionCookieInterceptor] on the shared Dio instance).
class LoginResult {
  const LoginResult._({this.me, this.totpRequired = false});

  const LoginResult.totpRequired() : this._(totpRequired: true);

  factory LoginResult.authenticated(CurrentUserResponse me) =>
      LoginResult._(me: me);

  final CurrentUserResponse? me;
  final bool totpRequired;
}

/// Result of `POST /api/incidents/{id}/escalate`: the policy steps fired
/// immediately by this call (`escalated: false` when the call was an
/// idempotent no-op on an already-acknowledged/resolved incident).
class EscalateResult {
  const EscalateResult({required this.escalated, required this.stepsFired});

  factory EscalateResult.fromJson(Map<String, Object?> json) {
    return EscalateResult(
      escalated: json['escalated'] == true,
      stepsFired: (json['steps_fired'] as num?)?.toInt() ?? 0,
    );
  }

  final bool escalated;
  final int stepsFired;
}

/// Result of `POST /api/monitors/{id}/snooze`: `mobile_push` for this
/// user + monitor resumes after [snoozedUntil].
class SnoozeResult {
  const SnoozeResult({required this.snoozedUntil});

  factory SnoozeResult.fromJson(Map<String, Object?> json) {
    return SnoozeResult(snoozedUntil: json['snoozed_until']! as String);
  }

  final String snoozedUntil;
}

/// Raw device-token issuance: the secret is returned exactly once.
class DeviceTokenIssuance {
  const DeviceTokenIssuance({
    required this.id,
    this.label,
    required this.token,
    required this.createdAt,
  });

  factory DeviceTokenIssuance.fromJson(Map<String, Object?> json) {
    return DeviceTokenIssuance(
      id: json['id']! as String,
      label: json['label'] as String?,
      token: json['token']! as String,
      createdAt: json['created_at']! as String,
    );
  }

  final String id;
  final String? label;
  final String token;
  final String createdAt;
}

/// Hand-written API client over [Dio] (see L7: dio + freezed, no codegen client).
class UptrackApi {
  UptrackApi({Dio? dio}) : _dio = dio ?? createApiClient();

  final Dio _dio;

  /// Configured Google/GitHub providers, shared with web signup/sign-in.
  Future<Set<String>> getAuthProviders() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/auth/providers',
    );
    final providers = response.data?['providers'];
    if (providers is! Map) {
      throw const FormatException('Invalid providers response');
    }
    return <String>{
      for (final name in <String>['google', 'github'])
        if (providers[name] == true) name,
    };
  }

  Uri socialLoginUrl(String provider, String state, String challenge) {
    if (!<String>['google', 'github'].contains(provider)) {
      throw ArgumentError.value(provider, 'provider');
    }
    final base = Uri.parse(_dio.options.baseUrl);
    if (base.scheme != 'https' &&
        !(base.scheme == 'http' &&
            <String>[
              'localhost',
              '127.0.0.1',
              '10.0.2.2',
              '::1',
            ].contains(base.host))) {
      throw const FormatException('Social login requires HTTPS');
    }
    return base
        .resolve('/auth/$provider')
        .replace(
          queryParameters: <String, String>{
            'mobile_state': state,
            'code_challenge': challenge,
            'code_challenge_method': 'S256',
          },
        );
  }

  Future<({bool totpRequired, DeviceTokenIssuance? issuance})>
  exchangeSocialCode({
    required String code,
    required String verifier,
    String? totpCode,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/mobile/exchange',
      data: <String, Object?>{
        'code': code,
        'code_verifier': verifier,
        'totp_code': ?totpCode,
      },
    );
    final data = response.data;
    if (data == null) throw const FormatException('Invalid sign-in response');
    if (data['totp_required'] == true) {
      return (totpRequired: true, issuance: null);
    }
    return (
      totpRequired: false,
      issuance: DeviceTokenIssuance.fromJson(data.cast<String, Object?>()),
    );
  }

  /// `GET /api/auth/me` — current user + organization.
  Future<CurrentUserResponse> getMe() async {
    final Response<Map<String, dynamic>> res = await _dio
        .get<Map<String, dynamic>>(kGetMePath);
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: kGetMePath),
        message: 'Empty response from $kGetMePath',
      );
    }
    return CurrentUserResponse.fromJson(data.cast<String, Object?>());
  }

  /// `POST /api/auth/login` — password login; returns a 2FA prompt when the
  /// account has TOTP enabled and no `totp_code` was supplied.
  Future<LoginResult> login({
    required String email,
    required String password,
    String? totpCode,
  }) async {
    final Response<Map<String, dynamic>> res = await _dio
        .post<Map<String, dynamic>>(
          kLoginPath,
          data: <String, Object?>{
            'email': email,
            'password': password,
            if (totpCode != null && totpCode.isNotEmpty) 'totp_code': totpCode,
          },
        );
    final Map<String, Object?> data = (res.data ?? <String, dynamic>{})
        .cast<String, Object?>();
    if (data['totp_required'] == true) {
      return const LoginResult.totpRequired();
    }
    return LoginResult.authenticated(CurrentUserResponse.fromJson(data));
  }

  /// `POST /api/auth/magic-link` — request a passwordless sign-in email.
  Future<void> requestMagicLink({required String email}) async {
    await _dio.post<Map<String, dynamic>>(
      kMagicLinkPath,
      data: <String, Object?>{'email': email, 'client': 'mobile'},
    );
  }

  /// `POST /api/auth/magic-link/verify` — consume `{email, token}` from the
  /// magic-link deep link into an authenticated session.
  Future<LoginResult> verifyMagicLink({
    required String email,
    required String token,
    String? totpCode,
  }) async {
    final Response<Map<String, dynamic>> res = await _dio
        .post<Map<String, dynamic>>(
          kMagicLinkVerifyPath,
          data: <String, Object?>{
            'email': email,
            'token': token,
            if (totpCode != null && totpCode.isNotEmpty) 'totp_code': totpCode,
          },
        );
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: kMagicLinkVerifyPath),
        message: 'Empty response from $kMagicLinkVerifyPath',
      );
    }
    if (data['totp_required'] == true) return const LoginResult.totpRequired();
    return LoginResult.authenticated(
      CurrentUserResponse.fromJson(data.cast<String, Object?>()),
    );
  }

  /// `POST /api/auth/device-tokens` — exchange the login session for a
  /// long-lived device token (raw secret returned once).
  Future<DeviceTokenIssuance> createDeviceToken({String? label}) async {
    final Response<Map<String, dynamic>> res = await _dio
        .post<Map<String, dynamic>>(
          kDeviceTokensPath,
          data: <String, Object?>{
            if (label != null && label.isNotEmpty) 'label': label,
          },
        );
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: kDeviceTokensPath),
        message: 'Empty response from $kDeviceTokensPath',
      );
    }
    return DeviceTokenIssuance.fromJson(data.cast<String, Object?>());
  }

  /// `GET /api/auth/device-tokens` — the caller's live (unrevoked)
  /// device tokens (metadata only; the raw secret is never returned).
  Future<List<DeviceToken>> listDeviceTokens() async {
    final Response<Map<String, dynamic>> res = await _dio
        .get<Map<String, dynamic>>(kDeviceTokensPath);
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: kDeviceTokensPath),
        message: 'Empty response from $kDeviceTokensPath',
      );
    }
    final Object? items = data['data'];
    if (items is! List) {
      throw DioException(
        requestOptions: RequestOptions(path: kDeviceTokensPath),
        message: 'Unexpected shape from $kDeviceTokensPath',
      );
    }
    return items
        .map(
          (Object? e) =>
              DeviceToken.fromJson((e! as Map).cast<String, Object?>()),
        )
        .toList();
  }

  /// `DELETE /api/auth/device-tokens/{id}` — revoke one device token.
  Future<void> revokeDeviceToken(String id) async {
    await _dio.delete<Map<String, dynamic>>('$kDeviceTokensPath/$id');
  }

  /// `POST /api/push/devices` — register (or re-register after a token
  /// refresh) the native push token. Idempotent on `(platform, token)`:
  /// re-registration refreshes `last_seen_at` and clears `invalidated_at`.
  Future<void> registerPushDevice({
    required String platform,
    required String token,
    String? environment,
    String? appVersion,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      kPushDevicesPath,
      data: <String, Object?>{
        'platform': platform,
        'token': token,
        if (environment != null && environment.isNotEmpty)
          'environment': environment,
        if (appVersion != null && appVersion.isNotEmpty)
          'app_version': appVersion,
      },
    );
  }

  /// `DELETE /api/push/devices` — unregister a push token on logout.
  Future<void> unregisterPushDevice(String token) async {
    await _dio.delete<Map<String, dynamic>>(
      kPushDevicesPath,
      data: <String, Object?>{'token': token},
    );
  }

  /// `POST /api/auth/logout` — clear the server session cookie.
  Future<void> logout() async {
    await _dio.post<Map<String, dynamic>>(kLogoutPath);
  }

  /// `POST /api/auth/account` — soft-delete the account + organization
  /// (R2.6). Owner-only, session-auth only; email/password users must pass
  /// their `password`; a live subscription must be cancelled first (the
  /// server answers 409 until then). Returns the goodbye token for the
  /// anonymous post-deletion feedback flow; callers should treat any
  /// 2xx as success and run the full local wipe regardless.
  Future<String?> deleteAccount({String? password}) async {
    final Response<Map<String, dynamic>> res = await _dio
        .post<Map<String, dynamic>>(
          kDeleteAccountPath,
          data: <String, Object?>{
            if (password != null && password.isNotEmpty) 'password': password,
          },
        );
    final Object? token = res.data?['goodbye_token'];
    return token is String && token.isNotEmpty ? token : null;
  }

  /// `GET /api/incidents` — the org's incidents, newest first.
  /// Pass `status: 'ongoing'` for open incidents only.
  Future<IncidentListResponse> listIncidents({String? status}) async {
    final Response<Map<String, dynamic>> res = await _dio
        .get<Map<String, dynamic>>(
          kIncidentsPath,
          queryParameters: <String, Object?>{
            if (status != null && status.isNotEmpty) 'status': status,
          },
        );
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: kIncidentsPath),
        message: 'Empty response from $kIncidentsPath',
      );
    }
    return IncidentListResponse.fromJson(data.cast<String, Object?>());
  }

  /// `GET /api/incidents/{id}` — one incident + its posted updates
  /// (`{ data: { incident, updates } }` envelope).
  Future<IncidentDetail> getIncident(String id) async {
    final String path = incidentDetailPath(id);
    final Response<Map<String, dynamic>> res = await _dio
        .get<Map<String, dynamic>>(path);
    return _parseIncidentDetail(res.data, path);
  }

  /// `POST /api/incidents/{id}/acknowledge` — pause escalation and
  /// auto-post an update; returns the refreshed incident detail.
  Future<IncidentDetail> acknowledgeIncident(String id) async {
    final String path = incidentAcknowledgePath(id);
    final Response<Map<String, dynamic>> res = await _dio
        .post<Map<String, dynamic>>(path);
    return _parseIncidentDetail(res.data, path);
  }

  /// `POST /api/incidents/{id}/escalate` — fire the monitor's escalation
  /// policy immediately (device-token Bearer auth; lock-screen triage).
  Future<EscalateResult> escalateIncident(String id) async {
    final String path = incidentEscalatePath(id);
    final Response<Map<String, dynamic>> res = await _dio
        .post<Map<String, dynamic>>(path);
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        message: 'Empty response from $path',
      );
    }
    return EscalateResult.fromJson(data.cast<String, Object?>());
  }

  /// `POST /api/monitors/{id}/snooze` — suppress `mobile_push` for this
  /// user + monitor for one hour (device-token Bearer auth).
  Future<SnoozeResult> snoozeMonitor(String id) async {
    final String path = monitorSnoozePath(id);
    final Response<Map<String, dynamic>> res = await _dio
        .post<Map<String, dynamic>>(path);
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        message: 'Empty response from $path',
      );
    }
    return SnoozeResult.fromJson(data.cast<String, Object?>());
  }

  /// `GET /api/monitors` — list the authenticated org's monitors.
  Future<MonitorListResponse> listMonitors({
    int page = 1,
    int perPage = 20,
    String? search,
  }) async {
    final Map<String, Object?> query = <String, Object?>{
      'page': page,
      'per_page': perPage,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final Response<Map<String, dynamic>> res = await _dio
        .get<Map<String, dynamic>>(kListMonitorsPath, queryParameters: query);
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: kListMonitorsPath),
        message: 'Empty response from $kListMonitorsPath',
      );
    }
    return MonitorListResponse.fromJson(data.cast<String, Object?>());
  }

  /// `GET /api/monitors/{id}` — a single monitor (`{ data }` envelope).
  Future<Monitor> getMonitor(String id) async {
    final String path = monitorDetailPath(id);
    final Response<Map<String, dynamic>> res = await _dio
        .get<Map<String, dynamic>>(path);
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        message: 'Empty response from $path',
      );
    }
    final Object? inner = data['data'];
    if (inner is! Map) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        message: 'Unexpected shape from $path',
      );
    }
    return Monitor.fromJson(inner.cast<String, Object?>());
  }

  /// `GET /api/monitors/{id}/checks?limit=N` — recent checks, newest first.
  Future<CheckListResponse> listChecks(String id, {int limit = 20}) async {
    final String path = monitorChecksPath(id);
    final Response<Map<String, dynamic>> res = await _dio
        .get<Map<String, dynamic>>(
          path,
          queryParameters: <String, Object?>{'limit': limit},
        );
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        message: 'Empty response from $path',
      );
    }
    return CheckListResponse.fromJson(data.cast<String, Object?>());
  }

  /// `GET /api/analytics/monitors/{monitor_id}?days=N` — response-time
  /// series + percentiles for the 24h/7d/90d chart windows.
  ///
  /// Throws [ArgumentError] for windows outside [analyticsDayOptions]; the
  /// server additionally clamps `days` to the plan's retention and echoes
  /// the effective window as `period_days`.
  Future<MonitorAnalytics> getMonitorAnalytics(
    String id, {
    int days = 7,
  }) async {
    if (!analyticsDayOptions.contains(days)) {
      throw ArgumentError.value(
        days,
        'days',
        'Must be one of $analyticsDayOptions',
      );
    }
    final String path = monitorAnalyticsPath(id);
    final Response<Map<String, dynamic>> res = await _dio
        .get<Map<String, dynamic>>(
          path,
          queryParameters: <String, Object?>{'days': days},
        );
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        message: 'Empty response from $path',
      );
    }
    return MonitorAnalytics.fromJson(data.cast<String, Object?>());
  }

  /// `GET /api/users/me/notification-preferences` — the caller's prefs
  /// (server returns defaults when nothing was ever saved).
  Future<NotificationPreferences> getNotificationPreferences() async {
    const String path = kNotificationPreferencesPath;
    final Response<Map<String, dynamic>> res = await _dio
        .get<Map<String, dynamic>>(path);
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        message: 'Empty response from $path',
      );
    }
    return NotificationPreferences.fromJson(data.cast<String, Object?>());
  }

  /// `PATCH /api/users/me/notification-preferences` — merge [patch]
  /// (see [NotificationPreferences.toPatchJson]) over the stored prefs.
  Future<NotificationPreferences> updateNotificationPreferences(
    Map<String, Object?> patch,
  ) async {
    const String path = kNotificationPreferencesPath;
    final Response<Map<String, dynamic>> res = await _dio
        .patch<Map<String, dynamic>>(path, data: patch);
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        message: 'Empty response from $path',
      );
    }
    return NotificationPreferences.fromJson(data.cast<String, Object?>());
  }

  /// `GET /api/billing/subscription` — read-only plan + subscription state.
  Future<BillingSubscriptionInfo> getBillingSubscription() async {
    const String path = kBillingSubscriptionPath;
    final Response<Map<String, dynamic>> res = await _dio
        .get<Map<String, dynamic>>(path);
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        message: 'Empty response from $path',
      );
    }
    return BillingSubscriptionInfo.fromJson(data.cast<String, Object?>());
  }

  /// `POST /api/push/live-activities` — register the activity push token
  /// when a Live Activity starts (device-token Bearer auth; idempotent
  /// upsert; 404 on unknown incidents, 422 on already-resolved ones).
  Future<void> registerLiveActivity(LiveActivityRegisterRequest request) async {
    await _dio.post<Map<String, dynamic>>(
      kLiveActivitiesPath,
      data: request.toJson(),
    );
  }

  /// `DELETE /api/push/live-activities` — remove the activity token when it
  /// ends on-device (owner-scoped; unknown tokens → 404).
  Future<void> unregisterLiveActivity(LiveActivityRemoveRequest request) async {
    await _dio.delete<Map<String, dynamic>>(
      kLiveActivitiesPath,
      data: request.toJson(),
    );
  }

  /// `GET /api/status/{slug}` — public status page (no auth required).
  ///
  /// The OpenAPI spec declares no password parameter for this endpoint, so
  /// the optional password is sent as `?password=` (the web UI convention);
  /// see `BACKEND-GAP: status password` in the loop LOG.
  Future<StatusPageData> getStatusPage(String slug, {String? password}) async {
    final String path = statusPagePath(slug);
    final Response<Map<String, dynamic>> res = await _dio
        .get<Map<String, dynamic>>(
          path,
          queryParameters: <String, Object?>{
            if (password != null && password.isNotEmpty) 'password': password,
          },
        );
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        message: 'Empty response from $path',
      );
    }
    final Object? inner = data['data'];
    if (inner is! Map) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        message: 'Unexpected shape from $path',
      );
    }
    return StatusPageData.fromJson(inner.cast<String, Object?>());
  }

  /// Unwraps the `{ data: { incident, updates } }` envelope shared by the
  /// incident detail and acknowledge endpoints.
  IncidentDetail _parseIncidentDetail(Map<String, dynamic>? data, String path) {
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        message: 'Empty response from $path',
      );
    }
    final Object? inner = data['data'];
    if (inner is! Map) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        message: 'Unexpected shape from $path',
      );
    }
    return IncidentDetail.fromJson(inner.cast<String, Object?>());
  }
}
