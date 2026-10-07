import 'dart:async';

import 'package:home_widget/home_widget.dart';

import '../data/local/app_database.dart';
import '../data/local/cache_repository.dart';
import '../push/push_message.dart';
import 'widget_group.dart';
import 'widget_snapshot.dart';

/// Fully-qualified native provider class `home_widget` must load on Android
/// (R5).
///
/// The two ids differ on purpose and must both be respected:
///
/// - `applicationId` is `app.uptrack.mobile`, which is what
///   `Context.packageName` reports at runtime;
/// - the provider class lives in the `namespace` package
///   `app.uptrack.uptrack_mobile`.
///
/// `home_widget` 0.10.0 resolves a bare `androidName` by prefixing it with
/// `context.packageName`, so `androidName: 'UptrackStatusWidgetProvider'`
/// asked `Class.forName` for `app.uptrack.mobile.UptrackStatusWidgetProvider`
/// — a class that does not exist, and every refresh failed. `qualifiedAndroidName`
/// is passed through verbatim, so it has to be the exact native class. The fix
/// is deliberately *this* constant: no namespace refactor, no manifest change.
const String kAndroidWidgetProviderClass =
    'app.uptrack.uptrack_mobile.UptrackStatusWidgetProvider';

/// Simple class name of [kAndroidWidgetProviderClass] (what a manifest
/// `.Receiver` entry resolves against the `namespace`).
const String kAndroidWidgetProviderSimpleName = 'UptrackStatusWidgetProvider';

/// WidgetKit kind for the iOS extension (Android name is irrelevant there).
const String kIosWidgetKind = 'UptrackStatusWidget';

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
    // `qualifiedAndroidName`, never `androidName`: the plugin resolves a bare
    // `androidName` against the application id, which is not the package the
    // provider class is declared in (see [kAndroidWidgetProviderClass]).
    return HomeWidget.updateWidget(
      qualifiedAndroidName: kAndroidWidgetProviderClass,
      iOSName: kIosWidgetKind,
    );
  }
}

/// Serializes widget writes and fences them by session epoch (R5).
///
/// Mirrors the discipline the offline cache already uses for its own rows: a
/// widget write captures the epoch before it starts and is refused *inside* the
/// queue if a logout advanced the epoch meanwhile, and the clear that logout
/// performs is queued so it lands after everything already pending. Without
/// both halves, a sync that began while signed in can put account data back on
/// the home screen after logout has already wiped it.
class WidgetWriteGate {
  WidgetWriteGate();

  /// Process-wide gate. A single instance is deliberate: `clearWidgetData` is
  /// the logout entry point and must fence refreshes started through any other
  /// `WidgetRefresher`, including ones held by the push plumbing.
  static final WidgetWriteGate shared = WidgetWriteGate();

  int _epoch = 0;
  Future<void> _tail = Future<void>.value();

  /// Current session. Advanced by [endSession]; captured by [run].
  int get epoch => _epoch;

  /// Ends the current session and clears the widget.
  ///
  /// The epoch moves first, so every queued or in-flight write from the ended
  /// session is refused; [clear] is then queued behind them so it cannot be
  /// overtaken by a write that had already started.
  Future<void> endSession({required Future<void> Function() clear}) {
    _epoch++;
    return _enqueue(clear, session: _epoch);
  }

  /// Queues [write], running it only if [session] is still the current epoch.
  ///
  /// Pass the epoch captured when the *operation* started, not the current one:
  /// re-reading it here would let a write that began before a logout pass as a
  /// new-session write. Returns whether the write ran.
  Future<bool> run(Future<void> Function() write, {int? session}) =>
      _enqueue(write, session: session ?? _epoch);

  Future<bool> _enqueue(Future<void> Function() write, {required int session}) {
    final Completer<bool> completer = Completer<bool>();
    _tail = _tail.then((_) async {
      try {
        if (session != _epoch) {
          // The session ended while this write was queued.
          completer.complete(false);
          return;
        }
        await write();
        completer.complete(true);
      } catch (error, stackTrace) {
        // The queue tail must stay runnable for later writes.
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

/// Clears every widget key and refreshes the widget so no signed-in
/// incident data lingers on the home screen after logout, account switch,
/// 401 re-auth or account deletion (R2.4, fenced by [WidgetWriteGate] in R5).
/// Best-effort: the platform channel may be unavailable (tests, exotic hosts)
/// and must never fail the caller's sign-out flow.
Future<void> clearWidgetData([
  WidgetDataStore store = const HomeWidgetStore(),
  WidgetWriteGate? gate,
]) async {
  final WidgetWriteGate writes = gate ?? WidgetWriteGate.shared;
  try {
    await writes.endSession(
      clear: () async {
        for (final String key in WidgetDataKeys.all) {
          await store.save<String>(key, null);
        }
        await store.save<String>(WidgetDataKeys.feedState, null);
        await store.refresh();
      },
    );
  } catch (_) {
    // Widget clearing is hygiene, not correctness of sign-out.
  }
}

/// Loads cached incident rows for the widget (defaults to the Drift
/// read-through cache; tests inject a fake list).
typedef SnapshotLoader = Future<List<IncidentSnapshot>> Function();

/// Loads the candidate set **with** the provenance that separates an
/// authoritative empty result from an unknown one (see
/// [WidgetCandidateLoad]).
typedef CandidateLoader = Future<WidgetCandidateLoad> Function();

/// Keeps the home widget in sync with the incident cache and the push
/// stream: full refresh from the Drift cache (foreground + best-effort
/// FCM data-message paths) and targeted push merges.
class WidgetRefresher {
  /// Builds a refresher over a plain row list.
  ///
  /// Rows carry no per-row sync stamp, and this loader cannot report whether the
  /// collection was ever enumerated, so the load is treated as **incomplete**
  /// unless the caller says otherwise with [loadEnumeratesAll]. That default is
  /// deliberate: a non-empty list is not proof of a complete feed — a cache fed
  /// only by detail reads or action upserts holds rows without ever having
  /// enumerated the collection — and completeness is what authorises clearing
  /// the widget. Prefer [WidgetRefresher.fromCache], which can tell the two apart
  /// from the cache's own `cache_meta` row.
  WidgetRefresher({
    required this.store,
    required SnapshotLoader loadSnapshots,
    bool loadEnumeratesAll = false,
    WidgetWriteGate? gate,
    this.publishable = WidgetSampleGuard.allow,
  }) : gate = gate ?? WidgetWriteGate.shared,
       _loadCandidates = (() async => WidgetCandidateLoad(
         enumeratesAll: loadEnumeratesAll,
         candidates: <WidgetIncidentCandidate>[
           for (final IncidentSnapshot row in await loadSnapshots())
             WidgetIncidentCandidate(row: row),
         ],
       ));

  /// Wires the refresher to the Drift read-through cache.
  ///
  /// Each row carries the instant its data was actually fetched (`cachedAt`,
  /// stamped by the cache writer at the moment of the write that produced the
  /// row), so the widget reports the real sync time instead of stamping the
  /// moment it happened to read. Reading the cache never renews freshness.
  ///
  /// The collection's own sync instant (`cache_meta`) travels with the load as
  /// [WidgetCandidateLoad.syncedAt] and is the *only* completeness proof here:
  /// it is written solely by a completed list sync, never by an action upsert or
  /// a detail read, and it is wiped by `clearAll`. The two stay separate on
  /// purpose — a row's `cachedAt` is freshness for that incident, the
  /// collection's stamp is coverage of the feed, and neither substitutes for the
  /// other.
  WidgetRefresher.fromCache(
    CacheRepository repository, {
    required this.store,
    WidgetWriteGate? gate,
    this.publishable = WidgetSampleGuard.allow,
  }) : gate = gate ?? WidgetWriteGate.shared,
       _loadCandidates = (() async {
         final CachedList<CachedIncident> cached = await repository
             .getIncidents();
         return WidgetCandidateLoad(
           syncedAt: cached.cachedAt,
           candidates: cached.data
               .map(
                 (CachedIncident row) => WidgetIncidentCandidate(
                   row: IncidentSnapshot(
                     id: row.id,
                     monitorId: row.monitorId,
                     monitorName: row.monitorName,
                     status: row.status,
                     startedAt: row.startedAt,
                     resolvedAt: row.resolvedAt,
                     acknowledgedAt: row.acknowledgedAt,
                     insertedAt: row.insertedAt,
                   ),
                   syncedAt: row.cachedAt,
                 ),
               )
               .toList(),
         );
       });

  final WidgetDataStore store;
  final WidgetWriteGate gate;

  /// Refuses sample/demo rows before they reach persistent widget storage.
  final WidgetPublishGate publishable;

  final CandidateLoader _loadCandidates;

  /// The candidate set this refresher selects from (shared with the Live
  /// Activity reconcile, so both surfaces read the same feed).
  Future<WidgetCandidateLoad> loadCandidates() => _loadCandidates();

  /// The next incident the widget should show, or null when there is nothing
  /// open to show.
  ///
  /// [preferIncidentId] wins when that incident is still eligible (a push named
  /// it); otherwise the most recently inserted eligible incident is chosen.
  /// Selecting from the eligible set — rather than from "whatever the caller
  /// resolved" — is what makes a resolve fall through to the *next* open
  /// incident instead of clearing a home screen that still has one (R5).
  static WidgetSnapshot? selectSnapshot(
    List<WidgetIncidentCandidate> candidates, {
    String? preferIncidentId,
  }) {
    final List<WidgetIncidentCandidate> open = candidates
        .where((WidgetIncidentCandidate c) => c.isEligible)
        .toList();
    if (open.isEmpty) {
      return null;
    }
    if (preferIncidentId != null) {
      for (final WidgetIncidentCandidate candidate in open) {
        if (candidate.row.id == preferIncidentId) {
          return candidate.toSnapshot();
        }
      }
    }
    open.sort(
      (WidgetIncidentCandidate a, WidgetIncidentCandidate b) =>
          b.row.insertedAt.compareTo(a.row.insertedAt),
    );
    return open.first.toSnapshot();
  }

  /// Picks the snapshot to show from plain rows: the most recently inserted
  /// ongoing incident, or null when everything resolved (the widget clears).
  ///
  /// Rows carry no sync stamp, so the result has unknown freshness unless
  /// [syncedAt] is given — never a fabricated "now".
  static WidgetSnapshot? pickTop(
    List<IncidentSnapshot> snapshots, {
    DateTime? syncedAt,
  }) => selectSnapshot(<WidgetIncidentCandidate>[
    for (final IncidentSnapshot row in snapshots)
      WidgetIncidentCandidate(row: row, syncedAt: syncedAt),
  ]);

  /// Reloads from the cache and applies the result (update/replace/clear
  /// per [collapseWidgetUpdate]); always refreshes the widget afterwards.
  ///
  /// A cache that cannot prove it enumerated the feed — never synced, fed only by
  /// detail reads or action upserts, or a read that failed — never clears: it
  /// leaves the widget exactly as it is. See [applyCandidates].
  Future<WidgetUpdateAction> refresh() async {
    final int session = gate.epoch;
    return applyCandidates(await _loadCandidates(), session: session);
  }

  /// Applies one push: the authoritative cache row wins when it knows the
  /// incident, and a merge of the stored snapshot covers the case where the
  /// cache has not caught up yet. A push with no incident id is a no-op.
  ///
  /// The cache is consulted *first* on purpose: the stored widget copy can only
  /// be as old as the last write, so trusting it over a freshly synced row
  /// would keep showing an incident the server has already resolved.
  Future<WidgetUpdateAction> applyPush(PushMessage message) async {
    // Captured before any await: a logout from here on must fence this write.
    final int session = gate.epoch;
    final String? incidentId = message.incidentId;
    if (incidentId == null || incidentId.isEmpty) {
      return WidgetUpdateAction.noop;
    }
    final WidgetCandidateLoad load = await _loadForPush();
    final List<WidgetIncidentCandidate> candidates = load.candidates;
    final bool known = candidates.any(
      (WidgetIncidentCandidate c) => c.row.id == incidentId,
    );
    if (known) {
      return applyCandidates(
        load,
        session: session,
        preferIncidentId: incidentId,
      );
    }
    final WidgetSnapshot? current = await readStored();
    final WidgetSnapshot? merged = current?.mergePush(message);
    if (merged != null && !merged.isResolved) {
      return applySnapshot(merged, session: session);
    }
    if (merged != null) {
      // The stored copy of the pushed incident is resolved and the cache no
      // longer carries the row (a resolution drops it out of the feed), so
      // parking the id would leave a dead incident on the home screen with
      // nothing left to reconcile it. Re-select from what the cache says is
      // eligible now: the next open incident, or — only when the load proves it
      // enumerated the feed — a clear (R5).
      //
      // A load that cannot answer (never synced, fed only by an action upsert or
      // a detail read, or a read that failed) writes nothing at all: unknown or
      // partial is not an all-clear, and the resolved copy stays put until a
      // sync can say better. Parking is skipped deliberately — the row that
      // would have named this id no longer exists.
      return applyCandidates(load, session: session);
    }
    // Push arrived before the next sync: park the id so the following refresh
    // can reconcile, and refresh the widget with last-known data. Fenced like
    // any other write, and reported as a no-op either way — a parked id
    // changes nothing that is displayed.
    await gate.run(() async {
      await store.save<String>(WidgetDataKeys.pendingIncidentId, incidentId);
      await store.refresh();
    }, session: session);
    return WidgetUpdateAction.noop;
  }

  /// The candidate load for a push, where a failed cache read is *unknown*
  /// rather than empty.
  ///
  /// A push is best-effort hygiene on the way to showing a notification: a
  /// database error must not escape past it and swallow the alert. Swallowing it
  /// here can never manufacture an all-clear, because [WidgetCandidateLoad]
  /// with no rows and no sync instant is not authoritative — the reconcile above
  /// then writes nothing. An explicit [refresh] still reports a failed read to
  /// its caller, because there the load *is* the result the caller asked for.
  Future<WidgetCandidateLoad> _loadForPush() async {
    try {
      return await _loadCandidates();
    } on Object {
      return const WidgetCandidateLoad(candidates: <WidgetIncidentCandidate>[]);
    }
  }

  /// Selects from [load] and applies the result.
  ///
  /// Pass the [session] epoch captured when the overall operation started.
  ///
  /// The clear decision is the load's to make, not this method's: an open
  /// candidate is written without any proof of completeness (showing a real
  /// ongoing incident is safe), but *nothing* is written when no candidate is
  /// eligible **and** the load cannot prove it enumerated the feed
  /// ([WidgetCandidateLoad.isKnownAllClear]). An uninitialized, partial or
  /// unreadable cache is not an all-clear, and clearing on one blanks the home
  /// screen for data nobody ever enumerated.
  Future<WidgetUpdateAction> applyCandidates(
    WidgetCandidateLoad load, {
    int? session,
    String? preferIncidentId,
  }) async {
    final WidgetSnapshot? next = selectSnapshot(
      load.candidates,
      preferIncidentId: preferIncidentId,
    );
    if (next == null && !load.isKnownAllClear) {
      // Unknown or partial, not all-clear: leave the stored data untouched, and
      // do not refresh the platform widget either — nothing changed.
      return WidgetUpdateAction.noop;
    }
    return applySnapshot(next, session: session);
  }

  /// Writes [snapshot] (or clears when null) and refreshes the widget,
  /// returning the collapse action taken against the stored snapshot.
  ///
  /// Returns [WidgetUpdateAction.noop] — writing nothing — when the session
  /// that started the work has ended, or when [publishable] refuses the data.
  Future<WidgetUpdateAction> applySnapshot(
    WidgetSnapshot? snapshot, {
    int? session,
  }) async {
    // Read the epoch before the first await: capturing it later would let a
    // write that started before a logout present itself as a post-logout one.
    final int fenced = session ?? gate.epoch;
    final WidgetSnapshot? current = await readStored();
    final WidgetUpdateAction action = collapseWidgetUpdate(
      current: current,
      incoming: snapshot,
    );
    if (snapshot != null && !publishable(snapshot)) {
      // Sample/demo fixtures must not land in persistent widget storage, and a
      // refused write must not clear live data either.
      return WidgetUpdateAction.noop;
    }
    final WidgetSnapshot? effective = _carryKnownStamp(current, snapshot);
    final bool applied = await gate.run(() async {
      if (effective == null || action == WidgetUpdateAction.clear) {
        for (final String key in WidgetDataKeys.all) {
          await store.save<String>(key, null);
        }
        // In the app only a proven all-clear reaches this branch:
        // [applyCandidates] writes nothing for an unknown or partial feed.
        await store.save<String>(
          WidgetDataKeys.feedState,
          WidgetDataKeys.feedAllClear,
        );
      } else {
        await store.save<String>(WidgetDataKeys.feedState, null);
        final Map<String, Object?> data = effective.toWidgetData();
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
    }, session: fenced);
    // A fenced write changed nothing, so it must not report a collapse action.
    return applied ? action : WidgetUpdateAction.noop;
  }

  /// [incoming] with the stored snapshot's sync stamp when the authoritative
  /// row has none and both describe the same incident.
  ///
  /// Keeps a real last-fetch time from being dropped by a write that simply
  /// could not report one. Never crosses incidents: a stamp belongs to the
  /// data that was fetched, not to whatever replaced it on screen.
  static WidgetSnapshot? _carryKnownStamp(
    WidgetSnapshot? current,
    WidgetSnapshot? incoming,
  ) {
    if (incoming == null || current == null) {
      return incoming;
    }
    if (!incoming.freshnessUnknown || current.freshnessUnknown) {
      return incoming;
    }
    return current.incidentId == incoming.incidentId
        ? incoming.withSyncStamp(current.updatedAt)
        : incoming;
  }

  /// Reads the currently stored snapshot (null when never written/cleared).
  ///
  /// Reading never writes and never renews freshness: the stored stamp is
  /// returned exactly as written.
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
