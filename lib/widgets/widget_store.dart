import 'package:home_widget/home_widget.dart';

import '../data/local/app_database.dart';
import '../data/local/cache_repository.dart';
import '../push/push_message.dart';
import 'widget_group.dart';
import 'widget_snapshot.dart';

/// `home_widget` plugin calls behind a seam the tests fake (the real
/// statics hit a platform channel with no host under `flutter_test`).
abstract class WidgetDataStore {
  Future<bool?> save<T>(String key, T? data);
  Future<T?> read<T>(String key);
  Future<bool?> refresh();
}

/// Production [WidgetDataStore] delegating to the `home_widget` plugin.
///
/// The T055 WidgetKit extension reads the same App Group data (the group
/// id is registered via [WidgetGroup.ensureConfigured] alongside the
/// entitlement); the T056 Glance widget reads the Android-side store.
/// Dart only writes primitives here.
class HomeWidgetStore implements WidgetDataStore {
  const HomeWidgetStore();

  @override
  Future<bool?> save<T>(String key, T? data) async {
    await WidgetGroup.ensureConfigured();
    return HomeWidget.saveWidgetData<T>(key, data);
  }

  @override
  Future<T?> read<T>(String key) async {
    await WidgetGroup.ensureConfigured();
    return HomeWidget.getWidgetData<T>(key);
  }

  @override
  Future<bool?> refresh() async {
    await WidgetGroup.ensureConfigured();
    return HomeWidget.updateWidget(
      androidName: 'UptrackStatusWidgetProvider',
      iOSName: 'UptrackStatusWidget',
    );
  }
}

/// Clears every widget key and refreshes the widget so no signed-in
/// incident data lingers on the home screen after logout, account switch,
/// 401 re-auth or account deletion (R2.4). Best-effort: the platform
/// channel may be unavailable (tests, exotic hosts) and must never fail
/// the caller's sign-out flow.
Future<void> clearWidgetData([
  WidgetDataStore store = const HomeWidgetStore(),
]) async {
  try {
    for (final String key in WidgetDataKeys.all) {
      await store.save<String>(key, null);
    }
    await store.refresh();
  } catch (_) {
    // Widget clearing is hygiene, not correctness of sign-out.
  }
}

/// Loads cached incident rows for the widget (defaults to the Drift
/// read-through cache; tests inject a fake list).
typedef SnapshotLoader = Future<List<IncidentSnapshot>> Function();

/// Keeps the home widget in sync with the incident cache and the push
/// stream: full refresh from the Drift cache (foreground + best-effort
/// FCM data-message paths) and targeted push merges.
class WidgetRefresher {
  WidgetRefresher({required this.store, required this.loadSnapshots});

  /// Wires the refresher to the Drift read-through cache.
  WidgetRefresher.fromCache(CacheRepository repository, {required this.store})
    : loadSnapshots = (() async {
        final CachedList<CachedIncident> cached = await repository
            .getIncidents();
        return cached.data
            .map(
              (CachedIncident row) => IncidentSnapshot(
                id: row.id,
                monitorId: row.monitorId,
                monitorName: row.monitorName,
                status: row.status,
                startedAt: row.startedAt,
                resolvedAt: row.resolvedAt,
                acknowledgedAt: row.acknowledgedAt,
                insertedAt: row.insertedAt,
              ),
            )
            .toList();
      });

  final WidgetDataStore store;
  final SnapshotLoader loadSnapshots;

  /// Picks the snapshot to show: the most recently inserted ongoing
  /// incident, or null when everything resolved (the widget clears).
  static WidgetSnapshot? pickTop(List<IncidentSnapshot> snapshots) {
    final List<IncidentSnapshot> ongoing = snapshots
        .where((IncidentSnapshot s) => s.resolvedAt == null)
        .toList();
    if (ongoing.isEmpty) {
      return null;
    }
    ongoing.sort(
      (IncidentSnapshot a, IncidentSnapshot b) =>
          b.insertedAt.compareTo(a.insertedAt),
    );
    return WidgetSnapshot.fromCache(ongoing.first);
  }

  /// Reloads from the cache and applies the result (update/replace/clear
  /// per [collapseWidgetUpdate]); always refreshes the widget afterwards.
  Future<WidgetUpdateAction> refresh() async {
    final List<IncidentSnapshot> snapshots = await loadSnapshots();
    return applySnapshot(pickTop(snapshots));
  }

  /// Applies one push: when it names the stored incident, merges in place;
  /// otherwise reloads from the cache (the push may announce an incident
  /// the cache already synced, or one still in flight). A push with no
  /// incident id is a no-op.
  Future<WidgetUpdateAction> applyPush(PushMessage message) async {
    final String? incidentId = message.incidentId;
    if (incidentId == null || incidentId.isEmpty) {
      return WidgetUpdateAction.noop;
    }
    final WidgetSnapshot? current = await readStored();
    if (current != null) {
      final WidgetSnapshot? merged = current.mergePush(message);
      if (merged != null) {
        return applySnapshot(merged);
      }
    }
    final List<IncidentSnapshot> snapshots = await loadSnapshots();
    IncidentSnapshot? match;
    for (final IncidentSnapshot snapshot in snapshots) {
      if (snapshot.id == incidentId) {
        match = snapshot;
        break;
      }
    }
    if (match == null) {
      // Push arrived before the next sync: park the id so the following
      // refresh can reconcile, and refresh the widget with last-known data.
      await store.save<String>(WidgetDataKeys.pendingIncidentId, incidentId);
      await store.refresh();
      return WidgetUpdateAction.noop;
    }
    return applySnapshot(WidgetSnapshot.fromCache(match));
  }

  /// Writes [snapshot] (or clears when null) and refreshes the widget,
  /// returning the collapse action taken against the stored snapshot.
  Future<WidgetUpdateAction> applySnapshot(WidgetSnapshot? snapshot) async {
    final WidgetSnapshot? current = await readStored();
    final WidgetUpdateAction action = collapseWidgetUpdate(
      current: current,
      incoming: snapshot,
    );
    if (snapshot == null || action == WidgetUpdateAction.clear) {
      for (final String key in WidgetDataKeys.all) {
        await store.save<String>(key, null);
      }
    } else {
      final Map<String, Object?> data = snapshot.toWidgetData();
      for (final MapEntry<String, Object?> entry in data.entries) {
        final Object? value = entry.value;
        if (value is bool) {
          await store.save<bool>(entry.key, value);
        } else {
          await store.save<String>(entry.key, value?.toString());
        }
      }
      await store.save<String>(WidgetDataKeys.pendingIncidentId, null);
    }
    await store.refresh();
    return action;
  }

  /// Reads the currently stored snapshot (null when never written/cleared).
  Future<WidgetSnapshot?> readStored() async {
    final Map<String, Object?> data = <String, Object?>{
      WidgetDataKeys.incidentId: await store.read<String>(
        WidgetDataKeys.incidentId,
      ),
      WidgetDataKeys.monitorId: await store.read<String>(
        WidgetDataKeys.monitorId,
      ),
      WidgetDataKeys.monitorName: await store.read<String>(
        WidgetDataKeys.monitorName,
      ),
      WidgetDataKeys.status: await store.read<String>(WidgetDataKeys.status),
      WidgetDataKeys.startedAt: await store.read<String>(
        WidgetDataKeys.startedAt,
      ),
      WidgetDataKeys.acknowledged: await store.read<bool>(
        WidgetDataKeys.acknowledged,
      ),
      WidgetDataKeys.updatedAt: await store.read<String>(
        WidgetDataKeys.updatedAt,
      ),
    };
    return WidgetSnapshot.fromWidgetData(data);
  }
}
