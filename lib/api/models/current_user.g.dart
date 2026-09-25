// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'current_user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CurrentUserResponse _$CurrentUserResponseFromJson(Map<String, dynamic> json) =>
    _CurrentUserResponse(
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      organization: AuthOrganization.fromJson(
        json['organization'] as Map<String, dynamic>,
      ),
    );

Map<String, dynamic> _$CurrentUserResponseToJson(
  _CurrentUserResponse instance,
) => <String, dynamic>{
  'user': instance.user,
  'organization': instance.organization,
};

_AuthUser _$AuthUserFromJson(Map<String, dynamic> json) => _AuthUser(
  id: json['id'] as String,
  name: json['name'] as String,
  email: json['email'] as String,
  provider: json['provider'] as String?,
  role: json['role'] as String,
  isAdmin: json['is_admin'] as bool,
  preferredLocale: json['preferred_locale'] as String?,
  insertedAt: json['inserted_at'] as String,
);

Map<String, dynamic> _$AuthUserToJson(_AuthUser instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'email': instance.email,
  'provider': instance.provider,
  'role': instance.role,
  'is_admin': instance.isAdmin,
  'preferred_locale': instance.preferredLocale,
  'inserted_at': instance.insertedAt,
};

_AuthOrganization _$AuthOrganizationFromJson(Map<String, dynamic> json) =>
    _AuthOrganization(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      plan: json['plan'] as String,
      featuresEnabled: json['features_enabled'] as bool?,
    );

Map<String, dynamic> _$AuthOrganizationToJson(_AuthOrganization instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'slug': instance.slug,
      'plan': instance.plan,
      'features_enabled': instance.featuresEnabled,
    };
