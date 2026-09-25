/// Check rows from `GET /api/monitors/{id}/checks` (subset of `CheckOut`).
class MonitorCheck {
  const MonitorCheck({
    required this.status,
    required this.responseTime,
    required this.statusCode,
    required this.checkedAt,
    this.errorMessage,
  });

  factory MonitorCheck.fromJson(Map<String, Object?> json) {
    return MonitorCheck(
      status: json['status']! as String,
      responseTime: (json['response_time']! as num).toInt(),
      statusCode: (json['status_code']! as num).toInt(),
      checkedAt: json['checked_at']! as String,
      errorMessage: json['error_message'] as String?,
    );
  }

  final String status;
  final int responseTime;
  final int statusCode;
  final String checkedAt;
  final String? errorMessage;

  bool get isUp => status == 'up';
}

/// `GET /api/monitors/{id}/checks` envelope (`{ data }`, newest first).
class CheckListResponse {
  const CheckListResponse({required this.data});

  factory CheckListResponse.fromJson(Map<String, Object?> json) {
    final Object? items = json['data'];
    if (items is! List) {
      throw FormatException('Unexpected shape for CheckListResponse');
    }
    return CheckListResponse(
      data: items
          .map(
            (Object? e) =>
                MonitorCheck.fromJson((e! as Map).cast<String, Object?>()),
          )
          .toList(),
    );
  }

  final List<MonitorCheck> data;
}
