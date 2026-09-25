import 'package:dio/dio.dart';

/// Captures the `_uptrack_key` session cookie from auth responses (login,
/// magic-link verify) and replays it on subsequent requests.
///
/// The mobile app logs in with email+password to obtain a session, then
/// exchanges it for a long-lived device token
/// (`POST /api/auth/device-tokens`, session-cookie auth only). A single
/// shared [Dio] instance carrying this interceptor makes that exchange work
/// without any extra cookie dependency.
class SessionCookieInterceptor extends Interceptor {
  static const String sessionCookieName = '_uptrack_key';

  String? _cookieHeader;

  /// The captured `Cookie` header value, if any (visible for testing).
  String? get cookieHeader => _cookieHeader;

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final List<String>? setCookies = response.headers.map['set-cookie'];
    if (setCookies != null) {
      for (final String entry in setCookies) {
        final String pair = entry.split(';').first.trim();
        if (pair.startsWith('$sessionCookieName=')) {
          _cookieHeader = pair;
        }
      }
    }
    handler.next(response);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final String? cookie = _cookieHeader;
    if (cookie != null && !options.headers.containsKey('Cookie')) {
      options.headers['Cookie'] = cookie;
    }
    handler.next(options);
  }
}

/// Fires [onUnauthorized] when the API answers 401.
///
/// The auth controller uses this to drop back to the login screen
/// ("re-auth on 401"); it no-ops unless currently signed in so failed
/// login attempts still surface their field-level error instead.
class UnauthorizedInterceptor extends Interceptor {
  UnauthorizedInterceptor({required this.onUnauthorized});

  final void Function() onUnauthorized;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      onUnauthorized();
    }
    handler.next(err);
  }
}
