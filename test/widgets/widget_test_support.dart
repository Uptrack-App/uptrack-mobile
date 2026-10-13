import 'dart:async';

import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/widgets/widget_snapshot.dart';
import 'package:uptrack_mobile/widgets/widget_store.dart';

/// In-memory [WidgetDataStore] that can also be stalled mid-write.
///
/// Used by the R5 tests to prove ordering and session fencing, which needs a
/// store whose writes can be paused at a chosen key: without a pause, a
/// "late write after logout" race cannot be expressed deterministically.
class FakeWidgetStore implements WidgetDataStore {
  FakeWidgetStore();

  final Map<String, Object?> values = <String, Object?>{};
  final List<String> writes = <String>[];

  int refreshes = 0;

  /// When set, a save of this key blocks until [release] is called.
  String? blockOnSave;
  final Completer<void> _blocked = Completer<void>();
  final Completer<void> _reached = Completer<void>();

  /// Completes once a save of [blockOnSave] has been reached.
  Future<void> get blocked => _reached.future;

  /// Lets a blocked save continue.
  void release() {
    if (!_blocked.isCompleted) {
      _blocked.complete();
    }
  }

  @override
  Future<bool?> save<T>(String key, T? data) async {
    if (key == blockOnSave) {
      if (!_reached.isCompleted) {
        _reached.complete();
      }
      await _blocked.future;
    }
    writes.add(key);
    if (data == null) {
      values.remove(key);
    } else {
      values[key] = data as Object;
    }
    return true;
  }

  @override
  Future<T?> read<T>(String key) async {
    final Object? value = values[key];
    if (value is T) {
      return value;
    }
    return null;
  }

  @override
  Future<bool?> refresh() async {
    refreshes += 1;
    return true;
  }
}

/// Cached row fixture.
IncidentSnapshot widgetRow(
  String id, {
  String status = 'ongoing',
  String? resolvedAt,
  String insertedAt = '2026-09-27T10:00:00Z',
  String? monitorId,
}) => IncidentSnapshot(
  id: id,
  monitorId: monitorId ?? 'mon-$id',
  monitorName: 'Monitor $id',
  status: status,
  startedAt: '2026-09-27T10:00:00Z',
  resolvedAt: resolvedAt,
  insertedAt: insertedAt,
);

/// Candidate fixture with an explicit sync stamp.
WidgetIncidentCandidate widgetCandidate(
  String id, {
  String status = 'ongoing',
  String? resolvedAt,
  String insertedAt = '2026-09-27T10:00:00Z',
  DateTime? syncedAt,
}) => WidgetIncidentCandidate(
  row: widgetRow(
    id,
    status: status,
    resolvedAt: resolvedAt,
    insertedAt: insertedAt,
  ),
  syncedAt: syncedAt,
);
