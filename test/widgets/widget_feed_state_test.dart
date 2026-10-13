import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/widgets/widget_snapshot.dart';
import 'package:uptrack_mobile/widgets/widget_store.dart';

import 'widget_test_support.dart';

/// The iOS widget must not claim "No ongoing incidents" when it simply has
/// no data (signed out, fresh install, never synced). Dart marks a proven
/// all-clear; the widget shows the all-clear text only with that mark.
void main() {
  WidgetRefresher refresher(
    FakeWidgetStore store,
    List<IncidentSnapshot> rows, {
    bool complete = true,
    WidgetWriteGate? gate,
  }) => WidgetRefresher(
    store: store,
    loadSnapshots: () async => rows,
    loadEnumeratesAll: complete,
    gate: gate ?? WidgetWriteGate(),
  );

  test('a proven all-clear marks the feed as all clear', () async {
    final FakeWidgetStore store = FakeWidgetStore();
    await refresher(store, <IncidentSnapshot>[
      widgetRow('inc-1', status: 'resolved', resolvedAt: 'x'),
    ]).refresh();
    expect(store.values[WidgetDataKeys.feedState], WidgetDataKeys.feedAllClear);
    for (final String key in WidgetDataKeys.all) {
      expect(store.values.containsKey(key), isFalse, reason: key);
    }
  });

  test('an ongoing incident removes the all-clear mark', () async {
    final FakeWidgetStore store = FakeWidgetStore();
    store.values[WidgetDataKeys.feedState] = WidgetDataKeys.feedAllClear;
    await refresher(store, <IncidentSnapshot>[widgetRow('inc-1')]).refresh();
    expect(store.values.containsKey(WidgetDataKeys.feedState), isFalse);
    expect(store.values[WidgetDataKeys.incidentId], 'inc-1');
  });

  test('a partial feed never marks an all-clear', () async {
    final FakeWidgetStore store = FakeWidgetStore();
    await refresher(
      store,
      const <IncidentSnapshot>[],
      complete: false,
    ).refresh();
    expect(store.values.containsKey(WidgetDataKeys.feedState), isFalse);
  });

  test('logout removes the all-clear mark', () async {
    final FakeWidgetStore store = FakeWidgetStore();
    final WidgetWriteGate gate = WidgetWriteGate();
    await refresher(store, const <IncidentSnapshot>[], gate: gate).refresh();
    expect(store.values[WidgetDataKeys.feedState], WidgetDataKeys.feedAllClear);
    await clearWidgetData(store, gate);
    expect(store.values.containsKey(WidgetDataKeys.feedState), isFalse);
  });
}
