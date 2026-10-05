import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/widgets/widget_snapshot.dart';
import 'package:uptrack_mobile/widgets/widget_store.dart';

import 'widget_test_support.dart';

/// R5 logout safety: the clear wins against any write that was already in
/// flight, and no write from an ended session can put account data back.
///
/// Each test injects its own [WidgetWriteGate] rather than relying on the
/// process-wide one, so the epoch arithmetic under test is the one written in
/// this test and the assertions cannot be satisfied by another test's history.
void main() {
  PushMessage pushFor(String incidentId) =>
      PushMessage.fromMap(<Object?, Object?>{'incident_id': incidentId})!;

  void expectNoAccountData(FakeWidgetStore store) {
    for (final String key in WidgetDataKeys.all) {
      expect(
        store.values.containsKey(key),
        isFalse,
        reason: '$key survived logout',
      );
    }
  }

  group('logout clears account data', () {
    test('removes every key and refreshes', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetWriteGate gate = WidgetWriteGate();
      await WidgetRefresher(
        store: store,
        gate: gate,
        loadSnapshots: () async => <IncidentSnapshot>[widgetRow('inc-1')],
      ).refresh();
      expect(store.values[WidgetDataKeys.incidentId], 'inc-1');

      await clearWidgetData(store, gate);

      expectNoAccountData(store);
      expect(store.refreshes, 2);
    });

    test('also drops a parked pending id', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetWriteGate gate = WidgetWriteGate();
      await WidgetRefresher(
        store: store,
        gate: gate,
        loadSnapshots: () async => <IncidentSnapshot>[],
      ).applyPush(pushFor('inc-new'));
      expect(store.values[WidgetDataKeys.pendingIncidentId], 'inc-new');

      await clearWidgetData(store, gate);

      expectNoAccountData(store);
    });
  });

  group('session fencing', () {
    test(
      'a refresh already writing when logout lands cannot repopulate',
      () async {
        final FakeWidgetStore store = FakeWidgetStore()
          ..blockOnSave = WidgetDataKeys.monitorName;
        final WidgetWriteGate gate = WidgetWriteGate();
        final WidgetRefresher refresher = WidgetRefresher(
          store: store,
          gate: gate,
          loadSnapshots: () async => <IncidentSnapshot>[widgetRow('inc-1')],
        );

        final Future<WidgetUpdateAction> writing = refresher.refresh();
        await store.blocked;

        // Logout runs while the write is mid-flight. `endSession` queues the
        // clear behind whatever is already running, so the partial write cannot
        // finish after it.
        final Future<void> logout = clearWidgetData(store, gate);
        store.release();
        await writing;
        await logout;

        expectNoAccountData(store);
      },
    );

    test('a load in flight across logout writes nothing at all', () async {
      final Completer<List<IncidentSnapshot>> rows =
          Completer<List<IncidentSnapshot>>();
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetWriteGate gate = WidgetWriteGate();
      final WidgetRefresher refresher = WidgetRefresher(
        store: store,
        gate: gate,
        // Simulates the authoritative dashboard sync that started while signed
        // in and only answered after logout.
        loadSnapshots: () => rows.future,
      );

      final Future<WidgetUpdateAction> syncing = refresher.refresh();
      await clearWidgetData(store, gate);
      rows.complete(<IncidentSnapshot>[widgetRow('inc-1')]);

      expect(
        await syncing,
        WidgetUpdateAction.noop,
        reason: 'a fenced write must not claim to have applied anything',
      );
      expectNoAccountData(store);
      expect(store.refreshes, 1, reason: 'only the logout refresh ran');
    });

    test('a push in flight across logout writes nothing', () async {
      final Completer<List<IncidentSnapshot>> rows =
          Completer<List<IncidentSnapshot>>();
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetWriteGate gate = WidgetWriteGate();
      final WidgetRefresher refresher = WidgetRefresher(
        store: store,
        gate: gate,
        loadSnapshots: () => rows.future,
      );

      final Future<WidgetUpdateAction> push = refresher.applyPush(
        pushFor('inc-1'),
      );
      await clearWidgetData(store, gate);
      rows.complete(<IncidentSnapshot>[widgetRow('inc-1')]);

      expect(await push, WidgetUpdateAction.noop);
      expectNoAccountData(store);
    });

    test('a new session may write again after the fence advanced', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetWriteGate gate = WidgetWriteGate();
      await clearWidgetData(store, gate);

      final WidgetUpdateAction action = await WidgetRefresher(
        store: store,
        gate: gate,
        loadSnapshots: () async => <IncidentSnapshot>[widgetRow('inc-9')],
      ).refresh();

      expect(action, WidgetUpdateAction.replace);
      expect(store.values[WidgetDataKeys.incidentId], 'inc-9');
    });

    test('the gate serializes overlapping writes in call order', () async {
      final List<String> order = <String>[];
      final WidgetWriteGate gate = WidgetWriteGate();
      final Completer<void> firstStarted = Completer<void>();
      final Completer<void> releaseFirst = Completer<void>();

      final Future<bool> first = gate.run(() async {
        order.add('first-start');
        firstStarted.complete();
        await releaseFirst.future;
        order.add('first-end');
      });
      final Future<bool> second = gate.run(() async {
        order.add('second');
      });

      await firstStarted.future;
      expect(order, <String>['first-start'], reason: 'second must wait');
      releaseFirst.complete();
      await Future.wait(<Future<bool>>[first, second]);

      expect(order, <String>['first-start', 'first-end', 'second']);
    });

    test('a failing write leaves the queue usable', () async {
      final WidgetWriteGate gate = WidgetWriteGate();

      await expectLater(
        gate.run(() async => throw StateError('channel down')),
        throwsStateError,
      );
      expect(gate.run(() async {}), completion(isTrue));
    });
  });

  group('sample/demo data never reaches widget storage', () {
    test('a demo fixture is refused and live data is untouched', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetWriteGate gate = WidgetWriteGate();
      await WidgetRefresher(
        store: store,
        gate: gate,
        loadSnapshots: () async => <IncidentSnapshot>[widgetRow('inc-1')],
      ).refresh();

      final WidgetUpdateAction action = await WidgetRefresher(
        store: store,
        gate: gate,
        loadSnapshots: () async => <IncidentSnapshot>[
          widgetRow('demo-incident', monitorId: 'demo-api'),
        ],
      ).refresh();

      expect(action, WidgetUpdateAction.noop);
      expect(
        store.values[WidgetDataKeys.incidentId],
        'inc-1',
        reason: 'a refused write must not clear or replace live data',
      );
      expect(
        store.refreshes,
        1,
        reason: 'a refused write changes nothing, so it must not refresh',
      );
    });

    test('the guard recognises the demo fixtures by id', () {
      expect(
        WidgetSampleGuard.isSampleSnapshot(
          WidgetSnapshot.fromCache(
            widgetRow('demo-incident', monitorId: 'mon-real'),
          ),
        ),
        isTrue,
      );
      expect(
        WidgetSampleGuard.isSampleSnapshot(
          WidgetSnapshot.fromCache(widgetRow('inc-1', monitorId: 'demo-api')),
        ),
        isTrue,
      );
      expect(
        WidgetSampleGuard.isSampleSnapshot(
          WidgetSnapshot.fromCache(widgetRow('inc-1')),
        ),
        isFalse,
      );
    });

    test('the gate is injectable for the later integration owner', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetRefresher refusingEverything = WidgetRefresher(
        store: store,
        gate: WidgetWriteGate(),
        loadSnapshots: () async => <IncidentSnapshot>[widgetRow('inc-1')],
        publishable: (WidgetSnapshot _) => false,
      );

      expect(await refusingEverything.refresh(), WidgetUpdateAction.noop);
      expect(store.values.containsKey(WidgetDataKeys.incidentId), isFalse);
    });
  });
}
