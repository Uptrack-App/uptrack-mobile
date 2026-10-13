import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/push/fcm_data.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/push/push_service.dart';
import 'package:uptrack_mobile/widgets/widget_snapshot.dart';
import 'package:uptrack_mobile/widgets/widget_store.dart';

import 'widget_test_support.dart';

PushMessage pushFor(String incidentId) =>
    PushMessage.fromMap(<Object?, Object?>{'incident_id': incidentId})!;

/// Records foreground displays; the widget refresher must never stop the alert.
class RecordingNotifier implements LocalNotifier {
  PushMessage? shown;

  @override
  Future<void> initialize({
    required void Function(PushMessage message) onTap,
  }) async {}

  @override
  Future<void> showForeground(PushMessage message) async {
    shown = message;
  }

  @override
  Future<PushMessage?> initialNotification() async => null;
}

/// Writes [snapshot] into [store] as plain key writes, with no collapse rules.
///
/// This is the state an *older* build could leave behind, not a state current
/// code can produce: R5 made selection skip an incident that is resolved by
/// `status` alone ([WidgetIncidentCandidate.isEligible]), while the
/// implementation it replaced filtered on `resolved_at` only. A device upgraded
/// from that build can therefore still have `status: 'resolved'` sitting in
/// widget storage, and a push for that incident has to reconcile rather than
/// leave a dead incident on the home screen.
Future<void> seedStored(FakeWidgetStore store, WidgetSnapshot snapshot) async {
  for (final MapEntry<String, Object?> entry
      in snapshot.toWidgetData().entries) {
    final Object? value = entry.value;
    if (value is bool) {
      await store.save<bool>(entry.key, value);
    } else {
      await store.save<String>(entry.key, value?.toString());
    }
  }
  await store.refresh();
}

/// The stored (status-only) resolved copy of incident `inc-a`.
WidgetSnapshot resolvedA() => WidgetSnapshot(
  incidentId: 'inc-a',
  monitorId: 'mon-inc-a',
  monitorName: 'Monitor inc-a',
  status: WidgetSnapshot.resolvedStatus,
  startedAt: '2026-10-04T09:00:00Z',
  updatedAt: DateTime.utc(2026, 10, 4, 11),
);

/// The stored ongoing copy of incident `inc-a`.
WidgetSnapshot openA() => WidgetSnapshot(
  incidentId: 'inc-a',
  monitorId: 'mon-inc-a',
  monitorName: 'Monitor inc-a',
  status: 'ongoing',
  startedAt: '2026-10-04T09:00:00Z',
  updatedAt: DateTime.utc(2026, 10, 4, 11),
);

/// The stored ongoing copy of incident `inc-b`: the state a partial cache must
/// not be able to erase.
WidgetSnapshot openB() => WidgetSnapshot(
  incidentId: 'inc-b',
  monitorId: 'mon-inc-b',
  monitorName: 'Monitor inc-b',
  status: 'ongoing',
  startedAt: '2026-10-04T08:00:00Z',
  updatedAt: DateTime.utc(2026, 10, 4, 10),
);

/// R5 push reconciliation: a resolution for an incident the latest full cache no
/// longer carries must reconcile what is open now — the next eligible incident,
/// or a clear when the cache authoritatively has none — instead of parking an id
/// that can never reconcile.
///
/// The hold being fixed: `applyPush` found the pushed incident absent, merged the
/// stored copy, and when that stored copy was resolved it fell through to parking
/// `pendingIncidentId` and returning. The resolved incident therefore stayed on the
/// home screen, and the parked id was a lie: the row that would have named it is
/// gone, so nothing would ever reconcile it.
///
/// Every cache state below is produced through the real Drift cache and read back
/// through `WidgetRefresher.fromCache`, so "authoritative empty", "never synced" and
/// "partial" are separated by the cache's own rows and `cache_meta` rather than by a
/// flag a test could get wrong.
void main() {
  // Drift persists DateTime at second precision, so fixtures are whole seconds.
  final DateTime syncedAt = DateTime.utc(2026, 10, 4, 12);

  late AppDatabase db;
  late CacheRepository cache;
  late bool closed;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    cache = CacheRepository(db);
    closed = false;
  });

  tearDown(() async {
    if (!closed) {
      await db.close();
    }
  });

  /// Closes the cache's database so the next real read genuinely fails.
  ///
  /// The connection is opened first: closing a database that was never opened
  /// closes nothing, and the read after that would quietly succeed on an empty
  /// cache instead of failing — which would make this the uninitialized case,
  /// not the failed-read case it claims to be.
  Future<void> breakTheCache() async {
    await cache.getIncidents();
    await db.close();
    closed = true;
  }

  /// Completes a list sync carrying [incidents] — the only cache write that
  /// makes an empty list authoritative.
  Future<void> sync(List<IncidentSnapshot> incidents) => cache.saveIncidents(
    incidents,
    session: cache.sessionEpoch,
    revision: cache.incidentRevision,
    syncedAt: syncedAt,
  );

  /// Writes one authoritative row the way a detail read or an action sync does:
  /// through `upsertIncident`, which stamps the row but never the collection.
  Future<void> upsertRow(IncidentSnapshot row, {required DateTime at}) =>
      cache.upsertIncident(row, session: cache.sessionEpoch, syncedAt: at);

  group('push resolves the stored incident the cache no longer has', () {
    test('selects the open incident the cache still knows', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      await seedStored(store, resolvedA());
      await sync(<IncidentSnapshot>[widgetRow('inc-b')]);

      final WidgetUpdateAction action = await WidgetRefresher.fromCache(
        cache,
        store: store,
        gate: WidgetWriteGate(),
      ).applyPush(pushFor('inc-a'));

      expect(action, WidgetUpdateAction.replace);
      expect(
        store.values[WidgetDataKeys.incidentId],
        'inc-b',
        reason:
            'the resolved incident is gone; the ongoing one takes the widget',
      );
      expect(store.values[WidgetDataKeys.status], 'ongoing');
      expect(
        // `isAtSameMomentAs`, not `==`: drift hands the row back in local time,
        // which is the same instant as the UTC fixture but a different flag.
        (DateTime.parse(store.values[WidgetDataKeys.updatedAt]! as String))
            .isAtSameMomentAs(syncedAt),
        isTrue,
        reason: 'the replacement carries the sync instant of the data written',
      );
      expect(
        store.values.containsKey(WidgetDataKeys.pendingIncidentId),
        isFalse,
        reason: 'a reconciled resolution must leave no pending id behind',
      );
    });

    test('clears when a completed sync reported nothing open', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      await seedStored(store, resolvedA());
      await sync(<IncidentSnapshot>[]);

      final WidgetUpdateAction action = await WidgetRefresher.fromCache(
        cache,
        store: store,
        gate: WidgetWriteGate(),
      ).applyPush(pushFor('inc-a'));

      expect(action, WidgetUpdateAction.clear);
      for (final String key in WidgetDataKeys.all) {
        expect(
          store.values.containsKey(key),
          isFalse,
          reason: '$key survived an authoritative all-clear',
        );
      }
    });

    test('writes nothing when the cache has never synced', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      await seedStored(store, resolvedA());
      // No list sync ever ran: an empty cache here is "unknown", not "nothing
      // open", and must not blank the home screen.
      final int refreshesBefore = store.refreshes;

      final WidgetUpdateAction action = await WidgetRefresher.fromCache(
        cache,
        store: store,
        gate: WidgetWriteGate(),
      ).applyPush(pushFor('inc-a'));

      expect(action, WidgetUpdateAction.noop);
      expect(
        store.values[WidgetDataKeys.incidentId],
        'inc-a',
        reason: 'an uninitialized cache may not claim an all-clear',
      );
      expect(
        store.values[WidgetDataKeys.status],
        WidgetSnapshot.resolvedStatus,
      );
      expect(store.refreshes, refreshesBefore);
      expect(
        store.values.containsKey(WidgetDataKeys.pendingIncidentId),
        isFalse,
        reason: 'the row that would name this id no longer exists',
      );
    });

    test('preserves the stored incident when the cache read fails', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      await seedStored(store, resolvedA());
      await breakTheCache();
      final int refreshesBefore = store.refreshes;

      final WidgetUpdateAction action = await WidgetRefresher.fromCache(
        cache,
        store: store,
        gate: WidgetWriteGate(),
      ).applyPush(pushFor('inc-a'));

      expect(action, WidgetUpdateAction.noop);
      expect(store.values[WidgetDataKeys.incidentId], 'inc-a');
      expect(store.refreshes, refreshesBefore);
      expect(
        store.values.containsKey(WidgetDataKeys.pendingIncidentId),
        isFalse,
      );
    });

    test('a reconcile in flight across logout writes nothing', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetWriteGate gate = WidgetWriteGate();
      await seedStored(store, resolvedA());
      await sync(<IncidentSnapshot>[widgetRow('inc-b')]);

      // The push is inside its cache read when logout advances the epoch, so the
      // reconcile it was about to perform must be refused by the same gate every
      // other write uses — not written, and not reported as applied.
      final Future<WidgetUpdateAction> push = WidgetRefresher.fromCache(
        cache,
        store: store,
        gate: gate,
      ).applyPush(pushFor('inc-a'));
      await clearWidgetData(store, gate);

      expect(await push, WidgetUpdateAction.noop);
      for (final String key in WidgetDataKeys.all) {
        expect(
          store.values.containsKey(key),
          isFalse,
          reason: '$key survived logout via the reconcile path',
        );
      }
    });

    test(
      'still parks a push for an incident that is not the shown one',
      () async {
        final FakeWidgetStore store = FakeWidgetStore();
        await seedStored(store, openA());
        await sync(<IncidentSnapshot>[]);

        final WidgetUpdateAction action = await WidgetRefresher.fromCache(
          cache,
          store: store,
          gate: WidgetWriteGate(),
        ).applyPush(pushFor('inc-new'));

        expect(action, WidgetUpdateAction.noop);
        expect(
          store.values[WidgetDataKeys.pendingIncidentId],
          'inc-new',
          reason:
              'inc-a is not resolved, so its absence from the feed proves '
              'nothing; a new incident still waits for the next sync',
        );
        expect(store.values[WidgetDataKeys.incidentId], 'inc-a');
      },
    );
  });

  group('a partial cache is not a complete feed', () {
    // The widget shows inc-b. The cache then learns about exactly one *other*
    // incident, resolved, through a path that never enumerates the collection.
    // "Nothing eligible in what I happen to know" is not "nothing open".

    test('a resolved-only upsert without list meta never clears', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetWriteGate gate = WidgetWriteGate();
      await seedStored(store, openB());
      await upsertRow(
        widgetRow(
          'inc-a',
          status: WidgetSnapshot.resolvedStatus,
          resolvedAt: '2026-10-04T13:00:00Z',
        ),
        at: DateTime.utc(2026, 10, 4, 13),
      );

      final WidgetUpdateAction action = await WidgetRefresher.fromCache(
        cache,
        store: store,
        gate: gate,
      ).refresh();

      expect(action, WidgetUpdateAction.noop);
      expect(
        store.values[WidgetDataKeys.incidentId],
        'inc-b',
        reason:
            'a resolved row that was upserted alone proves nothing about the '
            'feed, so the widget must not claim "no ongoing incidents"',
      );
      expect(
        store.refreshes,
        1,
        reason: 'nothing was written, nothing redrawn',
      );
    });

    test(
      'the same partial state does not clear through a push either',
      () async {
        final FakeWidgetStore store = FakeWidgetStore();
        final WidgetWriteGate gate = WidgetWriteGate();
        await seedStored(store, openB());
        await upsertRow(
          widgetRow(
            'inc-a',
            status: WidgetSnapshot.resolvedStatus,
            resolvedAt: '2026-10-04T13:00:00Z',
          ),
          at: DateTime.utc(2026, 10, 4, 13),
        );

        final WidgetUpdateAction action = await WidgetRefresher.fromCache(
          cache,
          store: store,
          gate: gate,
        ).applyPush(pushFor('inc-a'));

        expect(action, WidgetUpdateAction.noop);
        expect(store.values[WidgetDataKeys.incidentId], 'inc-b');
        expect(
          store.values.containsKey(WidgetDataKeys.pendingIncidentId),
          isFalse,
        );
      },
    );

    test('a completed empty sync does clear', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetWriteGate gate = WidgetWriteGate();
      await seedStored(store, openB());
      await upsertRow(
        widgetRow(
          'inc-a',
          status: WidgetSnapshot.resolvedStatus,
          resolvedAt: '2026-10-04T13:00:00Z',
        ),
        at: DateTime.utc(2026, 10, 4, 13),
      );
      // A real list sync now completes with an empty list: the collection's
      // `cache_meta` row is written, and only then is "nothing open" a fact.
      await sync(<IncidentSnapshot>[]);

      final WidgetUpdateAction action = await WidgetRefresher.fromCache(
        cache,
        store: store,
        gate: gate,
      ).refresh();

      expect(action, WidgetUpdateAction.clear);
      for (final String key in WidgetDataKeys.all) {
        expect(
          store.values.containsKey(key),
          isFalse,
          reason: '$key survived an authoritative all-clear',
        );
      }
    });

    test('a partial ongoing row is displayed without completeness', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetWriteGate gate = WidgetWriteGate();
      await seedStored(store, openB());
      final DateTime actionAt = DateTime.utc(2026, 10, 4, 13, 30);
      await upsertRow(widgetRow('inc-a'), at: actionAt);

      final WidgetUpdateAction action = await WidgetRefresher.fromCache(
        cache,
        store: store,
        gate: gate,
      ).refresh();

      expect(action, WidgetUpdateAction.replace);
      expect(
        store.values[WidgetDataKeys.incidentId],
        'inc-a',
        reason: 'showing a real open incident needs no proof of completeness',
      );
      expect(
        (DateTime.parse(store.values[WidgetDataKeys.updatedAt]! as String))
            .isAtSameMomentAs(actionAt),
        isTrue,
        reason: 'freshness comes from the row\'s own write, not from coverage',
      );
    });

    test(
      'an explicit completeness flag never fabricates a freshness stamp',
      () async {
        // The legacy row-list seam: completeness may be declared explicitly, but a
        // sync instant may not be invented to express it.
        final FakeWidgetStore store = FakeWidgetStore();
        final WidgetRefresher declared = WidgetRefresher(
          store: store,
          loadEnumeratesAll: true,
          loadSnapshots: () async => <IncidentSnapshot>[widgetRow('inc-a')],
        );

        expect(await declared.refresh(), WidgetUpdateAction.replace);
        expect(store.values[WidgetDataKeys.incidentId], 'inc-a');
        expect(
          store.values[WidgetDataKeys.updatedAt],
          '',
          reason: 'completeness is a coverage claim, never a freshness time',
        );
      },
    );

    test(
      'a declared-complete resolved set is the row-list all-clear',
      () async {
        final FakeWidgetStore store = FakeWidgetStore();
        await seedStored(store, openB());

        expect(
          await WidgetRefresher(
            store: store,
            loadEnumeratesAll: true,
            loadSnapshots: () async => <IncidentSnapshot>[
              widgetRow('inc-a', status: 'resolved', resolvedAt: 'x'),
            ],
          ).refresh(),
          WidgetUpdateAction.clear,
        );
        expect(store.values.containsKey(WidgetDataKeys.incidentId), isFalse);
      },
    );
  });

  group('the foreground push path survives an unreadable cache', () {
    test('shows the alert and keeps the stored incident', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      await seedStored(store, resolvedA());
      await breakTheCache();
      final RecordingNotifier notifier = RecordingNotifier();

      final PushMessage? message = await FcmDataHandler(
        notifier: notifier,
        refresher: WidgetRefresher.fromCache(
          cache,
          store: store,
          gate: WidgetWriteGate(),
        ),
      ).handle(<Object?, Object?>{'incident_id': 'inc-a'});

      expect(message, isNotNull);
      expect(
        notifier.shown?.incidentId,
        'inc-a',
        reason:
            'a cache error is widget hygiene, not a reason to lose the alert',
      );
      expect(store.values[WidgetDataKeys.incidentId], 'inc-a');
    });
  });

  group('unknown is never an all-clear', () {
    test(
      'refresh keeps a stored incident when the cache never synced',
      () async {
        final FakeWidgetStore store = FakeWidgetStore();
        await seedStored(store, openA());
        final int refreshesBefore = store.refreshes;

        final WidgetUpdateAction action = await WidgetRefresher.fromCache(
          cache,
          store: store,
          gate: WidgetWriteGate(),
        ).refresh();

        expect(action, WidgetUpdateAction.noop);
        expect(store.values[WidgetDataKeys.incidentId], 'inc-a');
        expect(
          store.refreshes,
          refreshesBefore,
          reason: 'nothing was written, so nothing needs redrawing',
        );
      },
    );

    test('refresh clears once a sync has reported an empty list', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetWriteGate gate = WidgetWriteGate();
      await WidgetRefresher.fromCache(
        cache,
        store: store,
        gate: gate,
      ).applySnapshot(openA());
      await sync(<IncidentSnapshot>[]);

      final WidgetUpdateAction action = await WidgetRefresher.fromCache(
        cache,
        store: store,
        gate: gate,
      ).refresh();

      expect(action, WidgetUpdateAction.clear);
      for (final String key in WidgetDataKeys.all) {
        expect(store.values.containsKey(key), isFalse);
      }
    });

    test('refresh reports a failed read and still clears nothing', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      await seedStored(store, openA());
      await breakTheCache();

      await expectLater(
        WidgetRefresher.fromCache(
          cache,
          store: store,
          gate: WidgetWriteGate(),
        ).refresh(),
        throwsA(isA<StateError>()),
      );
      expect(
        store.values[WidgetDataKeys.incidentId],
        'inc-a',
        reason: 'a reported failure is not permission to blank the widget',
      );
    });
  });

  group('WidgetCandidateLoad decides what may clear', () {
    final DateTime at = DateTime.utc(2026, 10, 4, 12);

    test('an empty load with no sync instant is unknown', () {
      const WidgetCandidateLoad load = WidgetCandidateLoad(
        candidates: <WidgetIncidentCandidate>[],
      );
      expect(load.isComplete, isFalse);
      expect(load.isKnownAllClear, isFalse);
    });

    test('an empty load after a completed sync is an all-clear', () {
      final WidgetCandidateLoad load = WidgetCandidateLoad(
        candidates: <WidgetIncidentCandidate>[],
        syncedAt: at,
      );
      expect(load.isComplete, isTrue);
      expect(load.hasOpen, isFalse);
      expect(load.isKnownAllClear, isTrue);
    });

    test('an explicitly complete empty load is an all-clear', () {
      const WidgetCandidateLoad load = WidgetCandidateLoad(
        candidates: <WidgetIncidentCandidate>[],
        enumeratesAll: true,
      );
      expect(load.isComplete, isTrue);
      expect(load.isKnownAllClear, isTrue);
      expect(
        load.syncedAt,
        isNull,
        reason: 'a completeness claim must not invent a freshness time',
      );
    });

    test('resolved rows without completeness are not an all-clear', () {
      // The partial-cache hold: rows fed by a detail read or an action upsert
      // say nothing about the incidents that were never written, so a
      // resolved-only set must not blank the widget.
      final WidgetCandidateLoad load = WidgetCandidateLoad(
        candidates: <WidgetIncidentCandidate>[
          widgetCandidate('a', status: 'resolved', syncedAt: at),
          widgetCandidate(
            'b',
            resolvedAt: '2026-10-04T13:00:00Z',
            syncedAt: at,
          ),
        ],
      );
      expect(load.isComplete, isFalse);
      expect(load.hasOpen, isFalse);
      expect(load.isKnownAllClear, isFalse);
    });

    test('rows that all report resolved clear only with completeness', () {
      final WidgetCandidateLoad load = WidgetCandidateLoad(
        candidates: <WidgetIncidentCandidate>[
          widgetCandidate('a', status: 'resolved'),
          widgetCandidate('b', resolvedAt: '2026-10-04T13:00:00Z'),
        ],
        syncedAt: at,
      );
      expect(load.isKnownAllClear, isTrue);
    });

    test('a per-row stamp never confers completeness', () {
      final WidgetCandidateLoad load = WidgetCandidateLoad(
        candidates: <WidgetIncidentCandidate>[
          widgetCandidate('a', syncedAt: at),
        ],
      );
      expect(load.isComplete, isFalse);
      expect(load.hasOpen, isTrue);
      expect(load.isKnownAllClear, isFalse);
    });

    test('one open row is never an all-clear', () {
      final WidgetCandidateLoad load = WidgetCandidateLoad(
        candidates: <WidgetIncidentCandidate>[widgetCandidate('b')],
        syncedAt: at,
      );
      expect(load.hasOpen, isTrue);
      expect(load.isKnownAllClear, isFalse);
    });
  });
}
