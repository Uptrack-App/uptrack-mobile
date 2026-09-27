import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/widgets/widget_snapshot.dart';

Incident testIncident() => const Incident(
  id: 'inc-1',
  monitorId: 'mon-1',
  monitorName: 'DB primary',
  status: 'ongoing',
  insertedAt: '2026-09-27T10:00:00Z',
  startedAt: '2026-09-27T10:00:00Z',
);

IncidentSnapshot testRow({
  String id = 'inc-1',
  String status = 'ongoing',
  String? resolvedAt,
  String insertedAt = '2026-09-27T10:00:00Z',
}) => IncidentSnapshot(
  id: id,
  monitorId: 'mon-1',
  monitorName: 'DB primary',
  status: status,
  startedAt: '2026-09-27T10:00:00Z',
  resolvedAt: resolvedAt,
  insertedAt: insertedAt,
);

void main() {
  group('WidgetSnapshot mapping', () {
    test('fromIncident copies status, monitor name, elapsed anchor', () {
      final WidgetSnapshot snapshot = WidgetSnapshot.fromIncident(
        testIncident(),
      );
      expect(snapshot.incidentId, 'inc-1');
      expect(snapshot.monitorId, 'mon-1');
      expect(snapshot.monitorName, 'DB primary');
      expect(snapshot.status, 'ongoing');
      expect(snapshot.displayName, 'DB primary');
      expect(snapshot.isResolved, isFalse);
    });

    test('fromCache marks acknowledged rows', () {
      final WidgetSnapshot snapshot = WidgetSnapshot.fromCache(
        IncidentSnapshot(
          id: 'inc-9',
          monitorId: 'mon-9',
          status: 'ongoing',
          acknowledgedAt: '2026-09-27T11:00:00Z',
          insertedAt: '2026-09-27T10:00:00Z',
        ),
      );
      expect(snapshot.acknowledged, isTrue);
      expect(snapshot.displayName, 'Incident inc-9');
    });

    test('resolved status flags clearing', () {
      final WidgetSnapshot snapshot = WidgetSnapshot.fromCache(
        testRow(status: 'resolved', resolvedAt: '2026-09-27T12:00:00Z'),
      );
      expect(snapshot.isResolved, isTrue);
    });
  });

  group('elapsed labels', () {
    test('minutes, hours, days buckets', () {
      final DateTime now = DateTime.utc(2026, 9, 27, 12);
      WidgetSnapshot at(String iso) => WidgetSnapshot(
        incidentId: 'i',
        monitorId: 'm',
        status: 'ongoing',
        startedAt: iso,
        updatedAt: now,
      );
      expect(at('2026-09-27T11:55:00Z').elapsedLabel(now), '5m');
      expect(at('2026-09-27T10:00:00Z').elapsedLabel(now), '2h');
      expect(at('2026-09-24T12:00:00Z').elapsedLabel(now), '3d');
    });

    test('falls back to updatedAt without a start anchor', () {
      final DateTime now = DateTime.utc(2026, 9, 27, 12);
      final WidgetSnapshot snapshot = WidgetSnapshot(
        incidentId: 'i',
        monitorId: 'm',
        status: 'ongoing',
        updatedAt: now.subtract(const Duration(minutes: 7)),
      );
      expect(snapshot.elapsedLabel(now), '7m');
    });

    test('unparseable anchor renders an em dash', () {
      final WidgetSnapshot snapshot = WidgetSnapshot(
        incidentId: 'i',
        monitorId: 'm',
        status: 'ongoing',
        startedAt: 'not-a-time',
        updatedAt: DateTime.utc(2026, 9, 27, 12),
      );
      expect(snapshot.elapsedLabel(DateTime.utc(2026, 9, 27, 12)), '—');
    });
  });

  group('widget-data round trip', () {
    test('toWidgetData/fromWidgetData preserves fields', () {
      final WidgetSnapshot snapshot = WidgetSnapshot.fromIncident(
        testIncident(),
      );
      final WidgetSnapshot? restored = WidgetSnapshot.fromWidgetData(
        snapshot.toWidgetData(),
      );
      expect(restored, isNotNull);
      expect(restored!.incidentId, 'inc-1');
      expect(restored.monitorName, 'DB primary');
      expect(restored.status, 'ongoing');
      expect(restored.acknowledged, isFalse);
    });

    test('missing incident id decodes to null', () {
      expect(WidgetSnapshot.fromWidgetData(<String, Object?>{}), isNull);
    });
  });

  group('collapseWidgetUpdate', () {
    final WidgetSnapshot stored = WidgetSnapshot.fromCache(testRow());
    final WidgetSnapshot same = WidgetSnapshot.fromCache(
      testRow(insertedAt: '2026-09-27T10:05:00Z'),
    );
    final WidgetSnapshot other = WidgetSnapshot.fromCache(testRow(id: 'inc-2'));
    final WidgetSnapshot resolved = WidgetSnapshot.fromCache(
      testRow(status: 'resolved', resolvedAt: '2026-09-27T12:00:00Z'),
    );

    test('first incident replaces; same incident updates', () {
      expect(
        collapseWidgetUpdate(current: null, incoming: same),
        WidgetUpdateAction.replace,
      );
      expect(
        collapseWidgetUpdate(current: stored, incoming: same),
        WidgetUpdateAction.update,
      );
    });

    test('different incident replaces; resolved clears', () {
      expect(
        collapseWidgetUpdate(current: stored, incoming: other),
        WidgetUpdateAction.replace,
      );
      expect(
        collapseWidgetUpdate(current: stored, incoming: resolved),
        WidgetUpdateAction.clear,
      );
    });

    test('null incoming clears a stored snapshot, no-ops when empty', () {
      expect(
        collapseWidgetUpdate(current: stored, incoming: null),
        WidgetUpdateAction.clear,
      );
      expect(
        collapseWidgetUpdate(current: null, incoming: null),
        WidgetUpdateAction.noop,
      );
    });
  });

  group('mergePush', () {
    test('same incident merges; unknown incident returns null', () {
      final WidgetSnapshot stored = WidgetSnapshot.fromCache(testRow());
      final PushMessage same = PushMessage.fromMap(<Object?, Object?>{
        'incident_id': 'inc-1',
        'monitor_id': 'mon-1',
      })!;
      final WidgetSnapshot? merged = stored.mergePush(same);
      expect(merged, isNotNull);
      expect(merged!.status, 'ongoing');

      final PushMessage other = PushMessage.fromMap(<Object?, Object?>{
        'incident_id': 'inc-2',
      })!;
      expect(stored.mergePush(other), isNull);

      final PushMessage bare = PushMessage.fromMap(<Object?, Object?>{
        'title': 'hello',
      })!;
      expect(stored.mergePush(bare), isNull);
    });
  });
}
