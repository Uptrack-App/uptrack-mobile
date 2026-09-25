// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'monitor.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MonitorListResponse {

 List<Monitor> get data; PageMeta get meta;
/// Create a copy of MonitorListResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MonitorListResponseCopyWith<MonitorListResponse> get copyWith => _$MonitorListResponseCopyWithImpl<MonitorListResponse>(this as MonitorListResponse, _$identity);

  /// Serializes this MonitorListResponse to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as MonitorListResponse;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MonitorListResponse&&const DeepCollectionEquality().equals(other.data, _this.data)&&(identical(other.meta, _this.meta) || other.meta == _this.meta));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as MonitorListResponse;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.data),_this.meta);
}

@override
String toString() {
  final _this = this as MonitorListResponse;
  return 'MonitorListResponse(data: ${_this.data}, meta: ${_this.meta})';
}


}

/// @nodoc
abstract mixin class $MonitorListResponseCopyWith<$Res>  {
  factory $MonitorListResponseCopyWith(MonitorListResponse value, $Res Function(MonitorListResponse) _then) = _$MonitorListResponseCopyWithImpl;
@useResult
$Res call({
 List<Monitor> data, PageMeta meta
});


$PageMetaCopyWith<$Res> get meta;

}
/// @nodoc
class _$MonitorListResponseCopyWithImpl<$Res>
    implements $MonitorListResponseCopyWith<$Res> {
  _$MonitorListResponseCopyWithImpl(this._self, this._then);

  final MonitorListResponse _self;
  final $Res Function(MonitorListResponse) _then;

/// Create a copy of MonitorListResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? data = null,Object? meta = null,}) {
  return _then(MonitorListResponse(
data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as List<Monitor>,meta: null == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as PageMeta,
  ));
}
/// Create a copy of MonitorListResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PageMetaCopyWith<$Res> get meta {
  
  return $PageMetaCopyWith<$Res>(_self.meta, (value) {
    return _then(_self.copyWith(meta: value));
  });
}
}


/// Adds pattern-matching-related methods to [MonitorListResponse].
extension MonitorListResponsePatterns on MonitorListResponse {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MonitorListResponse value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MonitorListResponse() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MonitorListResponse value)  $default,){
final _that = this;
switch (_that) {
case _MonitorListResponse():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MonitorListResponse value)?  $default,){
final _that = this;
switch (_that) {
case _MonitorListResponse() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Monitor> data,  PageMeta meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MonitorListResponse() when $default != null:
return $default(_that.data,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Monitor> data,  PageMeta meta)  $default,) {final _that = this;
switch (_that) {
case _MonitorListResponse():
return $default(_that.data,_that.meta);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Monitor> data,  PageMeta meta)?  $default,) {final _that = this;
switch (_that) {
case _MonitorListResponse() when $default != null:
return $default(_that.data,_that.meta);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MonitorListResponse implements MonitorListResponse {
  const _MonitorListResponse({required  List<Monitor> data, required this.meta}): _data = data;
  factory _MonitorListResponse.fromJson(Map<String, dynamic> json) => _$MonitorListResponseFromJson(json);

 final  List<Monitor> _data;
@override List<Monitor> get data {
  if (_data is EqualUnmodifiableListView) return _data;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_data);
}

@override final  PageMeta meta;

/// Create a copy of MonitorListResponse
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MonitorListResponseCopyWith<_MonitorListResponse> get copyWith => __$MonitorListResponseCopyWithImpl<_MonitorListResponse>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MonitorListResponseToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _MonitorListResponse&&const DeepCollectionEquality().equals(other.data, _data)&&(identical(other.meta, meta) || other.meta == meta));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_data),meta);
}

@override
String toString() {
    return 'MonitorListResponse(data: $data, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$MonitorListResponseCopyWith<$Res> implements $MonitorListResponseCopyWith<$Res> {
  factory _$MonitorListResponseCopyWith(_MonitorListResponse value, $Res Function(_MonitorListResponse) _then) = __$MonitorListResponseCopyWithImpl;
@override @useResult
$Res call({
 List<Monitor> data, PageMeta meta
});


@override $PageMetaCopyWith<$Res> get meta;

}
/// @nodoc
class __$MonitorListResponseCopyWithImpl<$Res>
    implements _$MonitorListResponseCopyWith<$Res> {
  __$MonitorListResponseCopyWithImpl(this._self, this._then);

  final _MonitorListResponse _self;
  final $Res Function(_MonitorListResponse) _then;

/// Create a copy of MonitorListResponse
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? data = null,Object? meta = null,}) {
  return _then(_MonitorListResponse(
data: null == data ? _self._data : data // ignore: cast_nullable_to_non_nullable
as List<Monitor>,meta: null == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as PageMeta,
  ));
}

/// Create a copy of MonitorListResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PageMetaCopyWith<$Res> get meta {
  
  return $PageMetaCopyWith<$Res>(_self.meta, (value) {
    return _then(_self.copyWith(meta: value));
  });
}
}


/// @nodoc
mixin _$PageMeta {

 int get total; int get page;@JsonKey(name: 'per_page') int get perPage;
/// Create a copy of PageMeta
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PageMetaCopyWith<PageMeta> get copyWith => _$PageMetaCopyWithImpl<PageMeta>(this as PageMeta, _$identity);

  /// Serializes this PageMeta to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PageMeta;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PageMeta&&(identical(other.total, _this.total) || other.total == _this.total)&&(identical(other.page, _this.page) || other.page == _this.page)&&(identical(other.perPage, _this.perPage) || other.perPage == _this.perPage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PageMeta;
  return Object.hash(runtimeType,_this.total,_this.page,_this.perPage);
}

@override
String toString() {
  final _this = this as PageMeta;
  return 'PageMeta(total: ${_this.total}, page: ${_this.page}, perPage: ${_this.perPage})';
}


}

/// @nodoc
abstract mixin class $PageMetaCopyWith<$Res>  {
  factory $PageMetaCopyWith(PageMeta value, $Res Function(PageMeta) _then) = _$PageMetaCopyWithImpl;
@useResult
$Res call({
 int total, int page,@JsonKey(name: 'per_page') int perPage
});




}
/// @nodoc
class _$PageMetaCopyWithImpl<$Res>
    implements $PageMetaCopyWith<$Res> {
  _$PageMetaCopyWithImpl(this._self, this._then);

  final PageMeta _self;
  final $Res Function(PageMeta) _then;

/// Create a copy of PageMeta
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? total = null,Object? page = null,Object? perPage = null,}) {
  return _then(PageMeta(
total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,page: null == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as int,perPage: null == perPage ? _self.perPage : perPage // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PageMeta].
extension PageMetaPatterns on PageMeta {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PageMeta value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PageMeta() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PageMeta value)  $default,){
final _that = this;
switch (_that) {
case _PageMeta():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PageMeta value)?  $default,){
final _that = this;
switch (_that) {
case _PageMeta() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int total,  int page, @JsonKey(name: 'per_page')  int perPage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PageMeta() when $default != null:
return $default(_that.total,_that.page,_that.perPage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int total,  int page, @JsonKey(name: 'per_page')  int perPage)  $default,) {final _that = this;
switch (_that) {
case _PageMeta():
return $default(_that.total,_that.page,_that.perPage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int total,  int page, @JsonKey(name: 'per_page')  int perPage)?  $default,) {final _that = this;
switch (_that) {
case _PageMeta() when $default != null:
return $default(_that.total,_that.page,_that.perPage);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PageMeta implements PageMeta {
  const _PageMeta({required this.total, required this.page, @JsonKey(name: 'per_page') required this.perPage});
  factory _PageMeta.fromJson(Map<String, dynamic> json) => _$PageMetaFromJson(json);

@override final  int total;
@override final  int page;
@override@JsonKey(name: 'per_page') final  int perPage;

/// Create a copy of PageMeta
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PageMetaCopyWith<_PageMeta> get copyWith => __$PageMetaCopyWithImpl<_PageMeta>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PageMetaToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PageMeta&&(identical(other.total, total) || other.total == total)&&(identical(other.page, page) || other.page == page)&&(identical(other.perPage, perPage) || other.perPage == perPage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,total,page,perPage);
}

@override
String toString() {
    return 'PageMeta(total: $total, page: $page, perPage: $perPage)';
}


}

/// @nodoc
abstract mixin class _$PageMetaCopyWith<$Res> implements $PageMetaCopyWith<$Res> {
  factory _$PageMetaCopyWith(_PageMeta value, $Res Function(_PageMeta) _then) = __$PageMetaCopyWithImpl;
@override @useResult
$Res call({
 int total, int page,@JsonKey(name: 'per_page') int perPage
});




}
/// @nodoc
class __$PageMetaCopyWithImpl<$Res>
    implements _$PageMetaCopyWith<$Res> {
  __$PageMetaCopyWithImpl(this._self, this._then);

  final _PageMeta _self;
  final $Res Function(_PageMeta) _then;

/// Create a copy of PageMeta
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? total = null,Object? page = null,Object? perPage = null,}) {
  return _then(_PageMeta(
total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,page: null == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as int,perPage: null == perPage ? _self.perPage : perPage // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$Monitor {

 String get id; String get name; String get url;@JsonKey(name: 'monitor_type') String get monitorType; String get status; int get interval; int get timeout; Map<String, Object?> get settings;@JsonKey(name: 'confirmation_window') String get confirmationWindow;@JsonKey(name: 'regions_required') String get regionsRequired;@JsonKey(name: 'alert_contacts') List<String> get alertContacts;@JsonKey(name: 'created_at') String get createdAt;@JsonKey(name: 'updated_at') String get updatedAt; String? get description;@JsonKey(name: 'escalation_policy_id') String? get escalationPolicyId;@JsonKey(name: 'confirmation_threshold') int? get confirmationThreshold;@JsonKey(name: 'reminder_interval_minutes') int? get reminderIntervalMinutes;@JsonKey(name: 'uptime_percentage') double? get uptimePercentage;@JsonKey(name: 'heartbeat_ping_url') String? get heartbeatPingUrl;@JsonKey(name: 'last_check') LastCheck? get lastCheck;
/// Create a copy of Monitor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MonitorCopyWith<Monitor> get copyWith => _$MonitorCopyWithImpl<Monitor>(this as Monitor, _$identity);

  /// Serializes this Monitor to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Monitor;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Monitor&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.monitorType, _this.monitorType) || other.monitorType == _this.monitorType)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.interval, _this.interval) || other.interval == _this.interval)&&(identical(other.timeout, _this.timeout) || other.timeout == _this.timeout)&&const DeepCollectionEquality().equals(other.settings, _this.settings)&&(identical(other.confirmationWindow, _this.confirmationWindow) || other.confirmationWindow == _this.confirmationWindow)&&(identical(other.regionsRequired, _this.regionsRequired) || other.regionsRequired == _this.regionsRequired)&&const DeepCollectionEquality().equals(other.alertContacts, _this.alertContacts)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.escalationPolicyId, _this.escalationPolicyId) || other.escalationPolicyId == _this.escalationPolicyId)&&(identical(other.confirmationThreshold, _this.confirmationThreshold) || other.confirmationThreshold == _this.confirmationThreshold)&&(identical(other.reminderIntervalMinutes, _this.reminderIntervalMinutes) || other.reminderIntervalMinutes == _this.reminderIntervalMinutes)&&(identical(other.uptimePercentage, _this.uptimePercentage) || other.uptimePercentage == _this.uptimePercentage)&&(identical(other.heartbeatPingUrl, _this.heartbeatPingUrl) || other.heartbeatPingUrl == _this.heartbeatPingUrl)&&(identical(other.lastCheck, _this.lastCheck) || other.lastCheck == _this.lastCheck));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Monitor;
  return Object.hashAll([runtimeType,_this.id,_this.name,_this.url,_this.monitorType,_this.status,_this.interval,_this.timeout,const DeepCollectionEquality().hash(_this.settings),_this.confirmationWindow,_this.regionsRequired,const DeepCollectionEquality().hash(_this.alertContacts),_this.createdAt,_this.updatedAt,_this.description,_this.escalationPolicyId,_this.confirmationThreshold,_this.reminderIntervalMinutes,_this.uptimePercentage,_this.heartbeatPingUrl,_this.lastCheck]);
}

@override
String toString() {
  final _this = this as Monitor;
  return 'Monitor(id: ${_this.id}, name: ${_this.name}, url: ${_this.url}, monitorType: ${_this.monitorType}, status: ${_this.status}, interval: ${_this.interval}, timeout: ${_this.timeout}, settings: ${_this.settings}, confirmationWindow: ${_this.confirmationWindow}, regionsRequired: ${_this.regionsRequired}, alertContacts: ${_this.alertContacts}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt}, description: ${_this.description}, escalationPolicyId: ${_this.escalationPolicyId}, confirmationThreshold: ${_this.confirmationThreshold}, reminderIntervalMinutes: ${_this.reminderIntervalMinutes}, uptimePercentage: ${_this.uptimePercentage}, heartbeatPingUrl: ${_this.heartbeatPingUrl}, lastCheck: ${_this.lastCheck})';
}


}

/// @nodoc
abstract mixin class $MonitorCopyWith<$Res>  {
  factory $MonitorCopyWith(Monitor value, $Res Function(Monitor) _then) = _$MonitorCopyWithImpl;
@useResult
$Res call({
 String id, String name, String url,@JsonKey(name: 'monitor_type') String monitorType, String status, int interval, int timeout, Map<String, Object?> settings,@JsonKey(name: 'confirmation_window') String confirmationWindow,@JsonKey(name: 'regions_required') String regionsRequired,@JsonKey(name: 'alert_contacts') List<String> alertContacts,@JsonKey(name: 'created_at') String createdAt,@JsonKey(name: 'updated_at') String updatedAt, String? description,@JsonKey(name: 'escalation_policy_id') String? escalationPolicyId,@JsonKey(name: 'confirmation_threshold') int? confirmationThreshold,@JsonKey(name: 'reminder_interval_minutes') int? reminderIntervalMinutes,@JsonKey(name: 'uptime_percentage') double? uptimePercentage,@JsonKey(name: 'heartbeat_ping_url') String? heartbeatPingUrl,@JsonKey(name: 'last_check') LastCheck? lastCheck
});


$LastCheckCopyWith<$Res>? get lastCheck;

}
/// @nodoc
class _$MonitorCopyWithImpl<$Res>
    implements $MonitorCopyWith<$Res> {
  _$MonitorCopyWithImpl(this._self, this._then);

  final Monitor _self;
  final $Res Function(Monitor) _then;

/// Create a copy of Monitor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? url = null,Object? monitorType = null,Object? status = null,Object? interval = null,Object? timeout = null,Object? settings = null,Object? confirmationWindow = null,Object? regionsRequired = null,Object? alertContacts = null,Object? createdAt = null,Object? updatedAt = null,Object? description = freezed,Object? escalationPolicyId = freezed,Object? confirmationThreshold = freezed,Object? reminderIntervalMinutes = freezed,Object? uptimePercentage = freezed,Object? heartbeatPingUrl = freezed,Object? lastCheck = freezed,}) {
  return _then(Monitor(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,monitorType: null == monitorType ? _self.monitorType : monitorType // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,interval: null == interval ? _self.interval : interval // ignore: cast_nullable_to_non_nullable
as int,timeout: null == timeout ? _self.timeout : timeout // ignore: cast_nullable_to_non_nullable
as int,settings: null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>,confirmationWindow: null == confirmationWindow ? _self.confirmationWindow : confirmationWindow // ignore: cast_nullable_to_non_nullable
as String,regionsRequired: null == regionsRequired ? _self.regionsRequired : regionsRequired // ignore: cast_nullable_to_non_nullable
as String,alertContacts: null == alertContacts ? _self.alertContacts : alertContacts // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,escalationPolicyId: freezed == escalationPolicyId ? _self.escalationPolicyId : escalationPolicyId // ignore: cast_nullable_to_non_nullable
as String?,confirmationThreshold: freezed == confirmationThreshold ? _self.confirmationThreshold : confirmationThreshold // ignore: cast_nullable_to_non_nullable
as int?,reminderIntervalMinutes: freezed == reminderIntervalMinutes ? _self.reminderIntervalMinutes : reminderIntervalMinutes // ignore: cast_nullable_to_non_nullable
as int?,uptimePercentage: freezed == uptimePercentage ? _self.uptimePercentage : uptimePercentage // ignore: cast_nullable_to_non_nullable
as double?,heartbeatPingUrl: freezed == heartbeatPingUrl ? _self.heartbeatPingUrl : heartbeatPingUrl // ignore: cast_nullable_to_non_nullable
as String?,lastCheck: freezed == lastCheck ? _self.lastCheck : lastCheck // ignore: cast_nullable_to_non_nullable
as LastCheck?,
  ));
}
/// Create a copy of Monitor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LastCheckCopyWith<$Res>? get lastCheck {
    if (_self.lastCheck == null) {
    return null;
  }

  return $LastCheckCopyWith<$Res>(_self.lastCheck!, (value) {
    return _then(_self.copyWith(lastCheck: value));
  });
}
}


/// Adds pattern-matching-related methods to [Monitor].
extension MonitorPatterns on Monitor {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Monitor value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Monitor() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Monitor value)  $default,){
final _that = this;
switch (_that) {
case _Monitor():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Monitor value)?  $default,){
final _that = this;
switch (_that) {
case _Monitor() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String url, @JsonKey(name: 'monitor_type')  String monitorType,  String status,  int interval,  int timeout,  Map<String, Object?> settings, @JsonKey(name: 'confirmation_window')  String confirmationWindow, @JsonKey(name: 'regions_required')  String regionsRequired, @JsonKey(name: 'alert_contacts')  List<String> alertContacts, @JsonKey(name: 'created_at')  String createdAt, @JsonKey(name: 'updated_at')  String updatedAt,  String? description, @JsonKey(name: 'escalation_policy_id')  String? escalationPolicyId, @JsonKey(name: 'confirmation_threshold')  int? confirmationThreshold, @JsonKey(name: 'reminder_interval_minutes')  int? reminderIntervalMinutes, @JsonKey(name: 'uptime_percentage')  double? uptimePercentage, @JsonKey(name: 'heartbeat_ping_url')  String? heartbeatPingUrl, @JsonKey(name: 'last_check')  LastCheck? lastCheck)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Monitor() when $default != null:
return $default(_that.id,_that.name,_that.url,_that.monitorType,_that.status,_that.interval,_that.timeout,_that.settings,_that.confirmationWindow,_that.regionsRequired,_that.alertContacts,_that.createdAt,_that.updatedAt,_that.description,_that.escalationPolicyId,_that.confirmationThreshold,_that.reminderIntervalMinutes,_that.uptimePercentage,_that.heartbeatPingUrl,_that.lastCheck);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String url, @JsonKey(name: 'monitor_type')  String monitorType,  String status,  int interval,  int timeout,  Map<String, Object?> settings, @JsonKey(name: 'confirmation_window')  String confirmationWindow, @JsonKey(name: 'regions_required')  String regionsRequired, @JsonKey(name: 'alert_contacts')  List<String> alertContacts, @JsonKey(name: 'created_at')  String createdAt, @JsonKey(name: 'updated_at')  String updatedAt,  String? description, @JsonKey(name: 'escalation_policy_id')  String? escalationPolicyId, @JsonKey(name: 'confirmation_threshold')  int? confirmationThreshold, @JsonKey(name: 'reminder_interval_minutes')  int? reminderIntervalMinutes, @JsonKey(name: 'uptime_percentage')  double? uptimePercentage, @JsonKey(name: 'heartbeat_ping_url')  String? heartbeatPingUrl, @JsonKey(name: 'last_check')  LastCheck? lastCheck)  $default,) {final _that = this;
switch (_that) {
case _Monitor():
return $default(_that.id,_that.name,_that.url,_that.monitorType,_that.status,_that.interval,_that.timeout,_that.settings,_that.confirmationWindow,_that.regionsRequired,_that.alertContacts,_that.createdAt,_that.updatedAt,_that.description,_that.escalationPolicyId,_that.confirmationThreshold,_that.reminderIntervalMinutes,_that.uptimePercentage,_that.heartbeatPingUrl,_that.lastCheck);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String url, @JsonKey(name: 'monitor_type')  String monitorType,  String status,  int interval,  int timeout,  Map<String, Object?> settings, @JsonKey(name: 'confirmation_window')  String confirmationWindow, @JsonKey(name: 'regions_required')  String regionsRequired, @JsonKey(name: 'alert_contacts')  List<String> alertContacts, @JsonKey(name: 'created_at')  String createdAt, @JsonKey(name: 'updated_at')  String updatedAt,  String? description, @JsonKey(name: 'escalation_policy_id')  String? escalationPolicyId, @JsonKey(name: 'confirmation_threshold')  int? confirmationThreshold, @JsonKey(name: 'reminder_interval_minutes')  int? reminderIntervalMinutes, @JsonKey(name: 'uptime_percentage')  double? uptimePercentage, @JsonKey(name: 'heartbeat_ping_url')  String? heartbeatPingUrl, @JsonKey(name: 'last_check')  LastCheck? lastCheck)?  $default,) {final _that = this;
switch (_that) {
case _Monitor() when $default != null:
return $default(_that.id,_that.name,_that.url,_that.monitorType,_that.status,_that.interval,_that.timeout,_that.settings,_that.confirmationWindow,_that.regionsRequired,_that.alertContacts,_that.createdAt,_that.updatedAt,_that.description,_that.escalationPolicyId,_that.confirmationThreshold,_that.reminderIntervalMinutes,_that.uptimePercentage,_that.heartbeatPingUrl,_that.lastCheck);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Monitor implements Monitor {
  const _Monitor({required this.id, required this.name, required this.url, @JsonKey(name: 'monitor_type') required this.monitorType, required this.status, required this.interval, required this.timeout,  Map<String, Object?> settings = const <String, Object?>{}, @JsonKey(name: 'confirmation_window') required this.confirmationWindow, @JsonKey(name: 'regions_required') required this.regionsRequired, @JsonKey(name: 'alert_contacts')  List<String> alertContacts = const <String>[], @JsonKey(name: 'created_at') required this.createdAt, @JsonKey(name: 'updated_at') required this.updatedAt, this.description, @JsonKey(name: 'escalation_policy_id') this.escalationPolicyId, @JsonKey(name: 'confirmation_threshold') this.confirmationThreshold, @JsonKey(name: 'reminder_interval_minutes') this.reminderIntervalMinutes, @JsonKey(name: 'uptime_percentage') this.uptimePercentage, @JsonKey(name: 'heartbeat_ping_url') this.heartbeatPingUrl, @JsonKey(name: 'last_check') this.lastCheck}): _settings = settings,_alertContacts = alertContacts;
  factory _Monitor.fromJson(Map<String, dynamic> json) => _$MonitorFromJson(json);

@override final  String id;
@override final  String name;
@override final  String url;
@override@JsonKey(name: 'monitor_type') final  String monitorType;
@override final  String status;
@override final  int interval;
@override final  int timeout;
 final  Map<String, Object?> _settings;
@override@JsonKey() Map<String, Object?> get settings {
  if (_settings is EqualUnmodifiableMapView) return _settings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_settings);
}

@override@JsonKey(name: 'confirmation_window') final  String confirmationWindow;
@override@JsonKey(name: 'regions_required') final  String regionsRequired;
 final  List<String> _alertContacts;
@override@JsonKey(name: 'alert_contacts') List<String> get alertContacts {
  if (_alertContacts is EqualUnmodifiableListView) return _alertContacts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_alertContacts);
}

@override@JsonKey(name: 'created_at') final  String createdAt;
@override@JsonKey(name: 'updated_at') final  String updatedAt;
@override final  String? description;
@override@JsonKey(name: 'escalation_policy_id') final  String? escalationPolicyId;
@override@JsonKey(name: 'confirmation_threshold') final  int? confirmationThreshold;
@override@JsonKey(name: 'reminder_interval_minutes') final  int? reminderIntervalMinutes;
@override@JsonKey(name: 'uptime_percentage') final  double? uptimePercentage;
@override@JsonKey(name: 'heartbeat_ping_url') final  String? heartbeatPingUrl;
@override@JsonKey(name: 'last_check') final  LastCheck? lastCheck;

/// Create a copy of Monitor
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MonitorCopyWith<_Monitor> get copyWith => __$MonitorCopyWithImpl<_Monitor>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MonitorToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Monitor&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.url, url) || other.url == url)&&(identical(other.monitorType, monitorType) || other.monitorType == monitorType)&&(identical(other.status, status) || other.status == status)&&(identical(other.interval, interval) || other.interval == interval)&&(identical(other.timeout, timeout) || other.timeout == timeout)&&const DeepCollectionEquality().equals(other.settings, _settings)&&(identical(other.confirmationWindow, confirmationWindow) || other.confirmationWindow == confirmationWindow)&&(identical(other.regionsRequired, regionsRequired) || other.regionsRequired == regionsRequired)&&const DeepCollectionEquality().equals(other.alertContacts, _alertContacts)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.description, description) || other.description == description)&&(identical(other.escalationPolicyId, escalationPolicyId) || other.escalationPolicyId == escalationPolicyId)&&(identical(other.confirmationThreshold, confirmationThreshold) || other.confirmationThreshold == confirmationThreshold)&&(identical(other.reminderIntervalMinutes, reminderIntervalMinutes) || other.reminderIntervalMinutes == reminderIntervalMinutes)&&(identical(other.uptimePercentage, uptimePercentage) || other.uptimePercentage == uptimePercentage)&&(identical(other.heartbeatPingUrl, heartbeatPingUrl) || other.heartbeatPingUrl == heartbeatPingUrl)&&(identical(other.lastCheck, lastCheck) || other.lastCheck == lastCheck));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,id,name,url,monitorType,status,interval,timeout,const DeepCollectionEquality().hash(_settings),confirmationWindow,regionsRequired,const DeepCollectionEquality().hash(_alertContacts),createdAt,updatedAt,description,escalationPolicyId,confirmationThreshold,reminderIntervalMinutes,uptimePercentage,heartbeatPingUrl,lastCheck]);
}

@override
String toString() {
    return 'Monitor(id: $id, name: $name, url: $url, monitorType: $monitorType, status: $status, interval: $interval, timeout: $timeout, settings: $settings, confirmationWindow: $confirmationWindow, regionsRequired: $regionsRequired, alertContacts: $alertContacts, createdAt: $createdAt, updatedAt: $updatedAt, description: $description, escalationPolicyId: $escalationPolicyId, confirmationThreshold: $confirmationThreshold, reminderIntervalMinutes: $reminderIntervalMinutes, uptimePercentage: $uptimePercentage, heartbeatPingUrl: $heartbeatPingUrl, lastCheck: $lastCheck)';
}


}

/// @nodoc
abstract mixin class _$MonitorCopyWith<$Res> implements $MonitorCopyWith<$Res> {
  factory _$MonitorCopyWith(_Monitor value, $Res Function(_Monitor) _then) = __$MonitorCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String url,@JsonKey(name: 'monitor_type') String monitorType, String status, int interval, int timeout, Map<String, Object?> settings,@JsonKey(name: 'confirmation_window') String confirmationWindow,@JsonKey(name: 'regions_required') String regionsRequired,@JsonKey(name: 'alert_contacts') List<String> alertContacts,@JsonKey(name: 'created_at') String createdAt,@JsonKey(name: 'updated_at') String updatedAt, String? description,@JsonKey(name: 'escalation_policy_id') String? escalationPolicyId,@JsonKey(name: 'confirmation_threshold') int? confirmationThreshold,@JsonKey(name: 'reminder_interval_minutes') int? reminderIntervalMinutes,@JsonKey(name: 'uptime_percentage') double? uptimePercentage,@JsonKey(name: 'heartbeat_ping_url') String? heartbeatPingUrl,@JsonKey(name: 'last_check') LastCheck? lastCheck
});


@override $LastCheckCopyWith<$Res>? get lastCheck;

}
/// @nodoc
class __$MonitorCopyWithImpl<$Res>
    implements _$MonitorCopyWith<$Res> {
  __$MonitorCopyWithImpl(this._self, this._then);

  final _Monitor _self;
  final $Res Function(_Monitor) _then;

/// Create a copy of Monitor
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? url = null,Object? monitorType = null,Object? status = null,Object? interval = null,Object? timeout = null,Object? settings = null,Object? confirmationWindow = null,Object? regionsRequired = null,Object? alertContacts = null,Object? createdAt = null,Object? updatedAt = null,Object? description = freezed,Object? escalationPolicyId = freezed,Object? confirmationThreshold = freezed,Object? reminderIntervalMinutes = freezed,Object? uptimePercentage = freezed,Object? heartbeatPingUrl = freezed,Object? lastCheck = freezed,}) {
  return _then(_Monitor(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,monitorType: null == monitorType ? _self.monitorType : monitorType // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,interval: null == interval ? _self.interval : interval // ignore: cast_nullable_to_non_nullable
as int,timeout: null == timeout ? _self.timeout : timeout // ignore: cast_nullable_to_non_nullable
as int,settings: null == settings ? _self._settings : settings // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>,confirmationWindow: null == confirmationWindow ? _self.confirmationWindow : confirmationWindow // ignore: cast_nullable_to_non_nullable
as String,regionsRequired: null == regionsRequired ? _self.regionsRequired : regionsRequired // ignore: cast_nullable_to_non_nullable
as String,alertContacts: null == alertContacts ? _self._alertContacts : alertContacts // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,escalationPolicyId: freezed == escalationPolicyId ? _self.escalationPolicyId : escalationPolicyId // ignore: cast_nullable_to_non_nullable
as String?,confirmationThreshold: freezed == confirmationThreshold ? _self.confirmationThreshold : confirmationThreshold // ignore: cast_nullable_to_non_nullable
as int?,reminderIntervalMinutes: freezed == reminderIntervalMinutes ? _self.reminderIntervalMinutes : reminderIntervalMinutes // ignore: cast_nullable_to_non_nullable
as int?,uptimePercentage: freezed == uptimePercentage ? _self.uptimePercentage : uptimePercentage // ignore: cast_nullable_to_non_nullable
as double?,heartbeatPingUrl: freezed == heartbeatPingUrl ? _self.heartbeatPingUrl : heartbeatPingUrl // ignore: cast_nullable_to_non_nullable
as String?,lastCheck: freezed == lastCheck ? _self.lastCheck : lastCheck // ignore: cast_nullable_to_non_nullable
as LastCheck?,
  ));
}

/// Create a copy of Monitor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LastCheckCopyWith<$Res>? get lastCheck {
    if (_self.lastCheck == null) {
    return null;
  }

  return $LastCheckCopyWith<$Res>(_self.lastCheck!, (value) {
    return _then(_self.copyWith(lastCheck: value));
  });
}
}


/// @nodoc
mixin _$LastCheck {

 String get status;@JsonKey(name: 'response_time') int get responseTime;@JsonKey(name: 'checked_at') String get checkedAt;
/// Create a copy of LastCheck
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LastCheckCopyWith<LastCheck> get copyWith => _$LastCheckCopyWithImpl<LastCheck>(this as LastCheck, _$identity);

  /// Serializes this LastCheck to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as LastCheck;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LastCheck&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.responseTime, _this.responseTime) || other.responseTime == _this.responseTime)&&(identical(other.checkedAt, _this.checkedAt) || other.checkedAt == _this.checkedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as LastCheck;
  return Object.hash(runtimeType,_this.status,_this.responseTime,_this.checkedAt);
}

@override
String toString() {
  final _this = this as LastCheck;
  return 'LastCheck(status: ${_this.status}, responseTime: ${_this.responseTime}, checkedAt: ${_this.checkedAt})';
}


}

/// @nodoc
abstract mixin class $LastCheckCopyWith<$Res>  {
  factory $LastCheckCopyWith(LastCheck value, $Res Function(LastCheck) _then) = _$LastCheckCopyWithImpl;
@useResult
$Res call({
 String status,@JsonKey(name: 'response_time') int responseTime,@JsonKey(name: 'checked_at') String checkedAt
});




}
/// @nodoc
class _$LastCheckCopyWithImpl<$Res>
    implements $LastCheckCopyWith<$Res> {
  _$LastCheckCopyWithImpl(this._self, this._then);

  final LastCheck _self;
  final $Res Function(LastCheck) _then;

/// Create a copy of LastCheck
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? responseTime = null,Object? checkedAt = null,}) {
  return _then(LastCheck(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,responseTime: null == responseTime ? _self.responseTime : responseTime // ignore: cast_nullable_to_non_nullable
as int,checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [LastCheck].
extension LastCheckPatterns on LastCheck {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LastCheck value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LastCheck() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LastCheck value)  $default,){
final _that = this;
switch (_that) {
case _LastCheck():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LastCheck value)?  $default,){
final _that = this;
switch (_that) {
case _LastCheck() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String status, @JsonKey(name: 'response_time')  int responseTime, @JsonKey(name: 'checked_at')  String checkedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LastCheck() when $default != null:
return $default(_that.status,_that.responseTime,_that.checkedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String status, @JsonKey(name: 'response_time')  int responseTime, @JsonKey(name: 'checked_at')  String checkedAt)  $default,) {final _that = this;
switch (_that) {
case _LastCheck():
return $default(_that.status,_that.responseTime,_that.checkedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String status, @JsonKey(name: 'response_time')  int responseTime, @JsonKey(name: 'checked_at')  String checkedAt)?  $default,) {final _that = this;
switch (_that) {
case _LastCheck() when $default != null:
return $default(_that.status,_that.responseTime,_that.checkedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LastCheck implements LastCheck {
  const _LastCheck({required this.status, @JsonKey(name: 'response_time') required this.responseTime, @JsonKey(name: 'checked_at') required this.checkedAt});
  factory _LastCheck.fromJson(Map<String, dynamic> json) => _$LastCheckFromJson(json);

@override final  String status;
@override@JsonKey(name: 'response_time') final  int responseTime;
@override@JsonKey(name: 'checked_at') final  String checkedAt;

/// Create a copy of LastCheck
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LastCheckCopyWith<_LastCheck> get copyWith => __$LastCheckCopyWithImpl<_LastCheck>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LastCheckToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LastCheck&&(identical(other.status, status) || other.status == status)&&(identical(other.responseTime, responseTime) || other.responseTime == responseTime)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,status,responseTime,checkedAt);
}

@override
String toString() {
    return 'LastCheck(status: $status, responseTime: $responseTime, checkedAt: $checkedAt)';
}


}

/// @nodoc
abstract mixin class _$LastCheckCopyWith<$Res> implements $LastCheckCopyWith<$Res> {
  factory _$LastCheckCopyWith(_LastCheck value, $Res Function(_LastCheck) _then) = __$LastCheckCopyWithImpl;
@override @useResult
$Res call({
 String status,@JsonKey(name: 'response_time') int responseTime,@JsonKey(name: 'checked_at') String checkedAt
});




}
/// @nodoc
class __$LastCheckCopyWithImpl<$Res>
    implements _$LastCheckCopyWith<$Res> {
  __$LastCheckCopyWithImpl(this._self, this._then);

  final _LastCheck _self;
  final $Res Function(_LastCheck) _then;

/// Create a copy of LastCheck
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? responseTime = null,Object? checkedAt = null,}) {
  return _then(_LastCheck(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,responseTime: null == responseTime ? _self.responseTime : responseTime // ignore: cast_nullable_to_non_nullable
as int,checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
