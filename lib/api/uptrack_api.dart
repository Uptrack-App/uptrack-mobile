import 'package:dio/dio.dart';

import 'client.dart';
import 'models/current_user.dart';
import 'models/monitor.dart';

/// Paths used by the mobile API client (mirrored in the contract test).
const String kGetMePath = '/api/auth/me';
const String kListMonitorsPath = '/api/monitors';

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
