import 'package:freezed_annotation/freezed_annotation.dart';

part 'monitor.freezed.dart';
part 'monitor.g.dart';

/// `GET /api/monitors` paginated envelope (`{ data, meta }`).
@freezed
abstract class MonitorListResponse with _$MonitorListResponse {
  const factory MonitorListResponse({
    required List<Monitor> data,
    required PageMeta meta,
  }) = _MonitorListResponse;

  factory MonitorListResponse.fromJson(Map<String, Object?> json) =>
      _$MonitorListResponseFromJson(json);
}

/// Pagination metadata for list endpoints.
@freezed
abstract class PageMeta with _$PageMeta {
  const factory PageMeta({
    required int total,
    required int page,
    @JsonKey(name: 'per_page') required int perPage,
  }) = _PageMeta;

  factory PageMeta.fromJson(Map<String, Object?> json) =>
      _$PageMetaFromJson(json);
}

/// A monitor row (subset of `MonitorOut` needed by the mobile v1 read flows).
@freezed
abstract class Monitor with _$Monitor {
  const factory Monitor({
    required String id,
    required String name,
    required String url,
    @JsonKey(name: 'monitor_type') required String monitorType,
    required String status,
    required int interval,
    required int timeout,
    @Default(<String, Object?>{}) Map<String, Object?> settings,
    @JsonKey(name: 'confirmation_window') required String confirmationWindow,
    @JsonKey(name: 'regions_required') required String regionsRequired,
    @JsonKey(name: 'alert_contacts')
    @Default(<String>[])
    List<String> alertContacts,
    @JsonKey(name: 'created_at') required String createdAt,
    @JsonKey(name: 'updated_at') required String updatedAt,
    String? description,
    @JsonKey(name: 'escalation_policy_id') String? escalationPolicyId,
    @JsonKey(name: 'confirmation_threshold') int? confirmationThreshold,
    @JsonKey(name: 'reminder_interval_minutes') int? reminderIntervalMinutes,
    @JsonKey(name: 'uptime_percentage') double? uptimePercentage,
    @JsonKey(name: 'heartbeat_ping_url') String? heartbeatPingUrl,
    @JsonKey(name: 'last_check') LastCheck? lastCheck,
  }) = _Monitor;

  factory Monitor.fromJson(Map<String, Object?> json) =>
      _$MonitorFromJson(json);
}

/// Latest check enrichment on a monitor row.
@freezed
abstract class LastCheck with _$LastCheck {
  const factory LastCheck({
    required String status,
    @JsonKey(name: 'response_time') required int responseTime,
    @JsonKey(name: 'checked_at') required String checkedAt,
  }) = _LastCheck;

  factory LastCheck.fromJson(Map<String, Object?> json) =>
      _$LastCheckFromJson(json);
}
