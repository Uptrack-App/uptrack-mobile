import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/widgets/widget_snapshot.dart';
import 'package:uptrack_mobile/widgets/widget_store.dart';

import 'widget_test_support.dart';

PushMessage pushFor(String incidentId) =>
    PushMessage.fromMap(<Object?, Object?>{'incident_id': incidentId})!;

/// R5 freshness provenance: the widget reports when its data was **actually**
/// fetched, and a missing stamp is reported as unknown rather than as now.
///
/// Driven through the real Drift cache on purpose. Asserting only that a
/// constructor does or does not stamp `DateTime.now()` would pass while the
/// store silently replaced the real timestamp downstream; the interesting
/// claims are that the cache's persisted sync instant survives the whole
/// pipeline and that re-reading the cache does not renew it.
void main() {
  late AppDatabase db;
  late CacheRepository cache;

  // Drift persists DateTime at second precision, so fixtures are whole seconds.
  final DateTime syncedAt = DateTime.utc(2026, 10, 4, 12, 0, 0);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    cache = CacheRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> saveIncident(IncidentSnapshot incident) => cache.saveIncidents(
    <IncidentSnapshot>[incident],
    session: cache.sessionEpoch,
    revision: cache.incidentRevision,
    syncedAt: syncedAt,
  );

  /// The instant the widget store actually holds for the freshness key.
  DateTime? storedStamp(FakeWidgetStore store) {
    final String? raw = store.values[WidgetDataKeys.updatedAt] as String?;
    expect(raw, isNotNull, reason: 'no freshness key was written');
    expect(raw, isNotEmpty, reason: 'freshness was written as unknown');
    return DateTime.tryParse(raw!);
  }

  group('actual sync timestamp survives to storage', () {
    test('carries the cache sync instant, not the read time', () async {
      await saveIncident(widgetRow('inc-1'));

      final FakeWidgetStore store = FakeWidgetStore();
      await WidgetRefresher.fromCache(cache, store: store).refresh();

      expect(
        storedStamp(store)?.millisecondsSinceEpoch,
        syncedAt.millisecondsSinceEpoch,
        reason: 'the stamp must be the API read the cache actually recorded',
      );
    });

    test('re-reading the cache never renews freshness', () async {
      await saveIncident(widgetRow('inc-1'));
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetRefresher refresher = WidgetRefresher.fromCache(
        cache,
        store: store,
      );

      await refresher.refresh();
      final DateTime? first = storedStamp(store);
      await refresher.refresh();

      expect(
        storedStamp(store)?.millisecondsSinceEpoch,
        first?.millisecondsSinceEpoch,
        reason: 'a cached read is not a sync',
      );
      expect(
        DateTime.now().toUtc().difference(syncedAt).inHours,
        greaterThan(0),
        reason: 'fixture must be in the past, so "now" would be detectable',
      );
    });

    test('an authoritative action sync stamps the widget', () async {
      // The acknowledge path upserts one row instead of replacing the list, so
      // the row's own stamp is the action's — and the acknowledgement it
      // carries must be visible on the widget.
      final DateTime actionAt = DateTime.utc(2026, 10, 4, 13, 30, 0);
      await saveIncident(widgetRow('inc-1'));
      await cache.upsertIncident(
        IncidentSnapshot(
          id: 'inc-1',
          monitorId: 'mon-inc-1',
          monitorName: 'Monitor inc-1',
          status: 'ongoing',
          startedAt: '2026-09-27T10:00:00Z',
          acknowledgedAt: '2026-10-04T13:29:00Z',
          insertedAt: '2026-09-27T10:00:00Z',
        ),
        session: cache.sessionEpoch,
        syncedAt: actionAt,
      );

      final FakeWidgetStore store = FakeWidgetStore();
      await WidgetRefresher.fromCache(cache, store: store).refresh();

      expect(
        storedStamp(store)?.millisecondsSinceEpoch,
        actionAt.millisecondsSinceEpoch,
      );
      expect(store.values[WidgetDataKeys.acknowledged], isTrue);
    });
  });

  group('unknown freshness', () {
    test('a row with no stamp is stored as unknown, not now', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetRefresher refresher = WidgetRefresher(
        store: store,
        loadSnapshots: () async => <IncidentSnapshot>[widgetRow('inc-1')],
      );

      await refresher.refresh();

      expect(store.values[WidgetDataKeys.updatedAt], '');
      final WidgetSnapshot? stored = await refresher.readStored();
      expect(stored, isNotNull);
      expect(stored!.freshnessUnknown, isTrue);
      expect(stored.syncAge(DateTime.utc(2026, 10, 5)), isNull);
      expect(
        stored.isStaleAt(DateTime.utc(2026, 10, 5), const Duration(hours: 1)),
        isFalse,
      );
    });

    test('an unparseable stored stamp decodes to unknown', () {
      final WidgetSnapshot? decoded = WidgetSnapshot.fromWidgetData(
        <String, Object?>{
          WidgetDataKeys.incidentId: 'inc-1',
          WidgetDataKeys.monitorId: 'mon-1',
          WidgetDataKeys.status: 'ongoing',
          WidgetDataKeys.updatedAt: 'whenever',
        },
      );
      expect(decoded, isNotNull);
      expect(decoded!.freshnessUnknown, isTrue);
    });

    test('unknown freshness survives a store round trip unchanged', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetSnapshot snapshot = WidgetSnapshot(
        incidentId: 'inc-1',
        monitorId: 'mon-1',
        status: 'ongoing',
      );
      final WidgetRefresher refresher = WidgetRefresher(
        store: store,
        loadSnapshots: () async => <IncidentSnapshot>[],
      );

      await refresher.applySnapshot(snapshot);

      final WidgetSnapshot? restored = await refresher.readStored();
      expect(restored!.updatedAt, isNull);
      expect(restored.toWidgetData()[WidgetDataKeys.updatedAt], '');
    });
  });

  group('staleness of known data', () {
    test('old data is stale, recent data is not', () {
      final DateTime now = DateTime.utc(2026, 10, 4, 12);
      const Duration threshold = Duration(hours: 1);
      WidgetSnapshot at(DateTime stamp) => WidgetSnapshot(
        incidentId: 'inc-1',
        monitorId: 'mon-1',
        status: 'ongoing',
        updatedAt: stamp,
      );

      expect(
        at(now.subtract(const Duration(minutes: 5))).isStaleAt(now, threshold),
        isFalse,
      );
      expect(
        at(now.subtract(const Duration(hours: 6))).isStaleAt(now, threshold),
        isTrue,
      );
    });

    test('a future stamp clamps to zero rather than reading negative', () {
      final DateTime now = DateTime.utc(2026, 10, 4, 12);
      final WidgetSnapshot snapshot = WidgetSnapshot(
        incidentId: 'inc-1',
        monitorId: 'mon-1',
        status: 'ongoing',
        updatedAt: now.add(const Duration(hours: 2)),
      );
      expect(snapshot.syncAge(now), Duration.zero);
      expect(snapshot.elapsedLabel(now), '0m');
    });
  });

  group('push handling never renews freshness', () {
    test('mergePush preserves the stored sync stamp', () {
      final DateTime at = DateTime.utc(2026, 10, 4, 12);
      final WidgetSnapshot stored = WidgetSnapshot.fromCache(
        widgetRow('inc-1'),
        syncedAt: at,
      );
      final WidgetSnapshot? merged = stored.mergePush(pushFor('inc-1'));

      expect(merged, isNotNull);
      expect(
        merged!.updatedAt?.millisecondsSinceEpoch,
        at.millisecondsSinceEpoch,
        reason: 'a push announcement is not a sync',
      );
    });

    test('applying a push to stored data keeps the original stamp', () async {
      final FakeWidgetStore store = FakeWidgetStore();
      final WidgetRefresher refresher = WidgetRefresher(
        store: store,
        loadSnapshots: () async => <IncidentSnapshot>[widgetRow('inc-1')],
      );
      final DateTime at = DateTime.utc(2026, 10, 4, 12);
      await refresher.applySnapshot(
        WidgetSnapshot.fromCache(widgetRow('inc-1'), syncedAt: at),
      );

      await refresher.applyPush(pushFor('inc-1'));

      expect(
        storedStamp(store)?.millisecondsSinceEpoch,
        at.millisecondsSinceEpoch,
      );
    });
  });
}
