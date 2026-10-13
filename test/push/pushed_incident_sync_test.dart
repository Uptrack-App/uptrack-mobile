import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/push/pushed_incident_sync.dart';

IncidentDetail detail(String id, {String status = 'ongoing'}) => IncidentDetail(
  incident: Incident(
    id: id,
    monitorId: 'mon-1',
    monitorName: 'API',
    status: status,
    insertedAt: '2026-10-08T10:00:00Z',
    startedAt: '2026-10-08T10:00:00Z',
  ),
  updates: const <IncidentUpdate>[],
);

void main() {
  late AppDatabase db;
  late CacheRepository cache;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    cache = CacheRepository(db);
  });

  tearDown(() => db.close());

  test(
    'stores the pushed incident so the widget and activity see it',
    () async {
      int changes = 0;
      final StreamSubscription<void> sub = cache.incidentsChanged.listen(
        (_) => changes++,
      );
      final bool stored = await syncPushedIncident(
        cache: cache,
        fetch: (String id) async => detail(id),
        incidentId: 'inc-1',
      );
      await pumpEventQueue();
      expect(stored, isTrue);
      expect(changes, 1);
      final CachedList<CachedIncident> rows = await cache.getIncidents();
      expect(rows.data.single.id, 'inc-1');
      expect(rows.data.single.monitorName, 'API');
      await sub.cancel();
    },
  );

  test('a resolve push stores the resolved state', () async {
    await syncPushedIncident(
      cache: cache,
      fetch: (String id) async => detail(id, status: 'resolved'),
      incidentId: 'inc-1',
    );
    expect((await cache.getIncidents()).data.single.status, 'resolved');
  });

  test('a fetch failure stores nothing and never throws', () async {
    final bool stored = await syncPushedIncident(
      cache: cache,
      fetch: (String id) async => throw Exception('offline'),
      incidentId: 'inc-1',
    );
    expect(stored, isFalse);
    expect((await cache.getIncidents()).data, isEmpty);
  });

  test('a logout during the fetch stores nothing', () async {
    final Completer<IncidentDetail> pending = Completer<IncidentDetail>();
    final Future<bool> result = syncPushedIncident(
      cache: cache,
      fetch: (String id) => pending.future,
      incidentId: 'inc-1',
    );
    await cache.clearAll();
    pending.complete(detail('inc-1'));
    expect(await result, isFalse);
    expect((await cache.getIncidents()).data, isEmpty);
  });

  test('an empty or demo id is ignored', () async {
    int fetches = 0;
    Future<IncidentDetail> fetch(String id) async {
      fetches++;
      return detail(id);
    }

    expect(
      await syncPushedIncident(cache: cache, fetch: fetch, incidentId: ''),
      isFalse,
    );
    expect(
      await syncPushedIncident(
        cache: cache,
        fetch: fetch,
        incidentId: 'demo-incident',
      ),
      isFalse,
    );
    expect(fetches, 0);
  });
}
