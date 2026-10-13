import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/widgets/live_activity_sync.dart';
import 'package:uptrack_mobile/widgets/widget_snapshot.dart';
import 'package:uptrack_mobile/widgets/widget_store.dart';

import 'widget_test_support.dart';

/// Records host calls; [running] is what `list` reports.
class FakeLiveActivityHost implements LiveActivityHost {
  FakeLiveActivityHost({
    List<RunningLiveActivity>? running,
    this.failAll = false,
  }) : running = running ?? <RunningLiveActivity>[];

  final List<RunningLiveActivity> running;
  final bool failAll;
  final List<LiveActivityStart> started = <LiveActivityStart>[];
  final List<LiveActivityEnd> ended = <LiveActivityEnd>[];

  @override
  Future<List<RunningLiveActivity>> list() async {
    if (failAll) {
      throw PlatformException(code: 'boom');
    }
    return List<RunningLiveActivity>.of(running);
  }

  @override
  Future<void> start(LiveActivityStart request) async {
    if (failAll) {
      throw PlatformException(code: 'boom');
    }
    started.add(request);
  }

  @override
  Future<void> end(LiveActivityEnd request) async {
    if (failAll) {
      throw PlatformException(code: 'boom');
    }
    ended.add(request);
  }
}

WidgetCandidateLoad completeLoad(List<WidgetIncidentCandidate> candidates) =>
    WidgetCandidateLoad(
      candidates: candidates,
      syncedAt: DateTime.utc(2026, 9, 27, 10, 5),
    );

WidgetCandidateLoad partialLoad(List<WidgetIncidentCandidate> candidates) =>
    WidgetCandidateLoad(candidates: candidates);

RunningLiveActivity running(String id, String incidentId) =>
    RunningLiveActivity(id: id, incidentId: incidentId);

void main() {
  group('liveActivityStartMode (5.3)', () {
    LiveActivityStartMode mode(
      String version, {
      TargetPlatform platform = TargetPlatform.iOS,
    }) => liveActivityStartMode(platform: platform, osVersion: version);

    test('iOS 16.0 has no ActivityKit: no Live Activity at all', () {
      expect(mode('Version 16.0 (Build 20A362)'), LiveActivityStartMode.none);
      expect(mode('Version 16.0.3 (Build 20A392)'), LiveActivityStartMode.none);
    });

    test('iOS 16.1 to 17.1 starts locally while the app runs', () {
      expect(mode('Version 16.1 (Build 20B82)'), LiveActivityStartMode.local);
      expect(mode('Version 16.7 (Build 20H19)'), LiveActivityStartMode.local);
      expect(mode('Version 17.0 (Build 21A329)'), LiveActivityStartMode.local);
      expect(mode('Version 17.1 (Build 21B74)'), LiveActivityStartMode.local);
    });

    test('iOS 17.2 and later is started remotely (push-to-start)', () {
      expect(mode('Version 17.2 (Build 21C62)'), LiveActivityStartMode.remote);
      expect(
        mode('Version 18.0 (Build 22A3354)'),
        LiveActivityStartMode.remote,
      );
      expect(mode('Version 27.0 (Build 25A1)'), LiveActivityStartMode.remote);
    });

    test('unknown versions and other platforms never start anything', () {
      expect(mode('???'), LiveActivityStartMode.none);
      expect(
        mode('Version 18.0', platform: TargetPlatform.android),
        LiveActivityStartMode.none,
      );
    });
  });

  group('RunningLiveActivity.fromMap', () {
    test('reads the native list entry', () {
      final RunningLiveActivity? activity = RunningLiveActivity.fromMap(
        <Object?, Object?>{
          'id': 'act-1',
          'incident_id': 'inc-1',
          'status': 'ongoing',
        },
      );
      expect(activity?.id, 'act-1');
      expect(activity?.incidentId, 'inc-1');
      expect(activity?.status, 'ongoing');
    });

    test('drops malformed entries instead of throwing', () {
      expect(RunningLiveActivity.fromMap(null), isNull);
      expect(RunningLiveActivity.fromMap('x'), isNull);
      expect(
        RunningLiveActivity.fromMap(<Object?, Object?>{'id': 'a'}),
        isNull,
      );
      expect(
        RunningLiveActivity.fromMap(<Object?, Object?>{
          'id': '',
          'incident_id': 'inc-1',
        }),
        isNull,
      );
    });
  });

  group('planLiveActivities', () {
    test('local mode starts the newest open incident once', () {
      final LiveActivityPlan plan = planLiveActivities(
        running: const <RunningLiveActivity>[],
        load: completeLoad(<WidgetIncidentCandidate>[
          widgetCandidate('old', insertedAt: '2026-09-27T09:00:00Z'),
          widgetCandidate('new', insertedAt: '2026-09-27T10:00:00Z'),
        ]),
        mode: LiveActivityStartMode.local,
      );
      expect(plan.start, hasLength(1));
      final LiveActivityStart start = plan.start.single;
      expect(start.incidentId, 'new');
      expect(start.monitorName, 'Monitor new');
      // Mirrors the server's `la_title_body(Opened)` content state.
      expect(start.title, '🚨 Monitor new is DOWN');
      expect(start.body, 'Incident opened');
      expect(start.status, 'ongoing');
      expect(start.toMap(), <String, Object?>{
        'incident_id': 'new',
        'monitor_name': 'Monitor new',
        'title': '🚨 Monitor new is DOWN',
        'body': 'Incident opened',
        'status': 'ongoing',
      });
      expect(plan.end, isEmpty);
    });

    test('no duplicate: an activity for the incident already runs', () {
      final LiveActivityPlan plan = planLiveActivities(
        running: <RunningLiveActivity>[running('act-1', 'inc-1')],
        load: completeLoad(<WidgetIncidentCandidate>[widgetCandidate('inc-1')]),
        mode: LiveActivityStartMode.local,
      );
      expect(plan.isEmpty, isTrue);
    });

    test('remote and none modes never start locally', () {
      for (final LiveActivityStartMode mode in <LiveActivityStartMode>[
        LiveActivityStartMode.remote,
        LiveActivityStartMode.none,
      ]) {
        final LiveActivityPlan plan = planLiveActivities(
          running: const <RunningLiveActivity>[],
          load: completeLoad(<WidgetIncidentCandidate>[
            widgetCandidate('inc-1'),
          ]),
          mode: mode,
        );
        expect(plan.start, isEmpty, reason: mode.name);
      }
    });

    test('demo fixtures never start a Live Activity', () {
      final LiveActivityPlan plan = planLiveActivities(
        running: const <RunningLiveActivity>[],
        load: completeLoad(<WidgetIncidentCandidate>[
          widgetCandidate('demo-incident'),
        ]),
        mode: LiveActivityStartMode.local,
      );
      expect(plan.start, isEmpty);
    });

    test('a resolved incident ends its activity with the resolved state', () {
      final LiveActivityPlan plan = planLiveActivities(
        running: <RunningLiveActivity>[running('act-1', 'inc-1')],
        load: partialLoad(<WidgetIncidentCandidate>[
          widgetCandidate('inc-1', status: 'resolved'),
        ]),
        mode: LiveActivityStartMode.remote,
      );
      expect(plan.end, hasLength(1));
      expect(plan.end.single.activityId, 'act-1');
      expect(plan.end.single.reason, LiveActivityEndReason.resolved);
      expect(plan.end.single.toMap(), <String, Object?>{
        'activity_id': 'act-1',
        'incident_id': 'inc-1',
        'status': 'resolved',
        'immediate': false,
      });
    });

    test('resolved_at alone also counts as resolved', () {
      final LiveActivityPlan plan = planLiveActivities(
        running: <RunningLiveActivity>[running('act-1', 'inc-1')],
        load: partialLoad(<WidgetIncidentCandidate>[
          widgetCandidate('inc-1', resolvedAt: '2026-09-27T10:30:00Z'),
        ]),
        mode: LiveActivityStartMode.remote,
      );
      expect(plan.end.single.reason, LiveActivityEndReason.resolved);
    });

    test('an incident missing from a complete feed ends at once', () {
      final LiveActivityPlan plan = planLiveActivities(
        running: <RunningLiveActivity>[running('act-1', 'gone')],
        load: completeLoad(<WidgetIncidentCandidate>[widgetCandidate('inc-1')]),
        mode: LiveActivityStartMode.remote,
      );
      expect(plan.end.single.activityId, 'act-1');
      expect(plan.end.single.reason, LiveActivityEndReason.gone);
      expect(plan.end.single.toMap()['immediate'], isTrue);
    });

    test('an incident missing from a partial feed is left alone', () {
      final LiveActivityPlan plan = planLiveActivities(
        running: <RunningLiveActivity>[running('act-1', 'unknown')],
        load: partialLoad(const <WidgetIncidentCandidate>[]),
        mode: LiveActivityStartMode.remote,
      );
      expect(plan.isEmpty, isTrue);
    });

    test('two activities for one incident: the extra one ends', () {
      final LiveActivityPlan plan = planLiveActivities(
        running: <RunningLiveActivity>[
          running('act-1', 'inc-1'),
          running('act-2', 'inc-1'),
        ],
        load: completeLoad(<WidgetIncidentCandidate>[widgetCandidate('inc-1')]),
        mode: LiveActivityStartMode.local,
      );
      expect(plan.start, isEmpty);
      expect(plan.end, hasLength(1));
      expect(plan.end.single.activityId, 'act-2');
      expect(plan.end.single.reason, LiveActivityEndReason.duplicate);
    });
  });

  group('LiveActivitySync.reconcile', () {
    test('runs the plan against the host', () async {
      final FakeLiveActivityHost host = FakeLiveActivityHost(
        running: <RunningLiveActivity>[running('act-old', 'inc-old')],
      );
      final LiveActivitySync sync = LiveActivitySync(
        host: host,
        loadCandidates: () async => completeLoad(<WidgetIncidentCandidate>[
          widgetCandidate('inc-old', status: 'resolved'),
          widgetCandidate('inc-new'),
        ]),
        mode: () => LiveActivityStartMode.local,
        gate: WidgetWriteGate(),
      );
      await sync.reconcile();
      expect(host.ended.single.activityId, 'act-old');
      expect(host.started.single.incidentId, 'inc-new');
    });

    test('a logout during the load starts nothing', () async {
      final WidgetWriteGate gate = WidgetWriteGate();
      final Completer<WidgetCandidateLoad> load =
          Completer<WidgetCandidateLoad>();
      final FakeLiveActivityHost host = FakeLiveActivityHost();
      final LiveActivitySync sync = LiveActivitySync(
        host: host,
        loadCandidates: () => load.future,
        mode: () => LiveActivityStartMode.local,
        gate: gate,
      );
      final Future<void> pending = sync.reconcile();
      await gate.endSession(clear: () async {});
      load.complete(
        completeLoad(<WidgetIncidentCandidate>[widgetCandidate('inc-1')]),
      );
      await pending;
      expect(host.started, isEmpty);
    });

    test('mode none skips the host entirely', () async {
      final FakeLiveActivityHost host = FakeLiveActivityHost(failAll: true);
      final LiveActivitySync sync = LiveActivitySync(
        host: host,
        loadCandidates: () async => throw StateError('must not load'),
        mode: () => LiveActivityStartMode.none,
        gate: WidgetWriteGate(),
      );
      expect((await sync.reconcile()).isEmpty, isTrue);
    });

    test('host and loader failures never escape', () async {
      final LiveActivitySync failingHost = LiveActivitySync(
        host: FakeLiveActivityHost(failAll: true),
        loadCandidates: () async =>
            completeLoad(<WidgetIncidentCandidate>[widgetCandidate('inc-1')]),
        mode: () => LiveActivityStartMode.local,
        gate: WidgetWriteGate(),
      );
      await failingHost.reconcile();
      final LiveActivitySync failingLoad = LiveActivitySync(
        host: FakeLiveActivityHost(),
        loadCandidates: () async => throw StateError('db closed'),
        mode: () => LiveActivityStartMode.local,
        gate: WidgetWriteGate(),
      );
      expect((await failingLoad.reconcile()).isEmpty, isTrue);
    });
  });

  group('MethodChannelLiveActivityHost', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const MethodChannel channel = MethodChannel(kLiveActivityChannel);
    final List<MethodCall> calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            calls.add(call);
            if (call.method == 'list') {
              return <Object?>[
                <Object?, Object?>{'id': 'act-1', 'incident_id': 'inc-1'},
                'garbage',
              ];
            }
            return 'ok';
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('speaks the native contract', () async {
      const MethodChannelLiveActivityHost host =
          MethodChannelLiveActivityHost();
      final List<RunningLiveActivity> list = await host.list();
      expect(list.single.incidentId, 'inc-1');
      await host.start(
        const LiveActivityStart(
          incidentId: 'inc-1',
          monitorName: 'API',
          title: 't',
          body: 'b',
          status: 'ongoing',
        ),
      );
      await host.end(
        const LiveActivityEnd(
          activityId: 'act-1',
          incidentId: 'inc-1',
          reason: LiveActivityEndReason.duplicate,
        ),
      );
      expect(calls.map((MethodCall c) => c.method), <String>[
        'list',
        'start',
        'end',
      ]);
      expect(
        (calls[1].arguments as Map<Object?, Object?>)['incident_id'],
        'inc-1',
      );
      expect(
        (calls[2].arguments as Map<Object?, Object?>)['immediate'],
        isTrue,
      );
    });

    test('a host without the channel lists nothing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      const MethodChannelLiveActivityHost host =
          MethodChannelLiveActivityHost();
      expect(await host.list(), isEmpty);
    });
  });
}
