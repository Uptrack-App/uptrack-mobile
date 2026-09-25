/// Notification-preference models for
/// `GET/PATCH /api/users/me/notification-preferences` (backend T016).
///
/// `severity_overrides` values are opaque to the API (the APNs/FCM senders
/// interpret them); the app only writes the documented interruption levels
/// (see [kInterruptionLevels]) or removes the key for the server default.
class NotificationPreferences {
  const NotificationPreferences({
    this.severityOverrides = const <String, String>{},
    this.quietHoursStart,
    this.quietHoursEnd,
    this.mobilePushEnabled = true,
    this.digestP3 = true,
  });

  factory NotificationPreferences.fromJson(Map<String, Object?> json) {
    final Map<String, String> overrides = <String, String>{};
    final Object? rawOverrides = json['severity_overrides'];
    if (rawOverrides is Map) {
      for (final MapEntry<Object?, Object?> entry in rawOverrides.entries) {
        final Object? key = entry.key;
        final Object? value = entry.value;
        if (key is String &&
            kSeverities.contains(key) &&
            value is String &&
            value.isNotEmpty) {
          overrides[key] = value;
        }
      }
    }
    return NotificationPreferences(
      severityOverrides: overrides,
      quietHoursStart: json['quiet_hours_start'] as String?,
      quietHoursEnd: json['quiet_hours_end'] as String?,
      mobilePushEnabled: json['mobile_push_enabled'] as bool? ?? true,
      digestP3: json['digest_p3'] as bool? ?? true,
    );
  }

  final Map<String, String> severityOverrides;

  /// `HH:MM(:SS)` strings (or null when no quiet window is set).
  final String? quietHoursStart;
  final String? quietHoursEnd;
  final bool mobilePushEnabled;
  final bool digestP3;

  /// Full-merge PATCH body: absent keys mean "no change" server-side, so
  /// the settings UI always sends the complete edited state.
  Map<String, Object?> toPatchJson() {
    return <String, Object?>{
      'severity_overrides': severityOverrides,
      'quiet_hours_start': quietHoursStart,
      'quiet_hours_end': quietHoursEnd,
      'mobile_push_enabled': mobilePushEnabled,
      'digest_p3': digestP3,
    };
  }
}

/// Severities accepted as `severity_overrides` keys (validated server-side).
const List<String> kSeverities = <String>['p1', 'p2', 'p3', 'info'];

/// Server defaults shown when no override is stored (APNs sender mapping).
const Map<String, String> kDefaultInterruption = <String, String>{
  'p1': 'time-sensitive',
  'p2': 'time-sensitive',
  'p3': 'active',
  'info': 'passive',
};

/// Interruption levels the senders interpret (`critical` intentionally
/// omitted — the Critical Alerts entitlement is a v1.1 item).
const List<String> kInterruptionLevels = <String>[
  'passive',
  'active',
  'time-sensitive',
];

/// `HH:MM` 24-hour validation for the quiet-hours fields (the server also
/// accepts `HH:MM:SS` and rejects anything else with a 422).
bool isValidQuietTime(String value) {
  final RegExp pattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
  return pattern.hasMatch(value.trim());
}
