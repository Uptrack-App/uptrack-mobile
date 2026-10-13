import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../push/live_activity_support.dart' show parseIosVersion;
import 'widget_snapshot.dart';
import 'widget_store.dart';

/// Dart → native channel that lists, starts and ends incident Live
/// Activities. Implemented by `UptrackLiveActivityBridge.swift`; no other
/// platform answers it.
const String kLiveActivityChannel = 'app.uptrack.mobile/live_activity';

/// How this device gets an incident Live Activity (plan item 5.3).
enum LiveActivityStartMode {
  /// No Live Activity: not iOS, iOS 16.0 (no ActivityKit), or an unknown
  /// version.
  none,

  /// iOS 16.1 to 17.1: the app starts the activity itself while it runs.
  /// The server then updates and ends it through the activity's own push
  /// token.
  local,

  /// iOS 17.2 and later: the server starts the activity with a push-to-start
  /// push. The app never starts one itself, so the two paths cannot both
  /// create an activity for one incident.
  remote,
}

/// Picks the [LiveActivityStartMode] for a platform and the
/// `Platform.operatingSystemVersion` text.
LiveActivityStartMode liveActivityStartMode({
  required TargetPlatform platform,
  required String osVersion,
}) {
  if (platform != TargetPlatform.iOS) {
    return LiveActivityStartMode.none;
  }
  final ({int major, int minor})? version = parseIosVersion(osVersion);
  if (version == null) {
    return LiveActivityStartMode.none;
  }
  int compare(int major, int minor) => version.major != major
      ? version.major.compareTo(major)
      : version.minor.compareTo(minor);
  if (compare(16, 1) < 0) {
    return LiveActivityStartMode.none;
  }
  if (compare(17, 2) < 0) {
    return LiveActivityStartMode.local;
  }
  return LiveActivityStartMode.remote;
}

/// One activity the native host reports as running.
@immutable
class RunningLiveActivity {
  const RunningLiveActivity({
    required this.id,
    required this.incidentId,
    this.status = 'ongoing',
  });

  /// Parses one `list` entry (`{id, incident_id, status?}`); null when the
  /// entry is malformed.
  static RunningLiveActivity? fromMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Object? id = raw['id'];
    final Object? incidentId = raw['incident_id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    if (incidentId is! String || incidentId.isEmpty) {
      return null;
    }
    final Object? status = raw['status'];
    return RunningLiveActivity(
      id: id,
      incidentId: incidentId,
      status: status is String && status.isNotEmpty ? status : 'ongoing',
    );
  }

  /// ActivityKit's activity id.
  final String id;

  /// `UptrackIncident.incidentId` of the activity.
  final String incidentId;

  /// Current `content-state.status`.
  final String status;
}

/// Arguments for one local start (`start` on [kLiveActivityChannel]).
@immutable
class LiveActivityStart {
  const LiveActivityStart({
    required this.incidentId,
    required this.monitorName,
    required this.title,
    required this.body,
    required this.status,
  });

  /// The content the server's `la_title_body(Opened)` would send, so a
  /// locally started activity looks the same as a remote one.
  factory LiveActivityStart.fromSnapshot(WidgetSnapshot snapshot) {
    final String monitor = snapshot.displayName;
    return LiveActivityStart(
      incidentId: snapshot.incidentId,
      monitorName: monitor,
      title: '🚨 $monitor is DOWN',
      body: 'Incident opened',
      status: 'ongoing',
    );
  }

  final String incidentId;
  final String monitorName;
  final String title;
  final String body;
  final String status;

  Map<String, Object?> toMap() => <String, Object?>{
    'incident_id': incidentId,
    'monitor_name': monitorName,
    'title': title,
    'body': body,
    'status': status,
  };
}

/// Why the app ends an activity itself.
enum LiveActivityEndReason {
  /// The incident resolved: show the resolved state, then let the system
  /// dismiss it.
  resolved,

  /// The incident is not in a complete feed any more: remove it now.
  gone,

  /// A second activity for an incident that already has one: remove it now.
  duplicate,
}

/// Arguments for one end (`end` on [kLiveActivityChannel]).
@immutable
class LiveActivityEnd {
  const LiveActivityEnd({
    required this.activityId,
    required this.incidentId,
    required this.reason,
  });

  final String activityId;
  final String incidentId;
  final LiveActivityEndReason reason;

  Map<String, Object?> toMap() => <String, Object?>{
    'activity_id': activityId,
    'incident_id': incidentId,
    'status': reason == LiveActivityEndReason.resolved ? 'resolved' : 'ended',
    'immediate': reason != LiveActivityEndReason.resolved,
  };
}

/// What one reconcile does.
@immutable
class LiveActivityPlan {
  const LiveActivityPlan({
    this.start = const <LiveActivityStart>[],
    this.end = const <LiveActivityEnd>[],
  });

  final List<LiveActivityStart> start;
  final List<LiveActivityEnd> end;

  bool get isEmpty => start.isEmpty && end.isEmpty;
}

/// Compares the running activities with the incident feed. Pure.
///
/// * An activity whose incident resolved ends with the resolved state. The
///   server also sends an `end` push, but that push can fail or arrive late.
/// * An activity whose incident is missing from a **complete** feed ends at
///   once. A partial or unknown feed proves nothing, so it ends nothing.
/// * A second activity for the same incident ends at once (one per
///   incident).
/// * In [LiveActivityStartMode.local] only, the incident the home widget
///   would show gets an activity when it has none. Demo data never does.
LiveActivityPlan planLiveActivities({
  required List<RunningLiveActivity> running,
  required WidgetCandidateLoad load,
  required LiveActivityStartMode mode,
}) {
  final Map<String, WidgetIncidentCandidate> byId =
      <String, WidgetIncidentCandidate>{
        for (final WidgetIncidentCandidate c in load.candidates) c.row.id: c,
      };
  final List<LiveActivityEnd> ends = <LiveActivityEnd>[];
  final Set<String> covered = <String>{};
  for (final RunningLiveActivity activity in running) {
    final WidgetIncidentCandidate? candidate = byId[activity.incidentId];
    LiveActivityEndReason? reason;
    if (candidate != null && !candidate.isEligible) {
      reason = LiveActivityEndReason.resolved;
    } else if (candidate == null && load.isComplete) {
      reason = LiveActivityEndReason.gone;
    } else if (covered.contains(activity.incidentId)) {
      reason = LiveActivityEndReason.duplicate;
    }
    if (reason == null) {
      covered.add(activity.incidentId);
    } else {
      ends.add(
        LiveActivityEnd(
          activityId: activity.id,
          incidentId: activity.incidentId,
          reason: reason,
        ),
      );
    }
  }
  final List<LiveActivityStart> starts = <LiveActivityStart>[];
  if (mode == LiveActivityStartMode.local) {
    final WidgetSnapshot? top = WidgetRefresher.selectSnapshot(load.candidates);
    if (top != null &&
        !covered.contains(top.incidentId) &&
        WidgetSampleGuard.allow(top)) {
      starts.add(LiveActivityStart.fromSnapshot(top));
    }
  }
  return LiveActivityPlan(start: starts, end: ends);
}

/// Native seam the tests fake.
abstract class LiveActivityHost {
  Future<List<RunningLiveActivity>> list();
  Future<void> start(LiveActivityStart request);
  Future<void> end(LiveActivityEnd request);
}

/// [LiveActivityHost] over [kLiveActivityChannel].
class MethodChannelLiveActivityHost implements LiveActivityHost {
  const MethodChannelLiveActivityHost({
    this.channel = const MethodChannel(kLiveActivityChannel),
  });

  final MethodChannel channel;

  /// Running activities; empty when the host has no such channel (Android,
  /// tests) or the call fails.
  @override
  Future<List<RunningLiveActivity>> list() async {
    try {
      final List<Object?>? raw = await channel.invokeListMethod<Object?>(
        'list',
      );
      return <RunningLiveActivity>[
        for (final Object? entry in raw ?? const <Object?>[])
          ?RunningLiveActivity.fromMap(entry),
      ];
    } on MissingPluginException {
      return const <RunningLiveActivity>[];
    }
  }

  @override
  Future<void> start(LiveActivityStart request) =>
      channel.invokeMethod<Object?>('start', request.toMap());

  @override
  Future<void> end(LiveActivityEnd request) =>
      channel.invokeMethod<Object?>('end', request.toMap());
}

/// Keeps incident Live Activities in line with the incident feed: the local
/// start on iOS 16.1 to 17.1 and the app-side end and de-duplication on all
/// supported versions.
///
/// Fenced by the same [WidgetWriteGate] as the home widget: a reconcile that
/// began before a logout starts nothing afterwards. (Logout itself ends every
/// activity natively in `clearSessionNotifications`.)
class LiveActivitySync {
  LiveActivitySync({
    required this.host,
    required this.loadCandidates,
    required this.mode,
    WidgetWriteGate? gate,
  }) : gate = gate ?? WidgetWriteGate.shared;

  final LiveActivityHost host;
  final CandidateLoader loadCandidates;
  final LiveActivityStartMode Function() mode;
  final WidgetWriteGate gate;

  /// Loads, plans and applies. Never throws; returns the plan it applied
  /// (empty when nothing ran).
  Future<LiveActivityPlan> reconcile() async {
    final int session = gate.epoch;
    final LiveActivityStartMode current = mode();
    if (current == LiveActivityStartMode.none) {
      return const LiveActivityPlan();
    }
    try {
      final WidgetCandidateLoad load = await loadCandidates();
      final List<RunningLiveActivity> running = await host.list();
      final LiveActivityPlan plan = planLiveActivities(
        running: running,
        load: load,
        mode: current,
      );
      if (plan.isEmpty) {
        return plan;
      }
      final bool applied = await gate.run(() async {
        for (final LiveActivityEnd end in plan.end) {
          await _bestEffort(() => host.end(end));
        }
        for (final LiveActivityStart start in plan.start) {
          await _bestEffort(() => host.start(start));
        }
      }, session: session);
      return applied ? plan : const LiveActivityPlan();
    } on Object {
      // Live Activities are a convenience; a failure must not break the
      // refresh path that called this.
      return const LiveActivityPlan();
    }
  }

  static Future<void> _bestEffort(Future<void> Function() call) async {
    try {
      await call();
    } on Object {
      // One failed start or end must not block the others.
    }
  }
}
