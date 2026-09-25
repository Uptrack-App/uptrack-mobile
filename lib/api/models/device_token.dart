/// Device-token metadata from `GET /api/auth/device-tokens`.
///
/// The raw secret is never exposed by the API — only id/label/timestamps
/// (see `DeviceTokenOut` in the server's `auth_api.rs`).
class DeviceToken {
  const DeviceToken({
    required this.id,
    this.label,
    required this.createdAt,
    this.lastUsedAt,
  });

  factory DeviceToken.fromJson(Map<String, Object?> json) {
    return DeviceToken(
      id: json['id']! as String,
      label: json['label'] as String?,
      createdAt: json['created_at']! as String,
      lastUsedAt: json['last_used_at'] as String?,
    );
  }

  final String id;
  final String? label;
  final String createdAt;
  final String? lastUsedAt;

  /// Human-readable name shown on the device-management screen.
  String get displayName {
    final String? trimmed = label?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return 'Unlabeled device';
  }
}
