// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'current_user.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CurrentUserResponse {

 AuthUser get user; AuthOrganization get organization;
/// Create a copy of CurrentUserResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CurrentUserResponseCopyWith<CurrentUserResponse> get copyWith => _$CurrentUserResponseCopyWithImpl<CurrentUserResponse>(this as CurrentUserResponse, _$identity);

  /// Serializes this CurrentUserResponse to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as CurrentUserResponse;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CurrentUserResponse&&(identical(other.user, _this.user) || other.user == _this.user)&&(identical(other.organization, _this.organization) || other.organization == _this.organization));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as CurrentUserResponse;
  return Object.hash(runtimeType,_this.user,_this.organization);
}

@override
String toString() {
  final _this = this as CurrentUserResponse;
  return 'CurrentUserResponse(user: ${_this.user}, organization: ${_this.organization})';
}


}

/// @nodoc
abstract mixin class $CurrentUserResponseCopyWith<$Res>  {
  factory $CurrentUserResponseCopyWith(CurrentUserResponse value, $Res Function(CurrentUserResponse) _then) = _$CurrentUserResponseCopyWithImpl;
@useResult
$Res call({
 AuthUser user, AuthOrganization organization
});


$AuthUserCopyWith<$Res> get user;$AuthOrganizationCopyWith<$Res> get organization;

}
/// @nodoc
class _$CurrentUserResponseCopyWithImpl<$Res>
    implements $CurrentUserResponseCopyWith<$Res> {
  _$CurrentUserResponseCopyWithImpl(this._self, this._then);

  final CurrentUserResponse _self;
  final $Res Function(CurrentUserResponse) _then;

/// Create a copy of CurrentUserResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? user = null,Object? organization = null,}) {
  return _then(CurrentUserResponse(
user: null == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as AuthUser,organization: null == organization ? _self.organization : organization // ignore: cast_nullable_to_non_nullable
as AuthOrganization,
  ));
}
/// Create a copy of CurrentUserResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AuthUserCopyWith<$Res> get user {
  
  return $AuthUserCopyWith<$Res>(_self.user, (value) {
    return _then(_self.copyWith(user: value));
  });
}/// Create a copy of CurrentUserResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AuthOrganizationCopyWith<$Res> get organization {
  
  return $AuthOrganizationCopyWith<$Res>(_self.organization, (value) {
    return _then(_self.copyWith(organization: value));
  });
}
}


/// Adds pattern-matching-related methods to [CurrentUserResponse].
extension CurrentUserResponsePatterns on CurrentUserResponse {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CurrentUserResponse value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CurrentUserResponse() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CurrentUserResponse value)  $default,){
final _that = this;
switch (_that) {
case _CurrentUserResponse():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CurrentUserResponse value)?  $default,){
final _that = this;
switch (_that) {
case _CurrentUserResponse() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AuthUser user,  AuthOrganization organization)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CurrentUserResponse() when $default != null:
return $default(_that.user,_that.organization);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AuthUser user,  AuthOrganization organization)  $default,) {final _that = this;
switch (_that) {
case _CurrentUserResponse():
return $default(_that.user,_that.organization);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AuthUser user,  AuthOrganization organization)?  $default,) {final _that = this;
switch (_that) {
case _CurrentUserResponse() when $default != null:
return $default(_that.user,_that.organization);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CurrentUserResponse implements CurrentUserResponse {
  const _CurrentUserResponse({required this.user, required this.organization});
  factory _CurrentUserResponse.fromJson(Map<String, dynamic> json) => _$CurrentUserResponseFromJson(json);

@override final  AuthUser user;
@override final  AuthOrganization organization;

/// Create a copy of CurrentUserResponse
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CurrentUserResponseCopyWith<_CurrentUserResponse> get copyWith => __$CurrentUserResponseCopyWithImpl<_CurrentUserResponse>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CurrentUserResponseToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CurrentUserResponse&&(identical(other.user, user) || other.user == user)&&(identical(other.organization, organization) || other.organization == organization));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,user,organization);
}

@override
String toString() {
    return 'CurrentUserResponse(user: $user, organization: $organization)';
}


}

/// @nodoc
abstract mixin class _$CurrentUserResponseCopyWith<$Res> implements $CurrentUserResponseCopyWith<$Res> {
  factory _$CurrentUserResponseCopyWith(_CurrentUserResponse value, $Res Function(_CurrentUserResponse) _then) = __$CurrentUserResponseCopyWithImpl;
@override @useResult
$Res call({
 AuthUser user, AuthOrganization organization
});


@override $AuthUserCopyWith<$Res> get user;@override $AuthOrganizationCopyWith<$Res> get organization;

}
/// @nodoc
class __$CurrentUserResponseCopyWithImpl<$Res>
    implements _$CurrentUserResponseCopyWith<$Res> {
  __$CurrentUserResponseCopyWithImpl(this._self, this._then);

  final _CurrentUserResponse _self;
  final $Res Function(_CurrentUserResponse) _then;

/// Create a copy of CurrentUserResponse
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? user = null,Object? organization = null,}) {
  return _then(_CurrentUserResponse(
user: null == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as AuthUser,organization: null == organization ? _self.organization : organization // ignore: cast_nullable_to_non_nullable
as AuthOrganization,
  ));
}

/// Create a copy of CurrentUserResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AuthUserCopyWith<$Res> get user {
  
  return $AuthUserCopyWith<$Res>(_self.user, (value) {
    return _then(_self.copyWith(user: value));
  });
}/// Create a copy of CurrentUserResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AuthOrganizationCopyWith<$Res> get organization {
  
  return $AuthOrganizationCopyWith<$Res>(_self.organization, (value) {
    return _then(_self.copyWith(organization: value));
  });
}
}


/// @nodoc
mixin _$AuthUser {

 String get id; String get name; String get email; String? get provider; String get role;@JsonKey(name: 'is_admin') bool get isAdmin;@JsonKey(name: 'preferred_locale') String? get preferredLocale;@JsonKey(name: 'inserted_at') String get insertedAt;
/// Create a copy of AuthUser
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AuthUserCopyWith<AuthUser> get copyWith => _$AuthUserCopyWithImpl<AuthUser>(this as AuthUser, _$identity);

  /// Serializes this AuthUser to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as AuthUser;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthUser&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.email, _this.email) || other.email == _this.email)&&(identical(other.provider, _this.provider) || other.provider == _this.provider)&&(identical(other.role, _this.role) || other.role == _this.role)&&(identical(other.isAdmin, _this.isAdmin) || other.isAdmin == _this.isAdmin)&&(identical(other.preferredLocale, _this.preferredLocale) || other.preferredLocale == _this.preferredLocale)&&(identical(other.insertedAt, _this.insertedAt) || other.insertedAt == _this.insertedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as AuthUser;
  return Object.hash(runtimeType,_this.id,_this.name,_this.email,_this.provider,_this.role,_this.isAdmin,_this.preferredLocale,_this.insertedAt);
}

@override
String toString() {
  final _this = this as AuthUser;
  return 'AuthUser(id: ${_this.id}, name: ${_this.name}, email: ${_this.email}, provider: ${_this.provider}, role: ${_this.role}, isAdmin: ${_this.isAdmin}, preferredLocale: ${_this.preferredLocale}, insertedAt: ${_this.insertedAt})';
}


}

/// @nodoc
abstract mixin class $AuthUserCopyWith<$Res>  {
  factory $AuthUserCopyWith(AuthUser value, $Res Function(AuthUser) _then) = _$AuthUserCopyWithImpl;
@useResult
$Res call({
 String id, String name, String email, String? provider, String role,@JsonKey(name: 'is_admin') bool isAdmin,@JsonKey(name: 'preferred_locale') String? preferredLocale,@JsonKey(name: 'inserted_at') String insertedAt
});




}
/// @nodoc
class _$AuthUserCopyWithImpl<$Res>
    implements $AuthUserCopyWith<$Res> {
  _$AuthUserCopyWithImpl(this._self, this._then);

  final AuthUser _self;
  final $Res Function(AuthUser) _then;

/// Create a copy of AuthUser
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? email = null,Object? provider = freezed,Object? role = null,Object? isAdmin = null,Object? preferredLocale = freezed,Object? insertedAt = null,}) {
  return _then(AuthUser(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,provider: freezed == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as String?,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,isAdmin: null == isAdmin ? _self.isAdmin : isAdmin // ignore: cast_nullable_to_non_nullable
as bool,preferredLocale: freezed == preferredLocale ? _self.preferredLocale : preferredLocale // ignore: cast_nullable_to_non_nullable
as String?,insertedAt: null == insertedAt ? _self.insertedAt : insertedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AuthUser].
extension AuthUserPatterns on AuthUser {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AuthUser value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AuthUser() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AuthUser value)  $default,){
final _that = this;
switch (_that) {
case _AuthUser():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AuthUser value)?  $default,){
final _that = this;
switch (_that) {
case _AuthUser() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String email,  String? provider,  String role, @JsonKey(name: 'is_admin')  bool isAdmin, @JsonKey(name: 'preferred_locale')  String? preferredLocale, @JsonKey(name: 'inserted_at')  String insertedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AuthUser() when $default != null:
return $default(_that.id,_that.name,_that.email,_that.provider,_that.role,_that.isAdmin,_that.preferredLocale,_that.insertedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String email,  String? provider,  String role, @JsonKey(name: 'is_admin')  bool isAdmin, @JsonKey(name: 'preferred_locale')  String? preferredLocale, @JsonKey(name: 'inserted_at')  String insertedAt)  $default,) {final _that = this;
switch (_that) {
case _AuthUser():
return $default(_that.id,_that.name,_that.email,_that.provider,_that.role,_that.isAdmin,_that.preferredLocale,_that.insertedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String email,  String? provider,  String role, @JsonKey(name: 'is_admin')  bool isAdmin, @JsonKey(name: 'preferred_locale')  String? preferredLocale, @JsonKey(name: 'inserted_at')  String insertedAt)?  $default,) {final _that = this;
switch (_that) {
case _AuthUser() when $default != null:
return $default(_that.id,_that.name,_that.email,_that.provider,_that.role,_that.isAdmin,_that.preferredLocale,_that.insertedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AuthUser implements AuthUser {
  const _AuthUser({required this.id, required this.name, required this.email, this.provider, required this.role, @JsonKey(name: 'is_admin') required this.isAdmin, @JsonKey(name: 'preferred_locale') this.preferredLocale, @JsonKey(name: 'inserted_at') required this.insertedAt});
  factory _AuthUser.fromJson(Map<String, dynamic> json) => _$AuthUserFromJson(json);

@override final  String id;
@override final  String name;
@override final  String email;
@override final  String? provider;
@override final  String role;
@override@JsonKey(name: 'is_admin') final  bool isAdmin;
@override@JsonKey(name: 'preferred_locale') final  String? preferredLocale;
@override@JsonKey(name: 'inserted_at') final  String insertedAt;

/// Create a copy of AuthUser
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AuthUserCopyWith<_AuthUser> get copyWith => __$AuthUserCopyWithImpl<_AuthUser>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AuthUserToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AuthUser&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.email, email) || other.email == email)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.role, role) || other.role == role)&&(identical(other.isAdmin, isAdmin) || other.isAdmin == isAdmin)&&(identical(other.preferredLocale, preferredLocale) || other.preferredLocale == preferredLocale)&&(identical(other.insertedAt, insertedAt) || other.insertedAt == insertedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name,email,provider,role,isAdmin,preferredLocale,insertedAt);
}

@override
String toString() {
    return 'AuthUser(id: $id, name: $name, email: $email, provider: $provider, role: $role, isAdmin: $isAdmin, preferredLocale: $preferredLocale, insertedAt: $insertedAt)';
}


}

/// @nodoc
abstract mixin class _$AuthUserCopyWith<$Res> implements $AuthUserCopyWith<$Res> {
  factory _$AuthUserCopyWith(_AuthUser value, $Res Function(_AuthUser) _then) = __$AuthUserCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String email, String? provider, String role,@JsonKey(name: 'is_admin') bool isAdmin,@JsonKey(name: 'preferred_locale') String? preferredLocale,@JsonKey(name: 'inserted_at') String insertedAt
});




}
/// @nodoc
class __$AuthUserCopyWithImpl<$Res>
    implements _$AuthUserCopyWith<$Res> {
  __$AuthUserCopyWithImpl(this._self, this._then);

  final _AuthUser _self;
  final $Res Function(_AuthUser) _then;

/// Create a copy of AuthUser
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? email = null,Object? provider = freezed,Object? role = null,Object? isAdmin = null,Object? preferredLocale = freezed,Object? insertedAt = null,}) {
  return _then(_AuthUser(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,provider: freezed == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as String?,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,isAdmin: null == isAdmin ? _self.isAdmin : isAdmin // ignore: cast_nullable_to_non_nullable
as bool,preferredLocale: freezed == preferredLocale ? _self.preferredLocale : preferredLocale // ignore: cast_nullable_to_non_nullable
as String?,insertedAt: null == insertedAt ? _self.insertedAt : insertedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$AuthOrganization {

 String get id; String get name; String get slug; String get plan;@JsonKey(name: 'features_enabled') bool? get featuresEnabled;
/// Create a copy of AuthOrganization
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AuthOrganizationCopyWith<AuthOrganization> get copyWith => _$AuthOrganizationCopyWithImpl<AuthOrganization>(this as AuthOrganization, _$identity);

  /// Serializes this AuthOrganization to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as AuthOrganization;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthOrganization&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.slug, _this.slug) || other.slug == _this.slug)&&(identical(other.plan, _this.plan) || other.plan == _this.plan)&&(identical(other.featuresEnabled, _this.featuresEnabled) || other.featuresEnabled == _this.featuresEnabled));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as AuthOrganization;
  return Object.hash(runtimeType,_this.id,_this.name,_this.slug,_this.plan,_this.featuresEnabled);
}

@override
String toString() {
  final _this = this as AuthOrganization;
  return 'AuthOrganization(id: ${_this.id}, name: ${_this.name}, slug: ${_this.slug}, plan: ${_this.plan}, featuresEnabled: ${_this.featuresEnabled})';
}


}

/// @nodoc
abstract mixin class $AuthOrganizationCopyWith<$Res>  {
  factory $AuthOrganizationCopyWith(AuthOrganization value, $Res Function(AuthOrganization) _then) = _$AuthOrganizationCopyWithImpl;
@useResult
$Res call({
 String id, String name, String slug, String plan,@JsonKey(name: 'features_enabled') bool? featuresEnabled
});




}
/// @nodoc
class _$AuthOrganizationCopyWithImpl<$Res>
    implements $AuthOrganizationCopyWith<$Res> {
  _$AuthOrganizationCopyWithImpl(this._self, this._then);

  final AuthOrganization _self;
  final $Res Function(AuthOrganization) _then;

/// Create a copy of AuthOrganization
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? slug = null,Object? plan = null,Object? featuresEnabled = freezed,}) {
  return _then(AuthOrganization(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,slug: null == slug ? _self.slug : slug // ignore: cast_nullable_to_non_nullable
as String,plan: null == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as String,featuresEnabled: freezed == featuresEnabled ? _self.featuresEnabled : featuresEnabled // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [AuthOrganization].
extension AuthOrganizationPatterns on AuthOrganization {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AuthOrganization value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AuthOrganization() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AuthOrganization value)  $default,){
final _that = this;
switch (_that) {
case _AuthOrganization():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AuthOrganization value)?  $default,){
final _that = this;
switch (_that) {
case _AuthOrganization() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String slug,  String plan, @JsonKey(name: 'features_enabled')  bool? featuresEnabled)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AuthOrganization() when $default != null:
return $default(_that.id,_that.name,_that.slug,_that.plan,_that.featuresEnabled);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String slug,  String plan, @JsonKey(name: 'features_enabled')  bool? featuresEnabled)  $default,) {final _that = this;
switch (_that) {
case _AuthOrganization():
return $default(_that.id,_that.name,_that.slug,_that.plan,_that.featuresEnabled);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String slug,  String plan, @JsonKey(name: 'features_enabled')  bool? featuresEnabled)?  $default,) {final _that = this;
switch (_that) {
case _AuthOrganization() when $default != null:
return $default(_that.id,_that.name,_that.slug,_that.plan,_that.featuresEnabled);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AuthOrganization implements AuthOrganization {
  const _AuthOrganization({required this.id, required this.name, required this.slug, required this.plan, @JsonKey(name: 'features_enabled') this.featuresEnabled});
  factory _AuthOrganization.fromJson(Map<String, dynamic> json) => _$AuthOrganizationFromJson(json);

@override final  String id;
@override final  String name;
@override final  String slug;
@override final  String plan;
@override@JsonKey(name: 'features_enabled') final  bool? featuresEnabled;

/// Create a copy of AuthOrganization
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AuthOrganizationCopyWith<_AuthOrganization> get copyWith => __$AuthOrganizationCopyWithImpl<_AuthOrganization>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AuthOrganizationToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AuthOrganization&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.slug, slug) || other.slug == slug)&&(identical(other.plan, plan) || other.plan == plan)&&(identical(other.featuresEnabled, featuresEnabled) || other.featuresEnabled == featuresEnabled));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name,slug,plan,featuresEnabled);
}

@override
String toString() {
    return 'AuthOrganization(id: $id, name: $name, slug: $slug, plan: $plan, featuresEnabled: $featuresEnabled)';
}


}

/// @nodoc
abstract mixin class _$AuthOrganizationCopyWith<$Res> implements $AuthOrganizationCopyWith<$Res> {
  factory _$AuthOrganizationCopyWith(_AuthOrganization value, $Res Function(_AuthOrganization) _then) = __$AuthOrganizationCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String slug, String plan,@JsonKey(name: 'features_enabled') bool? featuresEnabled
});




}
/// @nodoc
class __$AuthOrganizationCopyWithImpl<$Res>
    implements _$AuthOrganizationCopyWith<$Res> {
  __$AuthOrganizationCopyWithImpl(this._self, this._then);

  final _AuthOrganization _self;
  final $Res Function(_AuthOrganization) _then;

/// Create a copy of AuthOrganization
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? slug = null,Object? plan = null,Object? featuresEnabled = freezed,}) {
  return _then(_AuthOrganization(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,slug: null == slug ? _self.slug : slug // ignore: cast_nullable_to_non_nullable
as String,plan: null == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as String,featuresEnabled: freezed == featuresEnabled ? _self.featuresEnabled : featuresEnabled // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

// dart format on
