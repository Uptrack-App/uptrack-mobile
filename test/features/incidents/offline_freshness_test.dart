/// R4 UI: honest offline/freshness copy on the screens a bounded offline
/// context reaches — incident detail, the incident feed and the dashboard.
///
/// Drives the real widgets with data shaped exactly as the controller produces
/// it, so the copy under test is the copy the app shows. No golden images and
/// no tolerance-based assertions: every claim is a `find.text` on the exact
/// string a person would read.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart'
    show EscalateResult, SnoozeResult;
import 'package:uptrack_mobile/features/dashboard/dashboard_controller.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_screen.dart';
import 'package:uptrack_mobile/features/incidents/incident_detail_screen.dart';
import 'package:uptrack_mobile/features/incidents/incidents_controller.dart';
import 'package:uptrack_mobile/features/incidents/incidents_screen.dart';
import 'package:uptrack_mobile/theme/app_theme.dart';
import 'package:uptrack_mobile/util/date_format.dart';

/// A known instant, so the rendered timestamp is a literal string rather than
/// something formatted at test time.
final DateTime syncedAt = DateTime.utc(2026, 10, 4, 21, 10);

String get syncedText => formatInstant(syncedAt);

Incident _incident({
  String id = 'i1',
  String monitorName = 'Homepage',
  String? resolvedAt,
  String? acknowledgedAt,
}) => Incident(
  id: id,
  monitorId: 'm1',
  status: 'ongoing',
  insertedAt: '2026-10-04T20:00:00Z',
  monitorName: monitorName,
  startedAt: '2026-10-04T20:00:00Z',
  resolvedAt: resolvedAt,
  acknowledgedAt: acknowledgedAt,
);

IncidentUpdate _update(int id, String title) => IncidentUpdate(
  id: id,
  status: 'investigating',
  title: title,
  postedAt: '2026-10-04T20:05:00Z',
);

class _DetailRepo implements IncidentDetailRepository {
  _DetailRepo(this.data);

  IncidentDetailData data;

  /// What the server confirms for an acknowledgement. Null answers with [data].
  IncidentDetailData? acknowledgeResult;

  /// What a *load* answers once an acknowledgement has been sent, i.e. the
  /// server's post-action state. Null answers with [data].
  ///
  /// Only consulted after an acknowledgement: the screen has to start on the
  /// pre-action incident, with its controls enabled, and the invalidation the
  /// success path performs then picks this up. Returning it from the very first
  /// load would disable the Acknowledge control before it is ever tapped.
  IncidentDetailData? loadAfterAcknowledge;

  int acknowledges = 0;

  @override
  Future<IncidentDetailData> load(String id) async {
    final IncidentDetailData? after = loadAfterAcknowledge;
    if (acknowledges > 0 && after != null) {
      return after;
    }
    return data;
  }

  @override
  Future<IncidentDetailData> acknowledge(String id) async {
    acknowledges++;
    return acknowledgeResult ?? data;
  }

  @override
  Future<EscalateResult> escalate(String id) async =>
      const EscalateResult(escalated: true, stepsFired: 1);

  @override
  Future<SnoozeResult> snooze(String monitorId) async =>
      const SnoozeResult(snoozedUntil: '2026-10-04T22:00:00Z');
}

class _FeedRepo implements IncidentsRepository {
  _FeedRepo(this.data);

  IncidentsData data;

  @override
  Future<IncidentsData> load() async => data;
}

class _DashboardRepo implements DashboardRepository {
  _DashboardRepo(this.data);

  DashboardData data;

  @override
  Future<DashboardData> load() async => data;
}

/// Text shown for a snapshot whose sync time is unknown, kept next to the
/// assertions rather than hard-coded per test.
const String unknownStamp = 'Last sync time unavailable.';

Future<void> pumpDetail(WidgetTester tester, IncidentDetailData data) =>
    _pumpWith(tester, _DetailRepo(data));

/// Private because it takes [_DetailRepo]: a public signature naming a private
/// type is an API the rest of the app cannot call.
Future<void> _pumpWith(WidgetTester tester, _DetailRepo repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [incidentDetailRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: IncidentDetailScreen(incidentId: 'i1')),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpFeed(WidgetTester tester, IncidentsData data) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        incidentsRepositoryProvider.overrideWithValue(_FeedRepo(data)),
      ],
      child: const MaterialApp(home: IncidentsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpDashboard(WidgetTester tester, DashboardData data) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dashboardRepositoryProvider.overrideWithValue(_DashboardRepo(data)),
      ],
      child: const MaterialApp(home: DashboardScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

DashboardData _dashboard({bool offline = false, DateTime? synced}) =>
    DashboardData(
      totalMonitors: 2,
      loadedMonitors: 2,
      totalMonitorsKnown: true,
      countsByStatus: const <String, int>{'up': 2},
      averageUptime: 99.9,
      offline: offline,
      syncedAt: synced,
      incidents: partitionIncidents(<Incident>[_incident()]),
    );

void main() {
  setUp(() {
    // Pinned per test, not once for the file: `displayTimeZone` is a mutable
    // global that other suites restore, so a single setUpAll would leave every
    // later test formatting timestamps in whatever zone ran before it. The
    // rendered stamp is then the literal UTC string on any machine.
    displayTimeZone = (DateTime t) => t.toUtc();
  });

  tearDown(() {
    displayTimeZone = (DateTime t) => t.toLocal();
  });

  group('incident detail freshness', () {
    testWidgets('an online read shows the real sync time', (
      WidgetTester tester,
    ) async {
      await pumpDetail(
        tester,
        IncidentDetailData(
          incident: _incident(),
          updates: <IncidentUpdate>[_update(1, 'Looking into it')],
          offline: false,
          summarySyncedAt: syncedAt,
          updatesSyncedAt: syncedAt,
        ),
      );

      expect(find.text('Last synced $syncedText'), findsOneWidget);
      expect(
        find.textContaining('Updates last synced'),
        findsNothing,
        reason:
            'the updates were read in the same write as the summary, so a '
            'second timestamp would say nothing new',
      );
      expect(find.text('Looking into it'), findsOneWidget);
    });

    testWidgets('an offline read keeps its own updates timestamp', (
      WidgetTester tester,
    ) async {
      final DateTime summaryAt = DateTime.utc(2026, 10, 4, 21, 12);
      final DateTime updatesAt = DateTime.utc(2026, 10, 4, 20, 5);
      await pumpDetail(
        tester,
        IncidentDetailData(
          incident: _incident(),
          updates: <IncidentUpdate>[_update(1, 'Looking into it')],
          offline: true,
          summarySyncedAt: summaryAt,
          updatesSyncedAt: updatesAt,
        ),
      );

      expect(find.text('Offline — showing cached data'), findsOneWidget);
      expect(
        find.text('Last synced ${formatInstant(summaryAt)}'),
        findsOneWidget,
      );
      expect(
        find.text('Updates last synced ${formatInstant(updatesAt)}'),
        findsOneWidget,
        reason:
            'the updates were last read earlier than the summary, and the screen '
            'says so rather than implying one time for both',
      );
    });

    testWidgets('an unknown sync time is stated, not omitted', (
      WidgetTester tester,
    ) async {
      await pumpDetail(
        tester,
        IncidentDetailData(
          incident: _incident(),
          updates: const <IncidentUpdate>[],
          offline: true,
        ),
      );

      expect(find.text(unknownStamp), findsOneWidget);
      expect(
        find.textContaining('Last synced'),
        findsNothing,
        reason: 'no timestamp may be claimed when none is known',
      );
    });

    testWidgets('a saved empty snapshot and no snapshot read differently', (
      WidgetTester tester,
    ) async {
      // Saved, and genuinely empty: the server said there are none.
      await pumpDetail(
        tester,
        IncidentDetailData(
          incident: _incident(),
          updates: const <IncidentUpdate>[],
          offline: true,
          summarySyncedAt: syncedAt,
          updatesSyncedAt: syncedAt,
        ),
      );
      expect(find.text('No updates yet.'), findsOneWidget);
      expect(find.text('No saved updates for offline viewing.'), findsNothing);

      // Nothing saved: the app does not know, and must not say "none".
      await pumpDetail(
        tester,
        IncidentDetailData(
          incident: _incident(),
          updates: const <IncidentUpdate>[],
          offline: true,
          summarySyncedAt: syncedAt,
        ),
      );
      expect(
        find.text('No saved updates for offline viewing.'),
        findsOneWidget,
      );
      expect(find.text('No updates yet.'), findsNothing);
    });

    testWidgets('an unsaved acknowledgement is never called saved', (
      WidgetTester tester,
    ) async {
      await pumpDetail(
        tester,
        IncidentDetailData(
          incident: _incident(acknowledgedAt: '2026-10-04T21:00:00Z'),
          updates: <IncidentUpdate>[_update(2, 'Pausing alerts')],
          offline: false,
          summarySyncedAt: syncedAt,
          updatesSyncedAt: syncedAt,
          savedOffline: false,
        ),
      );

      expect(
        find.text('Response actions need a connection.'),
        findsNothing,
        reason: 'the screen is online; only the local save failed',
      );
      expect(
        find.widgetWithText(Chip, 'Acknowledged'),
        findsOneWidget,
        reason: 'the incident itself reads as acknowledged',
      );
    });
  });

  group('acknowledged on the server, not saved offline', () {
    // Drives the real button through the screen's own success path: the fake
    // repository answers exactly as the controller does after the server
    // accepted the acknowledgement and the local write failed. Nothing about
    // the outcome is injected into the widget — the screen has to interpret it.
    Future<void> tapAcknowledge(WidgetTester tester) async {
      await tester.tap(find.text('Acknowledge'));
      await tester.pumpAndSettle();
    }

    testWidgets('the screen says acknowledged, not could not acknowledge', (
      WidgetTester tester,
    ) async {
      // [loadAfterAcknowledge] stands in for the server: the acknowledgement is
      // on record, so the refresh the success path triggers reports it.
      final _DetailRepo repo = _DetailRepo(
        IncidentDetailData(
          incident: _incident(),
          updates: <IncidentUpdate>[_update(1, 'Looking into it')],
          offline: false,
          summarySyncedAt: syncedAt,
          updatesSyncedAt: syncedAt,
        ),
      );
      repo.acknowledgeResult = IncidentDetailData(
        incident: _incident(acknowledgedAt: '2026-10-04T21:00:00Z'),
        updates: <IncidentUpdate>[_update(2, 'Pausing alerts')],
        offline: false,
        summarySyncedAt: syncedAt,
        updatesSyncedAt: syncedAt,
        savedOffline: false,
      );
      repo.loadAfterAcknowledge = repo.acknowledgeResult;
      await _pumpWith(tester, repo);
      await tapAcknowledge(tester);

      expect(
        find.text('Could not acknowledge this incident. Try again.'),
        findsNothing,
        reason:
            'the server accepted the action, so this failure copy would be a lie '
            'and would invite a second acknowledgement',
      );
      expect(
        find.text(
          'Acknowledged. Escalation is paused. This device could not save the '
          'update offline, so it may not be here without a connection.',
        ),
        findsOneWidget,
        reason:
            'the screen takes the success path and states the save problem, '
            'instead of either hiding it or calling the action failed',
      );
      expect(
        find.widgetWithText(Chip, 'Acknowledged'),
        findsOneWidget,
        reason: 'the incident itself reads as acknowledged, not as rejected',
      );
      expect(repo.acknowledges, 1, reason: 'exactly one request was sent');

      // The controls reflect the state the server now has, not the state the
      // failed write left behind: acknowledging again and escalating are both
      // server no-ops once an incident is acknowledged.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Acknowledge'),
            )
            .onPressed,
        isNull,
        reason: 'a second acknowledgement must not be offered',
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Escalate'),
            )
            .onPressed,
        isNull,
        reason: 'escalation is a server no-op once acknowledged',
      );
      expect(
        find.text('Escalation is a no-op once an incident is acknowledged.'),
        findsOneWidget,
        reason:
            'and a disabled control states why, rather than being a dead end',
      );
      // A failed local save is not an offline state: the device is online, so
      // snoozing is still a real action.
      expect(find.text('Response actions need a connection.'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Snooze 1 hour'),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('a plain success keeps the plain success copy', (
      WidgetTester tester,
    ) async {
      // The contrast that makes the test above meaningful: when the write
      // succeeded, nothing about saving is mentioned at all.
      final _DetailRepo repo = _DetailRepo(
        IncidentDetailData(
          incident: _incident(),
          updates: <IncidentUpdate>[_update(1, 'Looking into it')],
          offline: false,
          summarySyncedAt: syncedAt,
          updatesSyncedAt: syncedAt,
        ),
      );
      repo.acknowledgeResult = IncidentDetailData(
        incident: _incident(acknowledgedAt: '2026-10-04T21:00:00Z'),
        updates: <IncidentUpdate>[_update(2, 'Pausing alerts')],
        offline: false,
        summarySyncedAt: syncedAt,
        updatesSyncedAt: syncedAt,
      );
      repo.loadAfterAcknowledge = repo.acknowledgeResult;
      await _pumpWith(tester, repo);
      await tapAcknowledge(tester);

      expect(find.text('Acknowledged. Escalation is paused.'), findsOneWidget);
      expect(
        find.textContaining('could not save'),
        findsNothing,
        reason: 'a saved acknowledgement has nothing to warn about',
      );
    });

    testWidgets('a no-op server answer stays a no-op', (
      WidgetTester tester,
    ) async {
      // The server answered without an acknowledgement: that is a no-op, and
      // must not be dressed up as one.
      final _DetailRepo repo = _DetailRepo(
        IncidentDetailData(
          incident: _incident(resolvedAt: '2026-10-04T20:30:00Z'),
          updates: <IncidentUpdate>[],
          offline: false,
          summarySyncedAt: syncedAt,
          updatesSyncedAt: syncedAt,
        ),
      );
      repo.acknowledgeResult = IncidentDetailData(
        incident: _incident(resolvedAt: '2026-10-04T20:30:00Z'),
        updates: <IncidentUpdate>[],
        offline: false,
        summarySyncedAt: syncedAt,
        updatesSyncedAt: syncedAt,
      );
      await _pumpWith(tester, repo);

      // A resolved incident cannot be acknowledged at all.
      expect(
        find.text('Acknowledge'),
        findsOneWidget,
        reason: 'the control stays visible, disabled, with its reason',
      );
      await tapAcknowledge(tester);
      expect(repo.acknowledges, 0);
      expect(
        find.text(
          'The incident is no longer open, so it was not acknowledged.',
        ),
        findsNothing,
        reason: 'nothing was sent, so nothing is reported as a no-op outcome',
      );
    });
  });

  group('feed and dashboard freshness', () {
    testWidgets('the feed states its snapshot time', (
      WidgetTester tester,
    ) async {
      await pumpFeed(
        tester,
        IncidentsData(
          incidents: <Incident>[_incident()],
          offline: false,
          syncedAt: syncedAt,
        ),
      );
      expect(find.text('Last synced $syncedText'), findsOneWidget);
      expect(find.text('Offline — showing cached data'), findsNothing);
    });

    testWidgets('an offline feed states the cached time, not a fresh one', (
      WidgetTester tester,
    ) async {
      await pumpFeed(
        tester,
        IncidentsData(
          incidents: <Incident>[_incident()],
          offline: true,
          syncedAt: syncedAt,
        ),
      );
      expect(find.text('Offline — showing cached data'), findsOneWidget);
      expect(find.text('Last synced $syncedText'), findsOneWidget);
    });

    testWidgets('a feed that never synced says so', (
      WidgetTester tester,
    ) async {
      await pumpFeed(
        tester,
        const IncidentsData(incidents: <Incident>[], offline: false),
      );
      expect(find.text(unknownStamp), findsOneWidget);
    });

    testWidgets('the dashboard states its oldest component time', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(tester, _dashboard(synced: syncedAt));
      expect(find.text('Last synced $syncedText'), findsOneWidget);
    });

    testWidgets('the dashboard keeps R2 partial-page honesty', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(
        tester,
        DashboardData(
          totalMonitors: 137,
          loadedMonitors: 100,
          totalMonitorsKnown: true,
          countsByStatus: const <String, int>{'up': 100},
          averageUptime: 99.9,
          offline: false,
          syncedAt: syncedAt,
          incidents: partitionIncidents(<Incident>[_incident()]),
        ),
      );

      expect(
        find.textContaining('Showing 100 of 137 monitors'),
        findsOneWidget,
        reason: 'a freshness stamp must not turn a page into the whole account',
      );
      expect(find.text('Total'), findsOneWidget);
    });

    testWidgets('an offline dashboard keeps the cached-count wording', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(
        tester,
        DashboardData(
          totalMonitors: 2,
          loadedMonitors: 2,
          totalMonitorsKnown: false,
          countsByStatus: const <String, int>{'up': 2},
          averageUptime: 99.9,
          offline: true,
          syncedAt: syncedAt,
          incidents: partitionIncidents(<Incident>[_incident()]),
        ),
      );

      expect(find.text('Offline — showing cached data'), findsOneWidget);
      expect(find.text('Cached'), findsOneWidget);
      expect(find.textContaining('account total is unknown'), findsOneWidget);
      expect(find.text('Last synced $syncedText'), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('the stamp is one readable node and not a live region', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpDetail(
        tester,
        IncidentDetailData(
          incident: _incident(),
          updates: <IncidentUpdate>[_update(1, 'Looking into it')],
          offline: true,
          summarySyncedAt: syncedAt,
          updatesSyncedAt: syncedAt,
        ),
      );

      expect(
        find.bySemanticsLabel('Last synced $syncedText'),
        findsOneWidget,
        reason: 'the stamp reads as one sentence',
      );

      // Not a live region: an unchanged timestamp must not be re-announced on
      // every rebuild. Transitions and errors are announced by the notice
      // (`UptrackNotice` sets liveRegion for its error kind), not by a
      // timestamp that has not changed.
      final SemanticsNode stamp = tester.getSemantics(
        find.bySemanticsLabel('Last synced $syncedText'),
      );
      expect(
        stamp.getSemanticsData().flagsCollection.isLiveRegion,
        isFalse,
        reason: 'a static timestamp must not be announced as a change',
      );

      // The offline notice is a separate node that does announce, so the two
      // mechanisms are not conflated.
      expect(
        find.bySemanticsLabel(RegExp('Offline')),
        findsWidgets,
        reason: 'offline is carried by text, not colour alone',
      );
      handle.dispose();
    });

    testWidgets('the offline stamp wraps at 200% text without truncating', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final DateTime updatesAt = DateTime.utc(2026, 10, 4, 20, 5);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            incidentDetailRepositoryProvider.overrideWithValue(
              _DetailRepo(
                IncidentDetailData(
                  incident: _incident(),
                  updates: <IncidentUpdate>[_update(1, 'Looking into it')],
                  offline: true,
                  summarySyncedAt: syncedAt,
                  updatesSyncedAt: updatesAt,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const IncidentDetailScreen(incidentId: 'i1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'no overflow at 200%');
      expect(
        find.text('Last synced $syncedText'),
        findsOneWidget,
        reason: 'the whole stamp stays present and complete',
      );

      // Asserted before scrolling: offline is carried by this text, and after a
      // scroll to the updates section it has legitimately left the viewport.
      expect(
        find.text('Offline — showing cached data'),
        findsOneWidget,
        reason: 'offline is carried by text, not colour alone',
      );

      // At 200% the updates section sits below the fold of this viewport, and a
      // ListView only builds what is visible — so scroll to it before asking
      // whether its timestamp rendered.
      await tester.scrollUntilVisible(
        find.text('Updates'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'no overflow once scrolled',
      );
      expect(
        find.text('Updates last synced ${formatInstant(updatesAt)}'),
        findsOneWidget,
        reason: 'the second timestamp wraps instead of being cut off',
      );
    });
  });
}
