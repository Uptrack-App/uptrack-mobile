import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/widgets/live_surface_sync.dart';

import 'widget_test_support.dart';

void main() {
  group('LiveSurfaceSync', () {
    test('refreshes the widget, then the Live Activities', () async {
      final List<String> calls = <String>[];
      final LiveSurfaceSync sync = LiveSurfaceSync(
        refreshWidget: () async => calls.add('widget'),
        reconcileActivities: () async => calls.add('activities'),
      );
      await sync.run();
      expect(calls, <String>['widget', 'activities']);
    });

    test('a widget failure still reconciles the activities', () async {
      final List<String> calls = <String>[];
      final LiveSurfaceSync sync = LiveSurfaceSync(
        refreshWidget: () async => throw StateError('no host'),
        reconcileActivities: () async => calls.add('activities'),
      );
      await sync.run();
      expect(calls, <String>['activities']);
    });

    test('triggers during a run coalesce into one more run', () async {
      int widget = 0;
      final Completer<void> gate = Completer<void>();
      final LiveSurfaceSync sync = LiveSurfaceSync(
        refreshWidget: () async {
          widget++;
          if (widget == 1) {
            await gate.future;
          }
        },
        reconcileActivities: () async {},
      );
      final Future<void> first = sync.run();
      final Future<void> second = sync.run();
      final Future<void> third = sync.run();
      gate.complete();
      await Future.wait(<Future<void>>[first, second, third]);
      expect(widget, 2);
    });

    test('runs on every trigger event until disposed', () async {
      int runs = 0;
      final StreamController<void> trigger = StreamController<void>();
      final LiveSurfaceSync sync = LiveSurfaceSync(
        refreshWidget: () async => runs++,
        reconcileActivities: () async {},
      );
      sync.attach(trigger.stream);
      trigger.add(null);
      await pumpEventQueue();
      expect(runs, 1);
      await sync.dispose();
      trigger.add(null);
      await pumpEventQueue();
      expect(runs, 1);
      await trigger.close();
    });
  });

  group('CacheRepository.incidentsChanged (widget refresh path)', () {
    late AppDatabase db;
    late CacheRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = CacheRepository(db);
    });

    tearDown(() => db.close());

    test('fires after an applied list sync and an upsert', () async {
      int events = 0;
      final StreamSubscription<void> sub = repo.incidentsChanged.listen(
        (_) => events++,
      );
      await repo.saveIncidents(
        <IncidentSnapshot>[widgetRow('inc-1')],
        session: repo.sessionEpoch,
        revision: repo.incidentRevision,
      );
      await repo.upsertIncident(
        widgetRow('inc-1', status: 'resolved'),
        session: repo.sessionEpoch,
      );
      await pumpEventQueue();
      expect(events, 2);
      await sub.cancel();
    });

    test('a fenced write does not fire', () async {
      int events = 0;
      final StreamSubscription<void> sub = repo.incidentsChanged.listen(
        (_) => events++,
      );
      final int staleSession = repo.sessionEpoch;
      await repo.clearAll();
      await repo.saveIncidents(
        <IncidentSnapshot>[widgetRow('inc-1')],
        session: staleSession,
        revision: repo.incidentRevision,
      );
      await pumpEventQueue();
      expect(events, 0);
      await sub.cancel();
    });
  });
}
