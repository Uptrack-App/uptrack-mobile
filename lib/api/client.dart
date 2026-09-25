import 'package:dio/dio.dart';

/// Base URL for the Uptrack API.
///
/// Overridable at build/run time with
/// `--dart-define=API_BASE_URL=https://api.example.com`.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:4000',
);

/// Builds a configured [Dio] client for the Uptrack API.
///
/// [tokenProvider] is a stub hook returning the bearer device token when
/// signed in (secure-storage wiring lands with the auth flows). When it
/// returns a non-empty token, the `Authorization: Bearer <token>` header is
/// attached to every request.
Dio createApiClient({
  String baseUrl = apiBaseUrl,
  String? Function()? tokenProvider,
  Dio? dio,
}) {
  final Dio client = dio ?? Dio();
  client.options.baseUrl = baseUrl;
  client.options.connectTimeout = const Duration(seconds: 10);
  client.options.receiveTimeout = const Duration(seconds: 15);
  client.options.headers[Headers.acceptHeader] = Headers.jsonContentType;
  if (tokenProvider != null) {
    client.interceptors.add(_BearerTokenInterceptor(tokenProvider));
  }
  return client;
}

/// Request interceptor attaching the bearer device token, when available.
class _BearerTokenInterceptor extends Interceptor {
  _BearerTokenInterceptor(this._tokenProvider);

  final String? Function() _tokenProvider;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final String? token = _tokenProvider();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
