import 'package:freezed_annotation/freezed_annotation.dart';

part 'current_user.freezed.dart';
part 'current_user.g.dart';

/// `GET /api/auth/me` response: current user + organization.
@freezed
abstract class CurrentUserResponse with _$CurrentUserResponse {
  const factory CurrentUserResponse({
    required AuthUser user,
    required AuthOrganization organization,
  }) = _CurrentUserResponse;

  factory CurrentUserResponse.fromJson(Map<String, Object?> json) =>
      _$CurrentUserResponseFromJson(json);
}

/// The current user as returned by login/register/me.
@freezed
abstract class AuthUser with _$AuthUser {
  const factory AuthUser({
    required String id,
    required String name,
    required String email,
    String? provider,
    required String role,
    @JsonKey(name: 'is_admin') required bool isAdmin,
    @JsonKey(name: 'preferred_locale') String? preferredLocale,
    @JsonKey(name: 'inserted_at') required String insertedAt,
  }) = _AuthUser;

  factory AuthUser.fromJson(Map<String, Object?> json) =>
      _$AuthUserFromJson(json);
}

/// The org as returned by login/register/me.
@freezed
abstract class AuthOrganization with _$AuthOrganization {
  const factory AuthOrganization({
    required String id,
    required String name,
    required String slug,
    required String plan,
    @JsonKey(name: 'features_enabled') bool? featuresEnabled,
  }) = _AuthOrganization;

  factory AuthOrganization.fromJson(Map<String, Object?> json) =>
      _$AuthOrganizationFromJson(json);
}
