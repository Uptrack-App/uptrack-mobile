import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/widgets/widget_snapshot.dart';
import 'package:uptrack_mobile/widgets/widget_store.dart';

/// In-memory [WidgetDataStore] recording saves and refresh calls.
class FakeStore implements WidgetDataStore {
  final Map<String, Object?> values = <String, Object?>{};
  int refreshes = 0;

  @override
  Future<bool?> save<T>(String key, T? data) async {
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

IncidentSnapshot row(
  String id, {
  String status = 'ongoing',
  String? resolvedAt,
  String insertedAt = '2026-09-27T10:00:00Z',
}) => IncidentSnapshot(
  id: id,
  monitorId: 'mon-$id',
  monitorName: 'Monitor $id',
  status: status,
  startedAt: '2026-09-27T10:00:00Z',
  resolvedAt: resolvedAt,
  insertedAt: insertedAt,
);

PushMessage pushFor(String incidentId) =>
    PushMessage.fromMap(<Object?, Object?>{'incident_id': incidentId})!;

void main() {
  group('WidgetRefresher.refresh', () {
    test('writes the newest ongoing incident and refreshes', () async {
      final FakeStore store = FakeStore();
      final WidgetRefresher refresher = WidgetRefresher(
        store: store,
        loadSnapshots: () async => <IncidentSnapshot>[
          row('inc-1', insertedAt: '2026-09-27T09:00:00Z'),
          row('inc-2', insertedAt: '2026-09-27T11:00:00Z'),
        ],
      );
      final WidgetUpdateAction action = await refresher.refresh();
      expect(action, WidgetUpdateAction.replace);
      expect(store.values[WidgetDataKeys.incidentId], 'inc-2');
      expect(store.values[WidgetDataKeys.monitorName], 'Monitor inc-2');
      expect(store.values[WidgetDataKeys.status], 'ongoing');
      expect(store.refreshes, 1);
    });

    test('clears when every incident resolved', () async {
      final FakeStore store = FakeStore();
      final WidgetRefresher seed = WidgetRefresher(
        store: store,
        loadSnapshots: () async => <IncidentSnapshot>[row('inc-1')],
      );
      await seed.refresh();
      final int seeded = store.refreshes;
      // The loader declares it enumerated the feed; that claim, not the mere
      // presence of a resolved row, is what authorises the clear.
      final WidgetRefresher refresher = WidgetRefresher(
        store: store,
        loadEnumeratesAll: true,
        loadSnapshots: () async => <IncidentSnapshot>[
          row('inc-1', status: 'resolved', resolvedAt: '2026-09-27T12:00:00Z'),
        ],
      );
      final WidgetUpdateAction action = await refresher.refresh();
      expect(action, WidgetUpdateAction.clear);
      expect(store.values.containsKey(WidgetDataKeys.incidentId), isFalse);
      expect(store.refreshes, seeded + 1);
    });

    test('second refresh of the same incident updates', () async {
      final FakeStore store = FakeStore();
      final WidgetRefresher refresher = WidgetRefresher(
        store: store,
        loadSnapshots: () async => <IncidentSnapshot>[row('inc-1')],
      );
      expect(await refresher.refresh(), WidgetUpdateAction.replace);
      expect(await refresher.refresh(), WidgetUpdateAction.update);
    });
  });

  group('WidgetRefresher.applyPush', () {
    test('push for the stored incident updates in place', () async {
      final FakeStore store = FakeStore();
      final WidgetRefresher refresher = WidgetRefresher(
        store: store,
        loadSnapshots: () async => <IncidentSnapshot>[row('inc-1')],
      );
      await refresher.refresh();
      final int refreshes = store.refreshes;
      final WidgetUpdateAction action = await refresher.applyPush(
        pushFor('inc-1'),
      );
      expect(action, WidgetUpdateAction.update);
      expect(store.values[WidgetDataKeys.incidentId], 'inc-1');
      expect(store.refreshes, refreshes + 1);
    });

    test('push for a cached-but-different incident replaces', () async {
      final FakeStore store = FakeStore();
      final WidgetRefresher refresher = WidgetRefresher(
        store: store,
        loadSnapshots: () async => <IncidentSnapshot>[
          row('inc-1'),
          row('inc-2', insertedAt: '2026-09-27T11:00:00Z'),
        ],
      );
      await refresher.applySnapshot(WidgetSnapshot.fromCache(row('inc-1')));
      final WidgetUpdateAction action = await refresher.applyPush(
        pushFor('inc-2'),
      );
      expect(action, WidgetUpdateAction.replace);
      expect(store.values[WidgetDataKeys.incidentId], 'inc-2');
    });

    test('push for an unknown incident parks a pending id', () async {
      final FakeStore store = FakeStore();
      final WidgetRefresher refresher = WidgetRefresher(
        store: store,
        loadSnapshots: () async => <IncidentSnapshot>[],
      );
      final WidgetUpdateAction action = await refresher.applyPush(
        pushFor('inc-99'),
      );
      expect(action, WidgetUpdateAction.noop);
      expect(store.values[WidgetDataKeys.pendingIncidentId], 'inc-99');
      expect(store.refreshes, 1);
    });

    test('push without an incident id is a no-op', () async {
      final FakeStore store = FakeStore();
      final WidgetRefresher refresher = WidgetRefresher(
        store: store,
        loadSnapshots: () async => <IncidentSnapshot>[row('inc-1')],
      );
      final PushMessage bare = PushMessage.fromMap(<Object?, Object?>{
        'title': 'hi',
      })!;
      expect(await refresher.applyPush(bare), WidgetUpdateAction.noop);
      expect(store.refreshes, 0);
    });
  });

  group('pickTop', () {
    test('prefers newest ongoing; null when all resolved', () {
      expect(
        WidgetRefresher.pickTop(<IncidentSnapshot>[
          row('a', insertedAt: '2026-09-27T09:00:00Z'),
          row('b', insertedAt: '2026-09-27T11:00:00Z'),
        ])!.incidentId,
        'b',
      );
      expect(
        WidgetRefresher.pickTop(<IncidentSnapshot>[
          row('a', status: 'resolved', resolvedAt: '2026-09-27T12:00:00Z'),
        ]),
        isNull,
      );
      expect(WidgetRefresher.pickTop(<IncidentSnapshot>[]), isNull);
    });
  });

  group('clearWidgetData', () {
    test('removes every key and refreshes (R2.4 logout hygiene)', () async {
      final FakeStore store = FakeStore();
      final WidgetRefresher seed = WidgetRefresher(
        store: store,
        loadSnapshots: () async => <IncidentSnapshot>[row('inc-1')],
      );
      await seed.refresh();
      expect(store.values[WidgetDataKeys.incidentId], 'inc-1');

      await clearWidgetData(store);

      for (final String key in WidgetDataKeys.all) {
        expect(store.values.containsKey(key), isFalse);
      }
      expect(store.refreshes, 2);
    });
  });
}
