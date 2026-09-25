import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the device token (`udt_…`, returned once at issuance) and its
/// server-side id. Production uses the platform keychain/keystore via
/// [SecureTokenStore]; tests substitute [MemoryTokenStore].
abstract class TokenStore {
  Future<String?> readDeviceToken();
  Future<String?> readDeviceTokenId();
  Future<void> writeDeviceToken({required String token, required String id});
  Future<void> clear();
}

/// Keychain/keystore-backed [TokenStore].
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String tokenKey = 'uptrack_device_token';
  static const String tokenIdKey = 'uptrack_device_token_id';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readDeviceToken() => _storage.read(key: tokenKey);

  @override
  Future<String?> readDeviceTokenId() => _storage.read(key: tokenIdKey);

  @override
  Future<void> writeDeviceToken({
    required String token,
    required String id,
  }) async {
    await _storage.write(key: tokenKey, value: token);
    await _storage.write(key: tokenIdKey, value: id);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: tokenKey);
    await _storage.delete(key: tokenIdKey);
  }
}

/// In-memory [TokenStore] for widget/unit tests (no platform channels).
class MemoryTokenStore implements TokenStore {
  String? _token;
  String? _id;

  @override
  Future<String?> readDeviceToken() async => _token;

  @override
  Future<String?> readDeviceTokenId() async => _id;

  @override
  Future<void> writeDeviceToken({
    required String token,
    required String id,
  }) async {
    _token = token;
    _id = id;
  }

  @override
  Future<void> clear() async {
    _token = null;
    _id = null;
  }
}
