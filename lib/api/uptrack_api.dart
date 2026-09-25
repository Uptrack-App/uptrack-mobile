import 'package:dio/dio.dart';

import 'client.dart';
import 'models/current_user.dart';
import 'models/monitor.dart';

/// Paths used by the mobile API client (mirrored in the contract test).
const String kGetMePath = '/api/auth/me';
const String kListMonitorsPath = '/api/monitors';
const String kLoginPath = '/api/auth/login';
const String kMagicLinkPath = '/api/auth/magic-link';
const String kMagicLinkVerifyPath = '/api/auth/magic-link/verify';
const String kLogoutPath = '/api/auth/logout';
const String kDeviceTokensPath = '/api/auth/device-tokens';
const String kPushDevicesPath = '/api/push/devices';

/// Result of `POST /api/auth/login`: either a 2FA prompt or an
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
      data: <String, Object?>{'email': email},
    );
  }

  /// `POST /api/auth/magic-link/verify` — consume `{email, token}` from the
  /// magic-link deep link into an authenticated session.
  Future<CurrentUserResponse> verifyMagicLink({
    required String email,
    required String token,
  }) async {
    final Response<Map<String, dynamic>> res = await _dio
        .post<Map<String, dynamic>>(
          kMagicLinkVerifyPath,
          data: <String, Object?>{'email': email, 'token': token},
        );
    final Map<String, dynamic>? data = res.data;
    if (data == null) {
      throw DioException(
        requestOptions: RequestOptions(path: kMagicLinkVerifyPath),
        message: 'Empty response from $kMagicLinkVerifyPath',
      );
    }
    return CurrentUserResponse.fromJson(data.cast<String, Object?>());
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

  /// `DELETE /api/auth/device-tokens/{id}` — revoke one device token.
  Future<void> revokeDeviceToken(String id) async {
    await _dio.delete<Map<String, dynamic>>('$kDeviceTokensPath/$id');
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
}
