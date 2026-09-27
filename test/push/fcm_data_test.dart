import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/push/fcm_data.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/push/push_service.dart';
import 'package:uptrack_mobile/widgets/widget_snapshot.dart';
import 'package:uptrack_mobile/widgets/widget_store.dart';

/// Fake [LocalNotifier] recording foreground displays.
class FakeNotifier implements LocalNotifier {
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

IncidentSnapshot row(String id) => IncidentSnapshot(
  id: id,
  monitorId: 'mon-$id',
  monitorName: 'Monitor $id',
  status: 'ongoing',
  startedAt: '2026-09-27T10:00:00Z',
  resolvedAt: null,
  insertedAt: '2026-09-27T10:00:00Z',
);

FcmDataHandler handlerWith(
  FakeNotifier notifier,
  FakeStore store, {
  List<IncidentSnapshot> snapshots = const <IncidentSnapshot>[],
}) => FcmDataHandler(
  notifier: notifier,
  refresher: WidgetRefresher(
    store: store,
    loadSnapshots: () async => snapshots,
  ),
);

void main() {
  group('FcmDataHandler', () {
    test('shows the alert and refreshes the widget for an incident', () async {
      final FakeNotifier notifier = FakeNotifier();
      final FakeStore store = FakeStore();
      final FcmDataHandler handler = handlerWith(
        notifier,
        store,
        snapshots: <IncidentSnapshot>[row('inc-1')],
      );
      final PushMessage? message = await handler.handle(<Object?, Object?>{
        'incident_id': 'inc-1',
        'monitor_name': 'Monitor inc-1',
        'severity': 'p1',
      });
      expect(message, isNotNull);
      expect(message!.incidentId, 'inc-1');
      // Repeat pushes collapse: the same incident always maps to one id.
      expect(message.notificationId, pushFor('inc-1').notificationId);
      expect(notifier.shown?.incidentId, 'inc-1');
      expect(store.values[WidgetDataKeys.incidentId], 'inc-1');
      expect(store.refreshes, 1);
    });

    test('parks an unknown incident id and still shows the alert', () async {
      final FakeNotifier notifier = FakeNotifier();
      final FakeStore store = FakeStore();
      final FcmDataHandler handler = handlerWith(notifier, store);
      final PushMessage? message = await handler.handle(<Object?, Object?>{
        'incident_id': 'inc-new',
      });
      expect(message, isNotNull);
      expect(notifier.shown?.incidentId, 'inc-new');
      expect(store.values[WidgetDataKeys.pendingIncidentId], 'inc-new');
      expect(store.refreshes, 1);
    });

    test('ignores payloads naming nothing actionable', () async {
      final FakeNotifier notifier = FakeNotifier();
      final FakeStore store = FakeStore();
      final FcmDataHandler handler = handlerWith(notifier, store);
      expect(await handler.handle(null), isNull);
      expect(
        await handler.handle(<Object?, Object?>{'severity': 'p1'}),
        isNull,
      );
      expect(notifier.shown, isNull);
      expect(store.refreshes, 0);
    });
  });
}

PushMessage pushFor(String incidentId) =>
    PushMessage.fromMap(<Object?, Object?>{'incident_id': incidentId})!;
