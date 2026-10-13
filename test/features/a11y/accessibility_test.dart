import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Tristate;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/util/date_format.dart';
import 'package:uptrack_mobile/api/models/check.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/api/models/monitor.dart';
import 'package:uptrack_mobile/api/models/monitor_analytics.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_controller.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_screen.dart';
import 'package:uptrack_mobile/features/incidents/incident_detail_screen.dart';
import 'package:uptrack_mobile/features/incidents/incidents_controller.dart';
import 'package:uptrack_mobile/features/incidents/incidents_screen.dart';
import 'package:uptrack_mobile/features/monitors/monitor_detail_controller.dart';
import 'package:uptrack_mobile/features/monitors/monitor_detail_screen.dart';
import 'package:uptrack_mobile/features/monitors/monitors_controller.dart';
import 'package:uptrack_mobile/features/monitors/monitors_screen.dart';
import 'package:uptrack_mobile/features/settings/settings_screen.dart';

Incident _incident(
  String id,
  String monitorName, {
  String? startedAt = '2026-09-26T00:00:00Z',
  String? acknowledgedAt,
  String? resolvedAt,
}) => Incident(
  id: id,
  monitorId: 'monitor-$id',
  status: 'open',
  insertedAt: '2026-09-26T00:00:00Z',
  monitorName: monitorName,
  startedAt: startedAt,
  acknowledgedAt: acknowledgedAt,
  resolvedAt: resolvedAt,
);

Monitor _monitor(String id, String name) => Monitor(
  id: id,
  name: name,
  url: 'https://$id.example.com',
  monitorType: 'http',
  status: 'up',
  interval: 60,
  timeout: 10,
  confirmationWindow: '1m',
  regionsRequired: 'any',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-02T00:00:00Z',
  uptimePercentage: 99.9,
);

class FakeDashboardRepository implements DashboardRepository {
  FakeDashboardRepository({required this.onLoad});

  Future<DashboardData> Function() onLoad;

  @override
  Future<DashboardData> load() => onLoad();
}

class FakeMonitorsRepository implements MonitorsRepository {
  FakeMonitorsRepository({required this.onLoad});

  Future<MonitorsData> Function() onLoad;

  @override
  Future<MonitorsData> load() => onLoad();
}

class FakeMonitorDetailRepository implements MonitorDetailRepository {
  FakeMonitorDetailRepository({required this.onLoad});

  Future<MonitorDetailData> Function(String id, int days) onLoad;

  @override
  Future<MonitorDetailData> load(String id, {required int days}) =>
      onLoad(id, days);
}

class FakeIncidentsRepository implements IncidentsRepository {
  FakeIncidentsRepository({required this.onLoad});

  Future<IncidentsData> Function() onLoad;

  @override
  Future<IncidentsData> load() => onLoad();
}

class FakeIncidentDetailRepository implements IncidentDetailRepository {
  FakeIncidentDetailRepository({required this.onLoad, this.onAck});

  Future<IncidentDetailData> Function(String id) onLoad;

  /// Optional separate acknowledge handler; defaults to [onLoad]. A test that
  /// needs the acknowledgement to stay in flight (the busy button state)
  /// passes a handler whose future never completes.
  Future<IncidentDetailData> Function(String id)? onAck;

  @override
  Future<IncidentDetailData> load(String id) => onLoad(id);

  @override
  Future<IncidentDetailData> acknowledge(String id) =>
      onAck?.call(id) ?? onLoad(id);

  @override
  Future<EscalateResult> escalate(String id) async =>
      const EscalateResult(escalated: true, stepsFired: 2);

  @override
  Future<SnoozeResult> snooze(String monitorId) async =>
      const SnoozeResult(snoozedUntil: '2026-09-26T01:00:00Z');
}

/// Fake [HttpClientAdapter] for the settings screen (same pattern as the
/// settings tests).
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Map<String, Object?> json) {
  return ResponseBody.fromString(
    jsonEncode(json),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );
}

void main() {
  group('accessibility semantics', () {
    testWidgets('dashboard stat tiles, uptime, and incident rows', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardRepositoryProvider.overrideWithValue(
              FakeDashboardRepository(
                onLoad: () async => DashboardData(
                  totalMonitors: 3,
                  loadedMonitors: 3,
                  totalMonitorsKnown: true,
                  countsByStatus: const <String, int>{'up': 2, 'down': 1},
                  averageUptime: 99.9,
                  incidents: partitionIncidents(<Incident>[
                    _incident('i1', 'Homepage'),
                  ]),
                  offline: false,
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: DashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Up monitors: 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Down monitors: 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Total monitors: 3'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Average uptime 99.9% across 3 monitors'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Incident Homepage, status Open'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('monitor list rows expose name + status', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monitorsRepositoryProvider.overrideWithValue(
              FakeMonitorsRepository(
                onLoad: () async => MonitorsData(
                  monitors: <Monitor>[_monitor('a', 'Homepage')],
                  offline: false,
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: MonitorsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Monitor Homepage, status Up, 99.9% uptime'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('monitor detail header, chart summary, and checks', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monitorDetailRepositoryProvider.overrideWithValue(
              FakeMonitorDetailRepository(
                onLoad: (String id, int days) async => MonitorDetailData(
                  monitor: _monitor('m1', 'Homepage'),
                  checks: const <MonitorCheck>[
                    MonitorCheck(
                      status: 'up',
                      responseTime: 120,
                      statusCode: 200,
                      checkedAt: '2026-09-26T00:00:00Z',
                    ),
                  ],
                  analytics: const MonitorAnalytics(
                    monitorId: 'm1',
                    periodDays: 7,
                    responseTimes: <ResponseTimePoint>[
                      ResponseTimePoint(
                        timestamp: 1729900000,
                        responseTime: 123.5,
                      ),
                      ResponseTimePoint(
                        timestamp: 1729903600,
                        responseTime: 140.0,
                      ),
                    ],
                    percentiles: ResponsePercentiles(
                      p50: 120,
                      p95: 300,
                      p99: 500,
                    ),
                  ),
                  offline: false,
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: MonitorDetailScreen(monitorId: 'm1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Monitor Homepage'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Last 7 days. 2 measured samples. '
          'p50 120 ms · p95 300 ms · p99 500 ms',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.bySemanticsLabel('Check Up, 120 ms, HTTP 200'),
        200,
      );
      expect(
        find.bySemanticsLabel('Check Up, 120 ms, HTTP 200'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('incident feed rows expose name + state', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            incidentsRepositoryProvider.overrideWithValue(
              FakeIncidentsRepository(
                onLoad: () async => IncidentsData(
                  incidents: <Incident>[_incident('a', 'Homepage')],
                  offline: false,
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: IncidentsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Incident Homepage, Open'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('incident detail header, acknowledge action, and updates', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            incidentDetailRepositoryProvider.overrideWithValue(
              FakeIncidentDetailRepository(
                onLoad: (String id) async => IncidentDetailData(
                  incident: _incident('i1', 'Homepage'),
                  updates: <IncidentUpdate>[
                    IncidentUpdate(
                      id: 7,
                      status: 'investigating',
                      title: 'Looking into it',
                      postedAt: '2026-09-26T00:05:00Z',
                    ),
                  ],
                  offline: false,
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: IncidentDetailScreen(incidentId: 'i1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Incident Homepage, Open'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Acknowledge incident Homepage'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Escalate incident Homepage'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Snooze your mobile alerts for 1 hour on Homepage',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.bySemanticsLabel('Update Looking into it, Investigating'),
        200,
      );
      expect(
        find.bySemanticsLabel('Update Looking into it, Investigating'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets(
      'incident response actions are named button nodes in every state',
      (WidgetTester tester) async {
        // The incident-specific label must sit on the actionable node itself:
        // asserting a label found somewhere in the tree would pass even if the
        // announcement were attached to a wrapper with no role, no tap action
        // and no enabled state.
        const String ackLabel = 'Acknowledge incident Homepage';
        const String escalateLabel = 'Escalate incident Homepage';
        const String snoozeLabel =
            'Snooze your mobile alerts for 1 hour on Homepage';
        final SemanticsHandle handle = tester.ensureSemantics();

        Future<void> pumpDetail({required bool offline}) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                incidentDetailRepositoryProvider.overrideWithValue(
                  FakeIncidentDetailRepository(
                    onLoad: (String id) async => IncidentDetailData(
                      incident: _incident('i1', 'Homepage'),
                      updates: const <IncidentUpdate>[],
                      offline: offline,
                    ),
                    // Never completes: the acknowledgement stays in flight, so
                    // the busy state can be asserted below.
                    onAck: (String id) =>
                        Completer<IncidentDetailData>().future,
                  ),
                ),
              ],
              child: const MaterialApp(
                home: IncidentDetailScreen(incidentId: 'i1'),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        SemanticsNode nodeFor(String label) =>
            tester.getSemantics(find.bySemanticsLabel(label));

        // Flutter expresses "is a button" as a flag rather than a role, so the
        // assertion is on that flag together with the node's own action and
        // enabled state: an announcement on a wrapper would have none of them.
        void expectEnabledButton(String label) {
          final SemanticsNode node = nodeFor(label);
          expect(node.label, label);
          expect(
            node.flagsCollection.isButton,
            isTrue,
            reason: '"$label" must be announced as a button',
          );
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
            reason: '"$label" must be tappable',
          );
          expect(
            node.flagsCollection.isEnabled,
            Tristate.isTrue,
            reason: '"$label" must report itself as enabled',
          );
        }

        void expectUnavailableButton(String label) {
          final SemanticsNode node = nodeFor(label);
          expect(node.label, label);
          expect(node.flagsCollection.isButton, isTrue);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isFalse,
            reason: '"$label" must not offer a tap it ignores',
          );
          expect(
            node.flagsCollection.isEnabled,
            Tristate.isFalse,
            reason: '"$label" must report itself as disabled',
          );
        }

        // -- enabled: all three actions are live ---------------------------
        await pumpDetail(offline: false);
        for (final String label in <String>[
          ackLabel,
          escalateLabel,
          snoozeLabel,
        ]) {
          expectEnabledButton(label);
        }
        // The tap actually reaches the action.
        await tester.tap(find.bySemanticsLabel(ackLabel));
        await tester.pump();

        // -- busy: the acknowledged action is in flight ---------------------
        final SemanticsNode busyAck = nodeFor(ackLabel);
        expect(busyAck.label, ackLabel);
        expect(busyAck.flagsCollection.isButton, isTrue);
        expect(
          busyAck.getSemanticsData().hasAction(SemanticsAction.tap),
          isFalse,
          reason: 'a busy action blocks taps but stays announced',
        );
        expect(
          busyAck.flagsCollection.isLiveRegion,
          isTrue,
          reason: 'the busy state must be announced without a tap',
        );
        expect(
          busyAck.value,
          'In progress',
          reason: 'the busy state is reported on the button node',
        );
        // The other actions are blocked while the slot is taken.
        expectUnavailableButton(escalateLabel);
        expectUnavailableButton(snoozeLabel);

        handle.dispose();
      },
    );

    testWidgets('offline response actions stay named disabled buttons', (
      WidgetTester tester,
    ) async {
      const String ackLabel = 'Acknowledge incident Homepage';
      const String escalateLabel = 'Escalate incident Homepage';
      const String snoozeLabel =
          'Snooze your mobile alerts for 1 hour on Homepage';
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            incidentDetailRepositoryProvider.overrideWithValue(
              FakeIncidentDetailRepository(
                onLoad: (String id) async => IncidentDetailData(
                  incident: _incident('i1', 'Homepage'),
                  updates: const <IncidentUpdate>[],
                  offline: true,
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: IncidentDetailScreen(incidentId: 'i1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final String label in <String>[
        ackLabel,
        escalateLabel,
        snoozeLabel,
      ]) {
        final SemanticsNode node = tester.getSemantics(
          find.bySemanticsLabel(label),
        );
        expect(node.label, label);
        expect(
          node.flagsCollection.isButton,
          isTrue,
          reason: 'a disabled action is still announced as a button',
        );
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.tap),
          isFalse,
          reason: '"$label" is unreachable offline',
        );
        expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      }
      handle.dispose();
    });

    testWidgets('settings device rows and revoke actions', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final AuthTokenHolder holder = AuthTokenHolder()..token = 'udt_test';
      final ProviderContainer container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
          authTokenHolderProvider.overrideWithValue(holder),
          dioProvider.overrideWithValue(
            buildAppDio(
              holder: holder,
              onUnauthorized: () {},
              adapter: FakeAdapter((RequestOptions options) async {
                final String path = options.path;
                if (path == kGetMePath) {
                  return jsonResponse(<String, Object?>{
                    'user': <String, Object?>{
                      'id': 'u1',
                      'name': 'Ada Lovelace',
                      'email': 'ada@example.com',
                      'provider': null,
                      'role': 'owner',
                      'is_admin': true,
                      'preferred_locale': null,
                      'inserted_at': '2026-01-01T00:00:00Z',
                    },
                    'organization': <String, Object?>{
                      'id': 'o1',
                      'name': 'Acme',
                      'slug': 'acme',
                      'plan': 'pro',
                      'features_enabled': true,
                    },
                  });
                }
                if (path == kNotificationPreferencesPath) {
                  return jsonResponse(<String, Object?>{
                    'user_id': 'u1',
                    'severity_overrides': <String, Object?>{'info': 'active'},
                    'quiet_hours_start': null,
                    'quiet_hours_end': null,
                    'mobile_push_enabled': true,
                    'digest_p3': false,
                  });
                }
                if (path == kBillingSubscriptionPath) {
                  return jsonResponse(<String, Object?>{
                    'data': null,
                    'plan': 'free',
                  });
                }
                if (path == kDeviceTokensPath) {
                  return jsonResponse(<String, Object?>{
                    'data': <Object?>[
                      <String, Object?>{
                        'id': '11111111-1111-4111-8111-111111111111',
                        'label': 'Pixel 9',
                        'created_at': '2026-01-01T00:00:00',
                        'last_used_at': null,
                      },
                    ],
                  });
                }
                return jsonResponse(<String, Object?>{'ok': true});
              }),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final Finder list = find.byKey(const ValueKey<String>('settings-list'));
      final Finder deviceRow = find.bySemanticsLabel(
        'Device Pixel 9, signed in ${formatTimestamp('2026-01-01T00:00:00')}',
      );
      for (int i = 0; i < 15 && deviceRow.evaluate().isEmpty; i++) {
        await tester.drag(list, const Offset(0, -500));
        await tester.pumpAndSettle();
      }
      expect(deviceRow, findsOneWidget);
      // The revoke icon button keeps its tooltip as its accessible name.
      expect(find.byTooltip('Revoke Pixel 9'), findsOneWidget);
      // Severity rows announce their interruption mapping. They sit above
      // the devices section, so scroll back until the node is onstage: the
      // settings list (danger zone included) is longer than one viewport.
      final Finder severityRow = find.bySemanticsLabel(
        'Severity info interruption: active',
      );
      for (
        int i = 0;
        i < 15 && severityRow.hitTestable().evaluate().isEmpty;
        i++
      ) {
        await tester.drag(list, const Offset(0, 500));
        await tester.pumpAndSettle();
      }
      expect(severityRow, findsOneWidget);
      handle.dispose();
    });
  });
}
