import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/widgets/widget_snapshot.dart';
import 'package:uptrack_mobile/widgets/widget_store.dart';

import 'widget_test_support.dart';

/// R5 selection: resolving the displayed incident moves the widget to the next
/// eligible open incident, and only a genuinely empty set clears it.
///
/// The regression this pins: the resolve path handed the collapse function a
/// resolved snapshot, which always decided `clear`, so one incident resolving
/// blanked a home screen that still had another open incident on it.
void main() {
  PushMessage pushFor(String incidentId) =>
      PushMessage.fromMap(<Object?, Object?>{'incident_id': incidentId})!;

  /// Refresher over a fixed row set.
  WidgetRefresher refresherOver(
    FakeWidgetStore store,
    List<IncidentSnapshot> rows,
  ) => WidgetRefresher(store: store, loadSnapshots: () async => rows);

  group('selectSnapshot', () {
    test('skips resolved rows and prefers the newest open one', () {
      final WidgetSnapshot? picked = WidgetRefresher.selectSnapshot(
        <WidgetIncidentCandidate>[
          widgetCandidate('a', insertedAt: '2026-09-27T09:00:00Z'),
          widgetCandidate(
            'b',
            insertedAt: '2026-09-27T11:00:00Z',
            status: 'resolved',
            resolvedAt: '2026-09-27T12:00:00Z',
          ),
          widgetCandidate('c', insertedAt: '2026-09-27T10:00:00Z'),
        ],
      );
      expect(picked!.incidentId, 'c');
    });

    test('treats a status-only resolution as ineligible', () {
      final WidgetSnapshot? picked = WidgetRefresher.selectSnapshot(
        <WidgetIncidentCandidate>[
          widgetCandidate('b', status: 'resolved'),
          widgetCandidate('c'),
        ],
      );
      expect(picked!.incidentId, 'c');
    });

    test('honours a preferred id while it is still open', () {
      final WidgetSnapshot? picked = WidgetRefresher.selectSnapshot(
        <WidgetIncidentCandidate>[
          widgetCandidate('newer', insertedAt: '2026-09-27T11:00:00Z'),
          widgetCandidate('named', insertedAt: '2026-09-27T09:00:00Z'),
        ],
        preferIncidentId: 'named',
      );
      expect(picked!.incidentId, 'named');
    });

    test('ignores a preferred id that has resolved', () {
      final WidgetSnapshot? picked = WidgetRefresher.selectSnapshot(
        <WidgetIncidentCandidate>[
          widgetCandidate('named', status: 'resolved'),
          widgetCandidate('other'),
        ],
        preferIncidentId: 'named',
      );
      expect(picked!.incidentId, 'other');
    });

    test('is null only when nothing is eligible', () {
      expect(
        WidgetRefresher.selectSnapshot(<WidgetIncidentCandidate>[
          widgetCandidate('a', status: 'resolved'),
        ]),
        isNull,
      );
      expect(
        WidgetRefresher.selectSnapshot(<WidgetIncidentCandidate>[]),
        isNull,
      );
    });

    test('carries each candidate sync stamp into the snapshot', () {
      final DateTime at = DateTime.utc(2026, 10, 4, 12);
      final WidgetSnapshot? picked = WidgetRefresher.selectSnapshot(
        <WidgetIncidentCandidate>[widgetCandidate('a', syncedAt: at)],
      );
      expect(
        picked!.updatedAt?.millisecondsSinceEpoch,
        at.millisecondsSinceEpoch,
      );
    });
  });

  group('resolving the displayed incident', () {
    test('a push for a resolved incident selects the next open one', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      // inc-1 is the newest and is what the widget shows.
      await refresherOver(store, <IncidentSnapshot>[
        widgetRow('inc-1', insertedAt: '2026-09-27T11:00:00Z'),
      ]).applySnapshot(WidgetSnapshot.fromCache(widgetRow('inc-1')));
      expect(store.values[WidgetDataKeys.incidentId], 'inc-1');

      // The authoritative sync resolves inc-1; the push announces it.
      final WidgetUpdateAction action = await refresherOver(
        store,
        <IncidentSnapshot>[
          widgetRow(
            'inc-1',
            status: 'resolved',
            resolvedAt: '2026-09-27T12:00:00Z',
            insertedAt: '2026-09-27T11:00:00Z',
          ),
          widgetRow('inc-2', insertedAt: '2026-09-27T09:00:00Z'),
        ],
      ).applyPush(pushFor('inc-1'));

      expect(action, WidgetUpdateAction.replace);
      expect(
        store.values[WidgetDataKeys.incidentId],
        'inc-2',
        reason: 'another open incident exists, so the widget must not blank',
      );
    });

    test('a cache refresh after a resolve selects the next open one', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      await refresherOver(store, <IncidentSnapshot>[
        widgetRow('inc-1', insertedAt: '2026-09-27T11:00:00Z'),
      ]).applySnapshot(WidgetSnapshot.fromCache(widgetRow('inc-1')));

      final WidgetUpdateAction action = await refresherOver(
        store,
        <IncidentSnapshot>[
          widgetRow(
            'inc-1',
            status: 'resolved',
            resolvedAt: '2026-09-27T12:00:00Z',
            insertedAt: '2026-09-27T11:00:00Z',
          ),
          widgetRow('inc-2', insertedAt: '2026-09-27T09:00:00Z'),
        ],
      ).refresh();

      expect(action, WidgetUpdateAction.replace);
      expect(store.values[WidgetDataKeys.incidentId], 'inc-2');
    });

    test('a true empty clears the widget', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      await refresherOver(store, <IncidentSnapshot>[
        widgetRow('inc-1'),
      ]).refresh();
      expect(store.values[WidgetDataKeys.incidentId], 'inc-1');

      // `loadEnumeratesAll` is the explicit claim that this loader saw the whole
      // feed. Without it the rows below prove only that these two resolved, which
      // is not enough to blank the widget (see widget_push_reconcile_test).
      final WidgetUpdateAction action = await WidgetRefresher(
        store: store,
        loadEnumeratesAll: true,
        loadSnapshots: () async => <IncidentSnapshot>[
          widgetRow('inc-1', status: 'resolved'),
          widgetRow('inc-2', status: 'resolved', resolvedAt: 'x'),
        ],
      ).refresh();

      expect(action, WidgetUpdateAction.clear);
      for (final String key in WidgetDataKeys.all) {
        expect(store.values.containsKey(key), isFalse);
      }
    });

    test(
      'a push whose incident is unknown leaves the shown one alone',
      () async {
        final FakeWidgetStore store = FakeWidgetStore();
        final WidgetRefresher refresher = refresherOver(
          store,
          <IncidentSnapshot>[widgetRow('inc-1')],
        );
        await refresher.applySnapshot(
          WidgetSnapshot.fromCache(widgetRow('inc-1')),
        );

        final WidgetUpdateAction action = await refresher.applyPush(
          pushFor('inc-not-cached'),
        );

        expect(action, WidgetUpdateAction.noop);
        expect(
          store.values[WidgetDataKeys.incidentId],
          'inc-1',
          reason: 'an unknown id must not blank the widget',
        );
        expect(
          store.values[WidgetDataKeys.pendingIncidentId],
          'inc-not-cached',
        );
      },
    );
  });
}
