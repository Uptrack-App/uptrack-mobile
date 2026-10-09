// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CachedMonitorsTable extends CachedMonitors
    with TableInfo<$CachedMonitorsTable, CachedMonitor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedMonitorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _monitorTypeMeta = const VerificationMeta(
    'monitorType',
  );
  @override
  late final GeneratedColumn<String> monitorType = GeneratedColumn<String>(
    'monitor_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _intervalMeta = const VerificationMeta(
    'interval',
  );
  @override
  late final GeneratedColumn<int> interval = GeneratedColumn<int>(
    'interval',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeoutMeta = const VerificationMeta(
    'timeout',
  );
  @override
  late final GeneratedColumn<int> timeout = GeneratedColumn<int>(
    'timeout',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uptimePercentageMeta = const VerificationMeta(
    'uptimePercentage',
  );
  @override
  late final GeneratedColumn<double> uptimePercentage = GeneratedColumn<double>(
    'uptime_percentage',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastCheckStatusMeta = const VerificationMeta(
    'lastCheckStatus',
  );
  @override
  late final GeneratedColumn<String> lastCheckStatus = GeneratedColumn<String>(
    'last_check_status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastCheckResponseTimeMeta =
      const VerificationMeta('lastCheckResponseTime');
  @override
  late final GeneratedColumn<int> lastCheckResponseTime = GeneratedColumn<int>(
    'last_check_response_time',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastCheckAtMeta = const VerificationMeta(
    'lastCheckAt',
  );
  @override
  late final GeneratedColumn<String> lastCheckAt = GeneratedColumn<String>(
    'last_check_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    url,
    monitorType,
    status,
    interval,
    timeout,
    uptimePercentage,
    lastCheckStatus,
    lastCheckResponseTime,
    lastCheckAt,
    updatedAt,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_monitors';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedMonitor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('monitor_type')) {
      context.handle(
        _monitorTypeMeta,
        monitorType.isAcceptableOrUnknown(
          data['monitor_type']!,
          _monitorTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_monitorTypeMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('interval')) {
      context.handle(
        _intervalMeta,
        interval.isAcceptableOrUnknown(data['interval']!, _intervalMeta),
      );
    } else if (isInserting) {
      context.missing(_intervalMeta);
    }
    if (data.containsKey('timeout')) {
      context.handle(
        _timeoutMeta,
        timeout.isAcceptableOrUnknown(data['timeout']!, _timeoutMeta),
      );
    } else if (isInserting) {
      context.missing(_timeoutMeta);
    }
    if (data.containsKey('uptime_percentage')) {
      context.handle(
        _uptimePercentageMeta,
        uptimePercentage.isAcceptableOrUnknown(
          data['uptime_percentage']!,
          _uptimePercentageMeta,
        ),
      );
    }
    if (data.containsKey('last_check_status')) {
      context.handle(
        _lastCheckStatusMeta,
        lastCheckStatus.isAcceptableOrUnknown(
          data['last_check_status']!,
          _lastCheckStatusMeta,
        ),
      );
    }
    if (data.containsKey('last_check_response_time')) {
      context.handle(
        _lastCheckResponseTimeMeta,
        lastCheckResponseTime.isAcceptableOrUnknown(
          data['last_check_response_time']!,
          _lastCheckResponseTimeMeta,
        ),
      );
    }
    if (data.containsKey('last_check_at')) {
      context.handle(
        _lastCheckAtMeta,
        lastCheckAt.isAcceptableOrUnknown(
          data['last_check_at']!,
          _lastCheckAtMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedMonitor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedMonitor(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      monitorType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}monitor_type'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      interval: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interval'],
      )!,
      timeout: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timeout'],
      )!,
      uptimePercentage: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}uptime_percentage'],
      ),
      lastCheckStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_check_status'],
      ),
      lastCheckResponseTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_check_response_time'],
      ),
      lastCheckAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_check_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedMonitorsTable createAlias(String alias) {
    return $CachedMonitorsTable(attachedDatabase, alias);
  }
}

class CachedMonitor extends DataClass implements Insertable<CachedMonitor> {
  final String id;
  final String name;
  final String url;
  final String monitorType;
  final String status;
  final int interval;
  final int timeout;
  final double? uptimePercentage;
  final String? lastCheckStatus;
  final int? lastCheckResponseTime;
  final String? lastCheckAt;
  final String updatedAt;
  final DateTime cachedAt;
  const CachedMonitor({
    required this.id,
    required this.name,
    required this.url,
    required this.monitorType,
    required this.status,
    required this.interval,
    required this.timeout,
    this.uptimePercentage,
    this.lastCheckStatus,
    this.lastCheckResponseTime,
    this.lastCheckAt,
    required this.updatedAt,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['url'] = Variable<String>(url);
    map['monitor_type'] = Variable<String>(monitorType);
    map['status'] = Variable<String>(status);
    map['interval'] = Variable<int>(interval);
    map['timeout'] = Variable<int>(timeout);
    if (!nullToAbsent || uptimePercentage != null) {
      map['uptime_percentage'] = Variable<double>(uptimePercentage);
    }
    if (!nullToAbsent || lastCheckStatus != null) {
      map['last_check_status'] = Variable<String>(lastCheckStatus);
    }
    if (!nullToAbsent || lastCheckResponseTime != null) {
      map['last_check_response_time'] = Variable<int>(lastCheckResponseTime);
    }
    if (!nullToAbsent || lastCheckAt != null) {
      map['last_check_at'] = Variable<String>(lastCheckAt);
    }
    map['updated_at'] = Variable<String>(updatedAt);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedMonitorsCompanion toCompanion(bool nullToAbsent) {
    return CachedMonitorsCompanion(
      id: Value(id),
      name: Value(name),
      url: Value(url),
      monitorType: Value(monitorType),
      status: Value(status),
      interval: Value(interval),
      timeout: Value(timeout),
      uptimePercentage: uptimePercentage == null && nullToAbsent
          ? const Value.absent()
          : Value(uptimePercentage),
      lastCheckStatus: lastCheckStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCheckStatus),
      lastCheckResponseTime: lastCheckResponseTime == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCheckResponseTime),
      lastCheckAt: lastCheckAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCheckAt),
      updatedAt: Value(updatedAt),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedMonitor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedMonitor(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      url: serializer.fromJson<String>(json['url']),
      monitorType: serializer.fromJson<String>(json['monitorType']),
      status: serializer.fromJson<String>(json['status']),
      interval: serializer.fromJson<int>(json['interval']),
      timeout: serializer.fromJson<int>(json['timeout']),
      uptimePercentage: serializer.fromJson<double?>(json['uptimePercentage']),
      lastCheckStatus: serializer.fromJson<String?>(json['lastCheckStatus']),
      lastCheckResponseTime: serializer.fromJson<int?>(
        json['lastCheckResponseTime'],
      ),
      lastCheckAt: serializer.fromJson<String?>(json['lastCheckAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'url': serializer.toJson<String>(url),
      'monitorType': serializer.toJson<String>(monitorType),
      'status': serializer.toJson<String>(status),
      'interval': serializer.toJson<int>(interval),
      'timeout': serializer.toJson<int>(timeout),
      'uptimePercentage': serializer.toJson<double?>(uptimePercentage),
      'lastCheckStatus': serializer.toJson<String?>(lastCheckStatus),
      'lastCheckResponseTime': serializer.toJson<int?>(lastCheckResponseTime),
      'lastCheckAt': serializer.toJson<String?>(lastCheckAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedMonitor copyWith({
    String? id,
    String? name,
    String? url,
    String? monitorType,
    String? status,
    int? interval,
    int? timeout,
    Value<double?> uptimePercentage = const Value.absent(),
    Value<String?> lastCheckStatus = const Value.absent(),
    Value<int?> lastCheckResponseTime = const Value.absent(),
    Value<String?> lastCheckAt = const Value.absent(),
    String? updatedAt,
    DateTime? cachedAt,
  }) => CachedMonitor(
    id: id ?? this.id,
    name: name ?? this.name,
    url: url ?? this.url,
    monitorType: monitorType ?? this.monitorType,
    status: status ?? this.status,
    interval: interval ?? this.interval,
    timeout: timeout ?? this.timeout,
    uptimePercentage: uptimePercentage.present
        ? uptimePercentage.value
        : this.uptimePercentage,
    lastCheckStatus: lastCheckStatus.present
        ? lastCheckStatus.value
        : this.lastCheckStatus,
    lastCheckResponseTime: lastCheckResponseTime.present
        ? lastCheckResponseTime.value
        : this.lastCheckResponseTime,
    lastCheckAt: lastCheckAt.present ? lastCheckAt.value : this.lastCheckAt,
    updatedAt: updatedAt ?? this.updatedAt,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedMonitor copyWithCompanion(CachedMonitorsCompanion data) {
    return CachedMonitor(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      url: data.url.present ? data.url.value : this.url,
      monitorType: data.monitorType.present
          ? data.monitorType.value
          : this.monitorType,
      status: data.status.present ? data.status.value : this.status,
      interval: data.interval.present ? data.interval.value : this.interval,
      timeout: data.timeout.present ? data.timeout.value : this.timeout,
      uptimePercentage: data.uptimePercentage.present
          ? data.uptimePercentage.value
          : this.uptimePercentage,
      lastCheckStatus: data.lastCheckStatus.present
          ? data.lastCheckStatus.value
          : this.lastCheckStatus,
      lastCheckResponseTime: data.lastCheckResponseTime.present
          ? data.lastCheckResponseTime.value
          : this.lastCheckResponseTime,
      lastCheckAt: data.lastCheckAt.present
          ? data.lastCheckAt.value
          : this.lastCheckAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedMonitor(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('monitorType: $monitorType, ')
          ..write('status: $status, ')
          ..write('interval: $interval, ')
          ..write('timeout: $timeout, ')
          ..write('uptimePercentage: $uptimePercentage, ')
          ..write('lastCheckStatus: $lastCheckStatus, ')
          ..write('lastCheckResponseTime: $lastCheckResponseTime, ')
          ..write('lastCheckAt: $lastCheckAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    url,
    monitorType,
    status,
    interval,
    timeout,
    uptimePercentage,
    lastCheckStatus,
    lastCheckResponseTime,
    lastCheckAt,
    updatedAt,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedMonitor &&
          other.id == this.id &&
          other.name == this.name &&
          other.url == this.url &&
          other.monitorType == this.monitorType &&
          other.status == this.status &&
          other.interval == this.interval &&
          other.timeout == this.timeout &&
          other.uptimePercentage == this.uptimePercentage &&
          other.lastCheckStatus == this.lastCheckStatus &&
          other.lastCheckResponseTime == this.lastCheckResponseTime &&
          other.lastCheckAt == this.lastCheckAt &&
          other.updatedAt == this.updatedAt &&
          other.cachedAt == this.cachedAt);
}

class CachedMonitorsCompanion extends UpdateCompanion<CachedMonitor> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> url;
  final Value<String> monitorType;
  final Value<String> status;
  final Value<int> interval;
  final Value<int> timeout;
  final Value<double?> uptimePercentage;
  final Value<String?> lastCheckStatus;
  final Value<int?> lastCheckResponseTime;
  final Value<String?> lastCheckAt;
  final Value<String> updatedAt;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedMonitorsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.url = const Value.absent(),
    this.monitorType = const Value.absent(),
    this.status = const Value.absent(),
    this.interval = const Value.absent(),
    this.timeout = const Value.absent(),
    this.uptimePercentage = const Value.absent(),
    this.lastCheckStatus = const Value.absent(),
    this.lastCheckResponseTime = const Value.absent(),
    this.lastCheckAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedMonitorsCompanion.insert({
    required String id,
    required String name,
    required String url,
    required String monitorType,
    required String status,
    required int interval,
    required int timeout,
    this.uptimePercentage = const Value.absent(),
    this.lastCheckStatus = const Value.absent(),
    this.lastCheckResponseTime = const Value.absent(),
    this.lastCheckAt = const Value.absent(),
    required String updatedAt,
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       url = Value(url),
       monitorType = Value(monitorType),
       status = Value(status),
       interval = Value(interval),
       timeout = Value(timeout),
       updatedAt = Value(updatedAt);
  static Insertable<CachedMonitor> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? url,
    Expression<String>? monitorType,
    Expression<String>? status,
    Expression<int>? interval,
    Expression<int>? timeout,
    Expression<double>? uptimePercentage,
    Expression<String>? lastCheckStatus,
    Expression<int>? lastCheckResponseTime,
    Expression<String>? lastCheckAt,
    Expression<String>? updatedAt,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (url != null) 'url': url,
      if (monitorType != null) 'monitor_type': monitorType,
      if (status != null) 'status': status,
      if (interval != null) 'interval': interval,
      if (timeout != null) 'timeout': timeout,
      if (uptimePercentage != null) 'uptime_percentage': uptimePercentage,
      if (lastCheckStatus != null) 'last_check_status': lastCheckStatus,
      if (lastCheckResponseTime != null)
        'last_check_response_time': lastCheckResponseTime,
      if (lastCheckAt != null) 'last_check_at': lastCheckAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedMonitorsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? url,
    Value<String>? monitorType,
    Value<String>? status,
    Value<int>? interval,
    Value<int>? timeout,
    Value<double?>? uptimePercentage,
    Value<String?>? lastCheckStatus,
    Value<int?>? lastCheckResponseTime,
    Value<String?>? lastCheckAt,
    Value<String>? updatedAt,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedMonitorsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      monitorType: monitorType ?? this.monitorType,
      status: status ?? this.status,
      interval: interval ?? this.interval,
      timeout: timeout ?? this.timeout,
      uptimePercentage: uptimePercentage ?? this.uptimePercentage,
      lastCheckStatus: lastCheckStatus ?? this.lastCheckStatus,
      lastCheckResponseTime:
          lastCheckResponseTime ?? this.lastCheckResponseTime,
      lastCheckAt: lastCheckAt ?? this.lastCheckAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (monitorType.present) {
      map['monitor_type'] = Variable<String>(monitorType.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (interval.present) {
      map['interval'] = Variable<int>(interval.value);
    }
    if (timeout.present) {
      map['timeout'] = Variable<int>(timeout.value);
    }
    if (uptimePercentage.present) {
      map['uptime_percentage'] = Variable<double>(uptimePercentage.value);
    }
    if (lastCheckStatus.present) {
      map['last_check_status'] = Variable<String>(lastCheckStatus.value);
    }
    if (lastCheckResponseTime.present) {
      map['last_check_response_time'] = Variable<int>(
        lastCheckResponseTime.value,
      );
    }
    if (lastCheckAt.present) {
      map['last_check_at'] = Variable<String>(lastCheckAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedMonitorsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('monitorType: $monitorType, ')
          ..write('status: $status, ')
          ..write('interval: $interval, ')
          ..write('timeout: $timeout, ')
          ..write('uptimePercentage: $uptimePercentage, ')
          ..write('lastCheckStatus: $lastCheckStatus, ')
          ..write('lastCheckResponseTime: $lastCheckResponseTime, ')
          ..write('lastCheckAt: $lastCheckAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedIncidentsTable extends CachedIncidents
    with TableInfo<$CachedIncidentsTable, CachedIncident> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedIncidentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _monitorIdMeta = const VerificationMeta(
    'monitorId',
  );
  @override
  late final GeneratedColumn<String> monitorId = GeneratedColumn<String>(
    'monitor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _monitorNameMeta = const VerificationMeta(
    'monitorName',
  );
  @override
  late final GeneratedColumn<String> monitorName = GeneratedColumn<String>(
    'monitor_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<String> startedAt = GeneratedColumn<String>(
    'started_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  @override
  late final GeneratedColumn<String> resolvedAt = GeneratedColumn<String>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _acknowledgedAtMeta = const VerificationMeta(
    'acknowledgedAt',
  );
  @override
  late final GeneratedColumn<String> acknowledgedAt = GeneratedColumn<String>(
    'acknowledged_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _insertedAtMeta = const VerificationMeta(
    'insertedAt',
  );
  @override
  late final GeneratedColumn<String> insertedAt = GeneratedColumn<String>(
    'inserted_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    monitorId,
    monitorName,
    status,
    startedAt,
    resolvedAt,
    acknowledgedAt,
    insertedAt,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_incidents';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedIncident> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('monitor_id')) {
      context.handle(
        _monitorIdMeta,
        monitorId.isAcceptableOrUnknown(data['monitor_id']!, _monitorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_monitorIdMeta);
    }
    if (data.containsKey('monitor_name')) {
      context.handle(
        _monitorNameMeta,
        monitorName.isAcceptableOrUnknown(
          data['monitor_name']!,
          _monitorNameMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
      );
    }
    if (data.containsKey('acknowledged_at')) {
      context.handle(
        _acknowledgedAtMeta,
        acknowledgedAt.isAcceptableOrUnknown(
          data['acknowledged_at']!,
          _acknowledgedAtMeta,
        ),
      );
    }
    if (data.containsKey('inserted_at')) {
      context.handle(
        _insertedAtMeta,
        insertedAt.isAcceptableOrUnknown(data['inserted_at']!, _insertedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_insertedAtMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedIncident map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedIncident(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      monitorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}monitor_id'],
      )!,
      monitorName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}monitor_name'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}started_at'],
      ),
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolved_at'],
      ),
      acknowledgedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}acknowledged_at'],
      ),
      insertedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inserted_at'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedIncidentsTable createAlias(String alias) {
    return $CachedIncidentsTable(attachedDatabase, alias);
  }
}

class CachedIncident extends DataClass implements Insertable<CachedIncident> {
  final String id;
  final String monitorId;
  final String? monitorName;
  final String status;
  final String? startedAt;
  final String? resolvedAt;
  final String? acknowledgedAt;
  final String insertedAt;
  final DateTime cachedAt;
  const CachedIncident({
    required this.id,
    required this.monitorId,
    this.monitorName,
    required this.status,
    this.startedAt,
    this.resolvedAt,
    this.acknowledgedAt,
    required this.insertedAt,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['monitor_id'] = Variable<String>(monitorId);
    if (!nullToAbsent || monitorName != null) {
      map['monitor_name'] = Variable<String>(monitorName);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<String>(startedAt);
    }
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<String>(resolvedAt);
    }
    if (!nullToAbsent || acknowledgedAt != null) {
      map['acknowledged_at'] = Variable<String>(acknowledgedAt);
    }
    map['inserted_at'] = Variable<String>(insertedAt);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedIncidentsCompanion toCompanion(bool nullToAbsent) {
    return CachedIncidentsCompanion(
      id: Value(id),
      monitorId: Value(monitorId),
      monitorName: monitorName == null && nullToAbsent
          ? const Value.absent()
          : Value(monitorName),
      status: Value(status),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
      acknowledgedAt: acknowledgedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(acknowledgedAt),
      insertedAt: Value(insertedAt),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedIncident.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedIncident(
      id: serializer.fromJson<String>(json['id']),
      monitorId: serializer.fromJson<String>(json['monitorId']),
      monitorName: serializer.fromJson<String?>(json['monitorName']),
      status: serializer.fromJson<String>(json['status']),
      startedAt: serializer.fromJson<String?>(json['startedAt']),
      resolvedAt: serializer.fromJson<String?>(json['resolvedAt']),
      acknowledgedAt: serializer.fromJson<String?>(json['acknowledgedAt']),
      insertedAt: serializer.fromJson<String>(json['insertedAt']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'monitorId': serializer.toJson<String>(monitorId),
      'monitorName': serializer.toJson<String?>(monitorName),
      'status': serializer.toJson<String>(status),
      'startedAt': serializer.toJson<String?>(startedAt),
      'resolvedAt': serializer.toJson<String?>(resolvedAt),
      'acknowledgedAt': serializer.toJson<String?>(acknowledgedAt),
      'insertedAt': serializer.toJson<String>(insertedAt),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedIncident copyWith({
    String? id,
    String? monitorId,
    Value<String?> monitorName = const Value.absent(),
    String? status,
    Value<String?> startedAt = const Value.absent(),
    Value<String?> resolvedAt = const Value.absent(),
    Value<String?> acknowledgedAt = const Value.absent(),
    String? insertedAt,
    DateTime? cachedAt,
  }) => CachedIncident(
    id: id ?? this.id,
    monitorId: monitorId ?? this.monitorId,
    monitorName: monitorName.present ? monitorName.value : this.monitorName,
    status: status ?? this.status,
    startedAt: startedAt.present ? startedAt.value : this.startedAt,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
    acknowledgedAt: acknowledgedAt.present
        ? acknowledgedAt.value
        : this.acknowledgedAt,
    insertedAt: insertedAt ?? this.insertedAt,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedIncident copyWithCompanion(CachedIncidentsCompanion data) {
    return CachedIncident(
      id: data.id.present ? data.id.value : this.id,
      monitorId: data.monitorId.present ? data.monitorId.value : this.monitorId,
      monitorName: data.monitorName.present
          ? data.monitorName.value
          : this.monitorName,
      status: data.status.present ? data.status.value : this.status,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
      acknowledgedAt: data.acknowledgedAt.present
          ? data.acknowledgedAt.value
          : this.acknowledgedAt,
      insertedAt: data.insertedAt.present
          ? data.insertedAt.value
          : this.insertedAt,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedIncident(')
          ..write('id: $id, ')
          ..write('monitorId: $monitorId, ')
          ..write('monitorName: $monitorName, ')
          ..write('status: $status, ')
          ..write('startedAt: $startedAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('acknowledgedAt: $acknowledgedAt, ')
          ..write('insertedAt: $insertedAt, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    monitorId,
    monitorName,
    status,
    startedAt,
    resolvedAt,
    acknowledgedAt,
    insertedAt,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedIncident &&
          other.id == this.id &&
          other.monitorId == this.monitorId &&
          other.monitorName == this.monitorName &&
          other.status == this.status &&
          other.startedAt == this.startedAt &&
          other.resolvedAt == this.resolvedAt &&
          other.acknowledgedAt == this.acknowledgedAt &&
          other.insertedAt == this.insertedAt &&
          other.cachedAt == this.cachedAt);
}

class CachedIncidentsCompanion extends UpdateCompanion<CachedIncident> {
  final Value<String> id;
  final Value<String> monitorId;
  final Value<String?> monitorName;
  final Value<String> status;
  final Value<String?> startedAt;
  final Value<String?> resolvedAt;
  final Value<String?> acknowledgedAt;
  final Value<String> insertedAt;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedIncidentsCompanion({
    this.id = const Value.absent(),
    this.monitorId = const Value.absent(),
    this.monitorName = const Value.absent(),
    this.status = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
    this.insertedAt = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedIncidentsCompanion.insert({
    required String id,
    required String monitorId,
    this.monitorName = const Value.absent(),
    required String status,
    this.startedAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
    required String insertedAt,
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       monitorId = Value(monitorId),
       status = Value(status),
       insertedAt = Value(insertedAt);
  static Insertable<CachedIncident> custom({
    Expression<String>? id,
    Expression<String>? monitorId,
    Expression<String>? monitorName,
    Expression<String>? status,
    Expression<String>? startedAt,
    Expression<String>? resolvedAt,
    Expression<String>? acknowledgedAt,
    Expression<String>? insertedAt,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (monitorId != null) 'monitor_id': monitorId,
      if (monitorName != null) 'monitor_name': monitorName,
      if (status != null) 'status': status,
      if (startedAt != null) 'started_at': startedAt,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (acknowledgedAt != null) 'acknowledged_at': acknowledgedAt,
      if (insertedAt != null) 'inserted_at': insertedAt,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedIncidentsCompanion copyWith({
    Value<String>? id,
    Value<String>? monitorId,
    Value<String?>? monitorName,
    Value<String>? status,
    Value<String?>? startedAt,
    Value<String?>? resolvedAt,
    Value<String?>? acknowledgedAt,
    Value<String>? insertedAt,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedIncidentsCompanion(
      id: id ?? this.id,
      monitorId: monitorId ?? this.monitorId,
      monitorName: monitorName ?? this.monitorName,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      insertedAt: insertedAt ?? this.insertedAt,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (monitorId.present) {
      map['monitor_id'] = Variable<String>(monitorId.value);
    }
    if (monitorName.present) {
      map['monitor_name'] = Variable<String>(monitorName.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<String>(startedAt.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<String>(resolvedAt.value);
    }
    if (acknowledgedAt.present) {
      map['acknowledged_at'] = Variable<String>(acknowledgedAt.value);
    }
    if (insertedAt.present) {
      map['inserted_at'] = Variable<String>(insertedAt.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedIncidentsCompanion(')
          ..write('id: $id, ')
          ..write('monitorId: $monitorId, ')
          ..write('monitorName: $monitorName, ')
          ..write('status: $status, ')
          ..write('startedAt: $startedAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('acknowledgedAt: $acknowledgedAt, ')
          ..write('insertedAt: $insertedAt, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedChecksTable extends CachedChecks
    with TableInfo<$CachedChecksTable, CachedCheck> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedChecksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _monitorIdMeta = const VerificationMeta(
    'monitorId',
  );
  @override
  late final GeneratedColumn<String> monitorId = GeneratedColumn<String>(
    'monitor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _responseTimeMeta = const VerificationMeta(
    'responseTime',
  );
  @override
  late final GeneratedColumn<int> responseTime = GeneratedColumn<int>(
    'response_time',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusCodeMeta = const VerificationMeta(
    'statusCode',
  );
  @override
  late final GeneratedColumn<int> statusCode = GeneratedColumn<int>(
    'status_code',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checkedAtMeta = const VerificationMeta(
    'checkedAt',
  );
  @override
  late final GeneratedColumn<String> checkedAt = GeneratedColumn<String>(
    'checked_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    monitorId,
    status,
    responseTime,
    statusCode,
    checkedAt,
    errorMessage,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_checks';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedCheck> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('monitor_id')) {
      context.handle(
        _monitorIdMeta,
        monitorId.isAcceptableOrUnknown(data['monitor_id']!, _monitorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_monitorIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('response_time')) {
      context.handle(
        _responseTimeMeta,
        responseTime.isAcceptableOrUnknown(
          data['response_time']!,
          _responseTimeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_responseTimeMeta);
    }
    if (data.containsKey('status_code')) {
      context.handle(
        _statusCodeMeta,
        statusCode.isAcceptableOrUnknown(data['status_code']!, _statusCodeMeta),
      );
    } else if (isInserting) {
      context.missing(_statusCodeMeta);
    }
    if (data.containsKey('checked_at')) {
      context.handle(
        _checkedAtMeta,
        checkedAt.isAcceptableOrUnknown(data['checked_at']!, _checkedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_checkedAtMeta);
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedCheck map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedCheck(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      monitorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}monitor_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      responseTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}response_time'],
      )!,
      statusCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status_code'],
      )!,
      checkedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checked_at'],
      )!,
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
    );
  }

  @override
  $CachedChecksTable createAlias(String alias) {
    return $CachedChecksTable(attachedDatabase, alias);
  }
}

class CachedCheck extends DataClass implements Insertable<CachedCheck> {
  final int id;
  final String monitorId;
  final String status;
  final int responseTime;
  final int statusCode;
  final String checkedAt;
  final String? errorMessage;
  const CachedCheck({
    required this.id,
    required this.monitorId,
    required this.status,
    required this.responseTime,
    required this.statusCode,
    required this.checkedAt,
    this.errorMessage,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['monitor_id'] = Variable<String>(monitorId);
    map['status'] = Variable<String>(status);
    map['response_time'] = Variable<int>(responseTime);
    map['status_code'] = Variable<int>(statusCode);
    map['checked_at'] = Variable<String>(checkedAt);
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    return map;
  }

  CachedChecksCompanion toCompanion(bool nullToAbsent) {
    return CachedChecksCompanion(
      id: Value(id),
      monitorId: Value(monitorId),
      status: Value(status),
      responseTime: Value(responseTime),
      statusCode: Value(statusCode),
      checkedAt: Value(checkedAt),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
    );
  }

  factory CachedCheck.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedCheck(
      id: serializer.fromJson<int>(json['id']),
      monitorId: serializer.fromJson<String>(json['monitorId']),
      status: serializer.fromJson<String>(json['status']),
      responseTime: serializer.fromJson<int>(json['responseTime']),
      statusCode: serializer.fromJson<int>(json['statusCode']),
      checkedAt: serializer.fromJson<String>(json['checkedAt']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'monitorId': serializer.toJson<String>(monitorId),
      'status': serializer.toJson<String>(status),
      'responseTime': serializer.toJson<int>(responseTime),
      'statusCode': serializer.toJson<int>(statusCode),
      'checkedAt': serializer.toJson<String>(checkedAt),
      'errorMessage': serializer.toJson<String?>(errorMessage),
    };
  }

  CachedCheck copyWith({
    int? id,
    String? monitorId,
    String? status,
    int? responseTime,
    int? statusCode,
    String? checkedAt,
    Value<String?> errorMessage = const Value.absent(),
  }) => CachedCheck(
    id: id ?? this.id,
    monitorId: monitorId ?? this.monitorId,
    status: status ?? this.status,
    responseTime: responseTime ?? this.responseTime,
    statusCode: statusCode ?? this.statusCode,
    checkedAt: checkedAt ?? this.checkedAt,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
  );
  CachedCheck copyWithCompanion(CachedChecksCompanion data) {
    return CachedCheck(
      id: data.id.present ? data.id.value : this.id,
      monitorId: data.monitorId.present ? data.monitorId.value : this.monitorId,
      status: data.status.present ? data.status.value : this.status,
      responseTime: data.responseTime.present
          ? data.responseTime.value
          : this.responseTime,
      statusCode: data.statusCode.present
          ? data.statusCode.value
          : this.statusCode,
      checkedAt: data.checkedAt.present ? data.checkedAt.value : this.checkedAt,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedCheck(')
          ..write('id: $id, ')
          ..write('monitorId: $monitorId, ')
          ..write('status: $status, ')
          ..write('responseTime: $responseTime, ')
          ..write('statusCode: $statusCode, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('errorMessage: $errorMessage')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    monitorId,
    status,
    responseTime,
    statusCode,
    checkedAt,
    errorMessage,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedCheck &&
          other.id == this.id &&
          other.monitorId == this.monitorId &&
          other.status == this.status &&
          other.responseTime == this.responseTime &&
          other.statusCode == this.statusCode &&
          other.checkedAt == this.checkedAt &&
          other.errorMessage == this.errorMessage);
}

class CachedChecksCompanion extends UpdateCompanion<CachedCheck> {
  final Value<int> id;
  final Value<String> monitorId;
  final Value<String> status;
  final Value<int> responseTime;
  final Value<int> statusCode;
  final Value<String> checkedAt;
  final Value<String?> errorMessage;
  const CachedChecksCompanion({
    this.id = const Value.absent(),
    this.monitorId = const Value.absent(),
    this.status = const Value.absent(),
    this.responseTime = const Value.absent(),
    this.statusCode = const Value.absent(),
    this.checkedAt = const Value.absent(),
    this.errorMessage = const Value.absent(),
  });
  CachedChecksCompanion.insert({
    this.id = const Value.absent(),
    required String monitorId,
    required String status,
    required int responseTime,
    required int statusCode,
    required String checkedAt,
    this.errorMessage = const Value.absent(),
  }) : monitorId = Value(monitorId),
       status = Value(status),
       responseTime = Value(responseTime),
       statusCode = Value(statusCode),
       checkedAt = Value(checkedAt);
  static Insertable<CachedCheck> custom({
    Expression<int>? id,
    Expression<String>? monitorId,
    Expression<String>? status,
    Expression<int>? responseTime,
    Expression<int>? statusCode,
    Expression<String>? checkedAt,
    Expression<String>? errorMessage,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (monitorId != null) 'monitor_id': monitorId,
      if (status != null) 'status': status,
      if (responseTime != null) 'response_time': responseTime,
      if (statusCode != null) 'status_code': statusCode,
      if (checkedAt != null) 'checked_at': checkedAt,
      if (errorMessage != null) 'error_message': errorMessage,
    });
  }

  CachedChecksCompanion copyWith({
    Value<int>? id,
    Value<String>? monitorId,
    Value<String>? status,
    Value<int>? responseTime,
    Value<int>? statusCode,
    Value<String>? checkedAt,
    Value<String?>? errorMessage,
  }) {
    return CachedChecksCompanion(
      id: id ?? this.id,
      monitorId: monitorId ?? this.monitorId,
      status: status ?? this.status,
      responseTime: responseTime ?? this.responseTime,
      statusCode: statusCode ?? this.statusCode,
      checkedAt: checkedAt ?? this.checkedAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (monitorId.present) {
      map['monitor_id'] = Variable<String>(monitorId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (responseTime.present) {
      map['response_time'] = Variable<int>(responseTime.value);
    }
    if (statusCode.present) {
      map['status_code'] = Variable<int>(statusCode.value);
    }
    if (checkedAt.present) {
      map['checked_at'] = Variable<String>(checkedAt.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedChecksCompanion(')
          ..write('id: $id, ')
          ..write('monitorId: $monitorId, ')
          ..write('status: $status, ')
          ..write('responseTime: $responseTime, ')
          ..write('statusCode: $statusCode, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('errorMessage: $errorMessage')
          ..write(')'))
        .toString();
  }
}

class $CacheMetaTable extends CacheMeta
    with TableInfo<$CacheMetaTable, CacheMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<CacheMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CacheMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheMetaData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CacheMetaTable createAlias(String alias) {
    return $CacheMetaTable(attachedDatabase, alias);
  }
}

class CacheMetaData extends DataClass implements Insertable<CacheMetaData> {
  final String key;
  final DateTime updatedAt;
  const CacheMetaData({required this.key, required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CacheMetaCompanion toCompanion(bool nullToAbsent) {
    return CacheMetaCompanion(key: Value(key), updatedAt: Value(updatedAt));
  }

  factory CacheMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheMetaData(
      key: serializer.fromJson<String>(json['key']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CacheMetaData copyWith({String? key, DateTime? updatedAt}) => CacheMetaData(
    key: key ?? this.key,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CacheMetaData copyWithCompanion(CacheMetaCompanion data) {
    return CacheMetaData(
      key: data.key.present ? data.key.value : this.key,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheMetaData(')
          ..write('key: $key, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheMetaData &&
          other.key == this.key &&
          other.updatedAt == this.updatedAt);
}

class CacheMetaCompanion extends UpdateCompanion<CacheMetaData> {
  final Value<String> key;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CacheMetaCompanion({
    this.key = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheMetaCompanion.insert({
    required String key,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       updatedAt = Value(updatedAt);
  static Insertable<CacheMetaData> custom({
    Expression<String>? key,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheMetaCompanion copyWith({
    Value<String>? key,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CacheMetaCompanion(
      key: key ?? this.key,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheMetaCompanion(')
          ..write('key: $key, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedIncidentDetailsTable extends CachedIncidentDetails
    with TableInfo<$CachedIncidentDetailsTable, CachedIncidentDetail> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedIncidentDetailsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _incidentIdMeta = const VerificationMeta(
    'incidentId',
  );
  @override
  late final GeneratedColumn<String> incidentId = GeneratedColumn<String>(
    'incident_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatesJsonMeta = const VerificationMeta(
    'updatesJson',
  );
  @override
  late final GeneratedColumn<String> updatesJson = GeneratedColumn<String>(
    'updates_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [incidentId, updatesJson, syncedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_incident_details';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedIncidentDetail> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('incident_id')) {
      context.handle(
        _incidentIdMeta,
        incidentId.isAcceptableOrUnknown(data['incident_id']!, _incidentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_incidentIdMeta);
    }
    if (data.containsKey('updates_json')) {
      context.handle(
        _updatesJsonMeta,
        updatesJson.isAcceptableOrUnknown(
          data['updates_json']!,
          _updatesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatesJsonMeta);
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_syncedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {incidentId};
  @override
  CachedIncidentDetail map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedIncidentDetail(
      incidentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}incident_id'],
      )!,
      updatesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updates_json'],
      )!,
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      )!,
    );
  }

  @override
  $CachedIncidentDetailsTable createAlias(String alias) {
    return $CachedIncidentDetailsTable(attachedDatabase, alias);
  }
}

class CachedIncidentDetail extends DataClass
    implements Insertable<CachedIncidentDetail> {
  final String incidentId;

  /// Posted updates exactly as the last successful detail read returned them,
  /// JSON-encoded in server order (see `CacheRepository.encodeIncidentUpdates`).
  final String updatesJson;

  /// When those updates were actually last read from the API — the honest
  /// "updates last synced" time, never the moment a cached row was read back.
  final DateTime syncedAt;
  const CachedIncidentDetail({
    required this.incidentId,
    required this.updatesJson,
    required this.syncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['incident_id'] = Variable<String>(incidentId);
    map['updates_json'] = Variable<String>(updatesJson);
    map['synced_at'] = Variable<DateTime>(syncedAt);
    return map;
  }

  CachedIncidentDetailsCompanion toCompanion(bool nullToAbsent) {
    return CachedIncidentDetailsCompanion(
      incidentId: Value(incidentId),
      updatesJson: Value(updatesJson),
      syncedAt: Value(syncedAt),
    );
  }

  factory CachedIncidentDetail.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedIncidentDetail(
      incidentId: serializer.fromJson<String>(json['incidentId']),
      updatesJson: serializer.fromJson<String>(json['updatesJson']),
      syncedAt: serializer.fromJson<DateTime>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'incidentId': serializer.toJson<String>(incidentId),
      'updatesJson': serializer.toJson<String>(updatesJson),
      'syncedAt': serializer.toJson<DateTime>(syncedAt),
    };
  }

  CachedIncidentDetail copyWith({
    String? incidentId,
    String? updatesJson,
    DateTime? syncedAt,
  }) => CachedIncidentDetail(
    incidentId: incidentId ?? this.incidentId,
    updatesJson: updatesJson ?? this.updatesJson,
    syncedAt: syncedAt ?? this.syncedAt,
  );
  CachedIncidentDetail copyWithCompanion(CachedIncidentDetailsCompanion data) {
    return CachedIncidentDetail(
      incidentId: data.incidentId.present
          ? data.incidentId.value
          : this.incidentId,
      updatesJson: data.updatesJson.present
          ? data.updatesJson.value
          : this.updatesJson,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedIncidentDetail(')
          ..write('incidentId: $incidentId, ')
          ..write('updatesJson: $updatesJson, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(incidentId, updatesJson, syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedIncidentDetail &&
          other.incidentId == this.incidentId &&
          other.updatesJson == this.updatesJson &&
          other.syncedAt == this.syncedAt);
}

class CachedIncidentDetailsCompanion
    extends UpdateCompanion<CachedIncidentDetail> {
  final Value<String> incidentId;
  final Value<String> updatesJson;
  final Value<DateTime> syncedAt;
  final Value<int> rowid;
  const CachedIncidentDetailsCompanion({
    this.incidentId = const Value.absent(),
    this.updatesJson = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedIncidentDetailsCompanion.insert({
    required String incidentId,
    required String updatesJson,
    required DateTime syncedAt,
    this.rowid = const Value.absent(),
  }) : incidentId = Value(incidentId),
       updatesJson = Value(updatesJson),
       syncedAt = Value(syncedAt);
  static Insertable<CachedIncidentDetail> custom({
    Expression<String>? incidentId,
    Expression<String>? updatesJson,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (incidentId != null) 'incident_id': incidentId,
      if (updatesJson != null) 'updates_json': updatesJson,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedIncidentDetailsCompanion copyWith({
    Value<String>? incidentId,
    Value<String>? updatesJson,
    Value<DateTime>? syncedAt,
    Value<int>? rowid,
  }) {
    return CachedIncidentDetailsCompanion(
      incidentId: incidentId ?? this.incidentId,
      updatesJson: updatesJson ?? this.updatesJson,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (incidentId.present) {
      map['incident_id'] = Variable<String>(incidentId.value);
    }
    if (updatesJson.present) {
      map['updates_json'] = Variable<String>(updatesJson.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedIncidentDetailsCompanion(')
          ..write('incidentId: $incidentId, ')
          ..write('updatesJson: $updatesJson, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CachedMonitorsTable cachedMonitors = $CachedMonitorsTable(this);
  late final $CachedIncidentsTable cachedIncidents = $CachedIncidentsTable(
    this,
  );
  late final $CachedChecksTable cachedChecks = $CachedChecksTable(this);
  late final $CacheMetaTable cacheMeta = $CacheMetaTable(this);
  late final $CachedIncidentDetailsTable cachedIncidentDetails =
      $CachedIncidentDetailsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedMonitors,
    cachedIncidents,
    cachedChecks,
    cacheMeta,
    cachedIncidentDetails,
  ];
}

typedef $$CachedMonitorsTableCreateCompanionBuilder =
    CachedMonitorsCompanion Function({
      required String id,
      required String name,
      required String url,
      required String monitorType,
      required String status,
      required int interval,
      required int timeout,
      Value<double?> uptimePercentage,
      Value<String?> lastCheckStatus,
      Value<int?> lastCheckResponseTime,
      Value<String?> lastCheckAt,
      required String updatedAt,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });
typedef $$CachedMonitorsTableUpdateCompanionBuilder =
    CachedMonitorsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> url,
      Value<String> monitorType,
      Value<String> status,
      Value<int> interval,
      Value<int> timeout,
      Value<double?> uptimePercentage,
      Value<String?> lastCheckStatus,
      Value<int?> lastCheckResponseTime,
      Value<String?> lastCheckAt,
      Value<String> updatedAt,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedMonitorsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedMonitorsTable> {
  $$CachedMonitorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get monitorType => $composableBuilder(
    column: $table.monitorType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get interval => $composableBuilder(
    column: $table.interval,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeout => $composableBuilder(
    column: $table.timeout,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get uptimePercentage => $composableBuilder(
    column: $table.uptimePercentage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCheckStatus => $composableBuilder(
    column: $table.lastCheckStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastCheckResponseTime => $composableBuilder(
    column: $table.lastCheckResponseTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCheckAt => $composableBuilder(
    column: $table.lastCheckAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedMonitorsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedMonitorsTable> {
  $$CachedMonitorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get monitorType => $composableBuilder(
    column: $table.monitorType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get interval => $composableBuilder(
    column: $table.interval,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeout => $composableBuilder(
    column: $table.timeout,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get uptimePercentage => $composableBuilder(
    column: $table.uptimePercentage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCheckStatus => $composableBuilder(
    column: $table.lastCheckStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastCheckResponseTime => $composableBuilder(
    column: $table.lastCheckResponseTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCheckAt => $composableBuilder(
    column: $table.lastCheckAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedMonitorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedMonitorsTable> {
  $$CachedMonitorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get monitorType => $composableBuilder(
    column: $table.monitorType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get interval =>
      $composableBuilder(column: $table.interval, builder: (column) => column);

  GeneratedColumn<int> get timeout =>
      $composableBuilder(column: $table.timeout, builder: (column) => column);

  GeneratedColumn<double> get uptimePercentage => $composableBuilder(
    column: $table.uptimePercentage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastCheckStatus => $composableBuilder(
    column: $table.lastCheckStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastCheckResponseTime => $composableBuilder(
    column: $table.lastCheckResponseTime,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastCheckAt => $composableBuilder(
    column: $table.lastCheckAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedMonitorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedMonitorsTable,
          CachedMonitor,
          $$CachedMonitorsTableFilterComposer,
          $$CachedMonitorsTableOrderingComposer,
          $$CachedMonitorsTableAnnotationComposer,
          $$CachedMonitorsTableCreateCompanionBuilder,
          $$CachedMonitorsTableUpdateCompanionBuilder,
          (
            CachedMonitor,
            BaseReferences<_$AppDatabase, $CachedMonitorsTable, CachedMonitor>,
          ),
          CachedMonitor,
          PrefetchHooks Function()
        > {
  $$CachedMonitorsTableTableManager(
    _$AppDatabase db,
    $CachedMonitorsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedMonitorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedMonitorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedMonitorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> monitorType = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> interval = const Value.absent(),
                Value<int> timeout = const Value.absent(),
                Value<double?> uptimePercentage = const Value.absent(),
                Value<String?> lastCheckStatus = const Value.absent(),
                Value<int?> lastCheckResponseTime = const Value.absent(),
                Value<String?> lastCheckAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMonitorsCompanion(
                id: id,
                name: name,
                url: url,
                monitorType: monitorType,
                status: status,
                interval: interval,
                timeout: timeout,
                uptimePercentage: uptimePercentage,
                lastCheckStatus: lastCheckStatus,
                lastCheckResponseTime: lastCheckResponseTime,
                lastCheckAt: lastCheckAt,
                updatedAt: updatedAt,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String url,
                required String monitorType,
                required String status,
                required int interval,
                required int timeout,
                Value<double?> uptimePercentage = const Value.absent(),
                Value<String?> lastCheckStatus = const Value.absent(),
                Value<int?> lastCheckResponseTime = const Value.absent(),
                Value<String?> lastCheckAt = const Value.absent(),
                required String updatedAt,
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMonitorsCompanion.insert(
                id: id,
                name: name,
                url: url,
                monitorType: monitorType,
                status: status,
                interval: interval,
                timeout: timeout,
                uptimePercentage: uptimePercentage,
                lastCheckStatus: lastCheckStatus,
                lastCheckResponseTime: lastCheckResponseTime,
                lastCheckAt: lastCheckAt,
                updatedAt: updatedAt,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedMonitorsTable, CachedMonitor>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedMonitorsTable,
                    CachedMonitor
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedMonitorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedMonitorsTable,
      CachedMonitor,
      $$CachedMonitorsTableFilterComposer,
      $$CachedMonitorsTableOrderingComposer,
      $$CachedMonitorsTableAnnotationComposer,
      $$CachedMonitorsTableCreateCompanionBuilder,
      $$CachedMonitorsTableUpdateCompanionBuilder,
      (
        CachedMonitor,
        BaseReferences<_$AppDatabase, $CachedMonitorsTable, CachedMonitor>,
      ),
      CachedMonitor,
      PrefetchHooks Function()
    >;
typedef $$CachedIncidentsTableCreateCompanionBuilder =
    CachedIncidentsCompanion Function({
      required String id,
      required String monitorId,
      Value<String?> monitorName,
      required String status,
      Value<String?> startedAt,
      Value<String?> resolvedAt,
      Value<String?> acknowledgedAt,
      required String insertedAt,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });
typedef $$CachedIncidentsTableUpdateCompanionBuilder =
    CachedIncidentsCompanion Function({
      Value<String> id,
      Value<String> monitorId,
      Value<String?> monitorName,
      Value<String> status,
      Value<String?> startedAt,
      Value<String?> resolvedAt,
      Value<String?> acknowledgedAt,
      Value<String> insertedAt,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedIncidentsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedIncidentsTable> {
  $$CachedIncidentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get monitorId => $composableBuilder(
    column: $table.monitorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get monitorName => $composableBuilder(
    column: $table.monitorName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get acknowledgedAt => $composableBuilder(
    column: $table.acknowledgedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get insertedAt => $composableBuilder(
    column: $table.insertedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedIncidentsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedIncidentsTable> {
  $$CachedIncidentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get monitorId => $composableBuilder(
    column: $table.monitorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get monitorName => $composableBuilder(
    column: $table.monitorName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get acknowledgedAt => $composableBuilder(
    column: $table.acknowledgedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get insertedAt => $composableBuilder(
    column: $table.insertedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedIncidentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedIncidentsTable> {
  $$CachedIncidentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get monitorId =>
      $composableBuilder(column: $table.monitorId, builder: (column) => column);

  GeneratedColumn<String> get monitorName => $composableBuilder(
    column: $table.monitorName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<String> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get acknowledgedAt => $composableBuilder(
    column: $table.acknowledgedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get insertedAt => $composableBuilder(
    column: $table.insertedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedIncidentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedIncidentsTable,
          CachedIncident,
          $$CachedIncidentsTableFilterComposer,
          $$CachedIncidentsTableOrderingComposer,
          $$CachedIncidentsTableAnnotationComposer,
          $$CachedIncidentsTableCreateCompanionBuilder,
          $$CachedIncidentsTableUpdateCompanionBuilder,
          (
            CachedIncident,
            BaseReferences<
              _$AppDatabase,
              $CachedIncidentsTable,
              CachedIncident
            >,
          ),
          CachedIncident,
          PrefetchHooks Function()
        > {
  $$CachedIncidentsTableTableManager(
    _$AppDatabase db,
    $CachedIncidentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedIncidentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedIncidentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedIncidentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> monitorId = const Value.absent(),
                Value<String?> monitorName = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> startedAt = const Value.absent(),
                Value<String?> resolvedAt = const Value.absent(),
                Value<String?> acknowledgedAt = const Value.absent(),
                Value<String> insertedAt = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedIncidentsCompanion(
                id: id,
                monitorId: monitorId,
                monitorName: monitorName,
                status: status,
                startedAt: startedAt,
                resolvedAt: resolvedAt,
                acknowledgedAt: acknowledgedAt,
                insertedAt: insertedAt,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String monitorId,
                Value<String?> monitorName = const Value.absent(),
                required String status,
                Value<String?> startedAt = const Value.absent(),
                Value<String?> resolvedAt = const Value.absent(),
                Value<String?> acknowledgedAt = const Value.absent(),
                required String insertedAt,
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedIncidentsCompanion.insert(
                id: id,
                monitorId: monitorId,
                monitorName: monitorName,
                status: status,
                startedAt: startedAt,
                resolvedAt: resolvedAt,
                acknowledgedAt: acknowledgedAt,
                insertedAt: insertedAt,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedIncidentsTable, CachedIncident>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedIncidentsTable,
                    CachedIncident
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedIncidentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedIncidentsTable,
      CachedIncident,
      $$CachedIncidentsTableFilterComposer,
      $$CachedIncidentsTableOrderingComposer,
      $$CachedIncidentsTableAnnotationComposer,
      $$CachedIncidentsTableCreateCompanionBuilder,
      $$CachedIncidentsTableUpdateCompanionBuilder,
      (
        CachedIncident,
        BaseReferences<_$AppDatabase, $CachedIncidentsTable, CachedIncident>,
      ),
      CachedIncident,
      PrefetchHooks Function()
    >;
typedef $$CachedChecksTableCreateCompanionBuilder =
    CachedChecksCompanion Function({
      Value<int> id,
      required String monitorId,
      required String status,
      required int responseTime,
      required int statusCode,
      required String checkedAt,
      Value<String?> errorMessage,
    });
typedef $$CachedChecksTableUpdateCompanionBuilder =
    CachedChecksCompanion Function({
      Value<int> id,
      Value<String> monitorId,
      Value<String> status,
      Value<int> responseTime,
      Value<int> statusCode,
      Value<String> checkedAt,
      Value<String?> errorMessage,
    });

class $$CachedChecksTableFilterComposer
    extends Composer<_$AppDatabase, $CachedChecksTable> {
  $$CachedChecksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get monitorId => $composableBuilder(
    column: $table.monitorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get responseTime => $composableBuilder(
    column: $table.responseTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get statusCode => $composableBuilder(
    column: $table.statusCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedChecksTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedChecksTable> {
  $$CachedChecksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get monitorId => $composableBuilder(
    column: $table.monitorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get responseTime => $composableBuilder(
    column: $table.responseTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get statusCode => $composableBuilder(
    column: $table.statusCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedChecksTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedChecksTable> {
  $$CachedChecksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get monitorId =>
      $composableBuilder(column: $table.monitorId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get responseTime => $composableBuilder(
    column: $table.responseTime,
    builder: (column) => column,
  );

  GeneratedColumn<int> get statusCode => $composableBuilder(
    column: $table.statusCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get checkedAt =>
      $composableBuilder(column: $table.checkedAt, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );
}

class $$CachedChecksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedChecksTable,
          CachedCheck,
          $$CachedChecksTableFilterComposer,
          $$CachedChecksTableOrderingComposer,
          $$CachedChecksTableAnnotationComposer,
          $$CachedChecksTableCreateCompanionBuilder,
          $$CachedChecksTableUpdateCompanionBuilder,
          (
            CachedCheck,
            BaseReferences<_$AppDatabase, $CachedChecksTable, CachedCheck>,
          ),
          CachedCheck,
          PrefetchHooks Function()
        > {
  $$CachedChecksTableTableManager(_$AppDatabase db, $CachedChecksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedChecksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedChecksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedChecksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> monitorId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> responseTime = const Value.absent(),
                Value<int> statusCode = const Value.absent(),
                Value<String> checkedAt = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
              }) => CachedChecksCompanion(
                id: id,
                monitorId: monitorId,
                status: status,
                responseTime: responseTime,
                statusCode: statusCode,
                checkedAt: checkedAt,
                errorMessage: errorMessage,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String monitorId,
                required String status,
                required int responseTime,
                required int statusCode,
                required String checkedAt,
                Value<String?> errorMessage = const Value.absent(),
              }) => CachedChecksCompanion.insert(
                id: id,
                monitorId: monitorId,
                status: status,
                responseTime: responseTime,
                statusCode: statusCode,
                checkedAt: checkedAt,
                errorMessage: errorMessage,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedChecksTable, CachedCheck>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedChecksTable,
                    CachedCheck
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedChecksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedChecksTable,
      CachedCheck,
      $$CachedChecksTableFilterComposer,
      $$CachedChecksTableOrderingComposer,
      $$CachedChecksTableAnnotationComposer,
      $$CachedChecksTableCreateCompanionBuilder,
      $$CachedChecksTableUpdateCompanionBuilder,
      (
        CachedCheck,
        BaseReferences<_$AppDatabase, $CachedChecksTable, CachedCheck>,
      ),
      CachedCheck,
      PrefetchHooks Function()
    >;
typedef $$CacheMetaTableCreateCompanionBuilder = CacheMetaCompanion Function({
  required String key,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$CacheMetaTableUpdateCompanionBuilder = CacheMetaCompanion Function({
  Value<String> key,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$CacheMetaTableFilterComposer
    extends Composer<_$AppDatabase, $CacheMetaTable> {
  $$CacheMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CacheMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $CacheMetaTable> {
  $$CacheMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CacheMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $CacheMetaTable> {
  $$CacheMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CacheMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CacheMetaTable,
          CacheMetaData,
          $$CacheMetaTableFilterComposer,
          $$CacheMetaTableOrderingComposer,
          $$CacheMetaTableAnnotationComposer,
          $$CacheMetaTableCreateCompanionBuilder,
          $$CacheMetaTableUpdateCompanionBuilder,
          (
            CacheMetaData,
            BaseReferences<_$AppDatabase, $CacheMetaTable, CacheMetaData>,
          ),
          CacheMetaData,
          PrefetchHooks Function()
        > {
  $$CacheMetaTableTableManager(_$AppDatabase db, $CacheMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CacheMetaCompanion(
                key: key,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CacheMetaCompanion.insert(
                key: key,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CacheMetaTable, CacheMetaData>(table),
                  BaseReferences<_$AppDatabase, $CacheMetaTable, CacheMetaData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CacheMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CacheMetaTable,
      CacheMetaData,
      $$CacheMetaTableFilterComposer,
      $$CacheMetaTableOrderingComposer,
      $$CacheMetaTableAnnotationComposer,
      $$CacheMetaTableCreateCompanionBuilder,
      $$CacheMetaTableUpdateCompanionBuilder,
      (
        CacheMetaData,
        BaseReferences<_$AppDatabase, $CacheMetaTable, CacheMetaData>,
      ),
      CacheMetaData,
      PrefetchHooks Function()
    >;
typedef $$CachedIncidentDetailsTableCreateCompanionBuilder =
    CachedIncidentDetailsCompanion Function({
      required String incidentId,
      required String updatesJson,
      required DateTime syncedAt,
      Value<int> rowid,
    });
typedef $$CachedIncidentDetailsTableUpdateCompanionBuilder =
    CachedIncidentDetailsCompanion Function({
      Value<String> incidentId,
      Value<String> updatesJson,
      Value<DateTime> syncedAt,
      Value<int> rowid,
    });

class $$CachedIncidentDetailsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedIncidentDetailsTable> {
  $$CachedIncidentDetailsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get incidentId => $composableBuilder(
    column: $table.incidentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatesJson => $composableBuilder(
    column: $table.updatesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedIncidentDetailsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedIncidentDetailsTable> {
  $$CachedIncidentDetailsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get incidentId => $composableBuilder(
    column: $table.incidentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatesJson => $composableBuilder(
    column: $table.updatesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedIncidentDetailsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedIncidentDetailsTable> {
  $$CachedIncidentDetailsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get incidentId => $composableBuilder(
    column: $table.incidentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatesJson => $composableBuilder(
    column: $table.updatesJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$CachedIncidentDetailsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedIncidentDetailsTable,
          CachedIncidentDetail,
          $$CachedIncidentDetailsTableFilterComposer,
          $$CachedIncidentDetailsTableOrderingComposer,
          $$CachedIncidentDetailsTableAnnotationComposer,
          $$CachedIncidentDetailsTableCreateCompanionBuilder,
          $$CachedIncidentDetailsTableUpdateCompanionBuilder,
          (
            CachedIncidentDetail,
            BaseReferences<
              _$AppDatabase,
              $CachedIncidentDetailsTable,
              CachedIncidentDetail
            >,
          ),
          CachedIncidentDetail,
          PrefetchHooks Function()
        > {
  $$CachedIncidentDetailsTableTableManager(
    _$AppDatabase db,
    $CachedIncidentDetailsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedIncidentDetailsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CachedIncidentDetailsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedIncidentDetailsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> incidentId = const Value.absent(),
                Value<String> updatesJson = const Value.absent(),
                Value<DateTime> syncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedIncidentDetailsCompanion(
                incidentId: incidentId,
                updatesJson: updatesJson,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String incidentId,
                required String updatesJson,
                required DateTime syncedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedIncidentDetailsCompanion.insert(
                incidentId: incidentId,
                updatesJson: updatesJson,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $CachedIncidentDetailsTable,
                    CachedIncidentDetail
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedIncidentDetailsTable,
                    CachedIncidentDetail
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedIncidentDetailsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedIncidentDetailsTable,
      CachedIncidentDetail,
      $$CachedIncidentDetailsTableFilterComposer,
      $$CachedIncidentDetailsTableOrderingComposer,
      $$CachedIncidentDetailsTableAnnotationComposer,
      $$CachedIncidentDetailsTableCreateCompanionBuilder,
      $$CachedIncidentDetailsTableUpdateCompanionBuilder,
      (
        CachedIncidentDetail,
        BaseReferences<
          _$AppDatabase,
          $CachedIncidentDetailsTable,
          CachedIncidentDetail
        >,
      ),
      CachedIncidentDetail,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedMonitorsTableTableManager get cachedMonitors =>
      $$CachedMonitorsTableTableManager(_db, _db.cachedMonitors);
  $$CachedIncidentsTableTableManager get cachedIncidents =>
      $$CachedIncidentsTableTableManager(_db, _db.cachedIncidents);
  $$CachedChecksTableTableManager get cachedChecks =>
      $$CachedChecksTableTableManager(_db, _db.cachedChecks);
  $$CacheMetaTableTableManager get cacheMeta =>
      $$CacheMetaTableTableManager(_db, _db.cacheMeta);
  $$CachedIncidentDetailsTableTableManager get cachedIncidentDetails =>
      $$CachedIncidentDetailsTableTableManager(_db, _db.cachedIncidentDetails);
}
