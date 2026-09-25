// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'monitor.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MonitorListResponse _$MonitorListResponseFromJson(Map<String, dynamic> json) =>
    _MonitorListResponse(
      data: (json['data'] as List<dynamic>)
          .map((e) => Monitor.fromJson(e as Map<String, dynamic>))
          .toList(),
      meta: PageMeta.fromJson(json['meta'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$MonitorListResponseToJson(
  _MonitorListResponse instance,
) => <String, dynamic>{'data': instance.data, 'meta': instance.meta};

_PageMeta _$PageMetaFromJson(Map<String, dynamic> json) => _PageMeta(
  total: (json['total'] as num).toInt(),
  page: (json['page'] as num).toInt(),
  perPage: (json['per_page'] as num).toInt(),
);

Map<String, dynamic> _$PageMetaToJson(_PageMeta instance) => <String, dynamic>{
  'total': instance.total,
  'page': instance.page,
  'per_page': instance.perPage,
};

_Monitor _$MonitorFromJson(Map<String, dynamic> json) => _Monitor(
  id: json['id'] as String,
  name: json['name'] as String,
  url: json['url'] as String,
  monitorType: json['monitor_type'] as String,
  status: json['status'] as String,
  interval: (json['interval'] as num).toInt(),
  timeout: (json['timeout'] as num).toInt(),
  settings:
      json['settings'] as Map<String, dynamic>? ?? const <String, Object?>{},
  confirmationWindow: json['confirmation_window'] as String,
  regionsRequired: json['regions_required'] as String,
  alertContacts:
      (json['alert_contacts'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  createdAt: json['created_at'] as String,
  updatedAt: json['updated_at'] as String,
  description: json['description'] as String?,
  escalationPolicyId: json['escalation_policy_id'] as String?,
  confirmationThreshold: (json['confirmation_threshold'] as num?)?.toInt(),
  reminderIntervalMinutes: (json['reminder_interval_minutes'] as num?)?.toInt(),
  uptimePercentage: (json['uptime_percentage'] as num?)?.toDouble(),
  heartbeatPingUrl: json['heartbeat_ping_url'] as String?,
  lastCheck: json['last_check'] == null
      ? null
      : LastCheck.fromJson(json['last_check'] as Map<String, dynamic>),
);

Map<String, dynamic> _$MonitorToJson(_Monitor instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'url': instance.url,
  'monitor_type': instance.monitorType,
  'status': instance.status,
  'interval': instance.interval,
  'timeout': instance.timeout,
  'settings': instance.settings,
  'confirmation_window': instance.confirmationWindow,
  'regions_required': instance.regionsRequired,
  'alert_contacts': instance.alertContacts,
  'created_at': instance.createdAt,
  'updated_at': instance.updatedAt,
  'description': instance.description,
  'escalation_policy_id': instance.escalationPolicyId,
  'confirmation_threshold': instance.confirmationThreshold,
  'reminder_interval_minutes': instance.reminderIntervalMinutes,
  'uptime_percentage': instance.uptimePercentage,
  'heartbeat_ping_url': instance.heartbeatPingUrl,
  'last_check': instance.lastCheck,
};

_LastCheck _$LastCheckFromJson(Map<String, dynamic> json) => _LastCheck(
  status: json['status'] as String,
  responseTime: (json['response_time'] as num).toInt(),
  checkedAt: json['checked_at'] as String,
);

Map<String, dynamic> _$LastCheckToJson(_LastCheck instance) =>
    <String, dynamic>{
      'status': instance.status,
      'response_time': instance.responseTime,
      'checked_at': instance.checkedAt,
    };
