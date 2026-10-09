import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/features/incidents/incident_detail_screen.dart';
import 'package:uptrack_mobile/features/incidents/incident_response.dart';
import 'package:uptrack_mobile/features/incidents/incidents_controller.dart';
import 'package:uptrack_mobile/theme/app_theme.dart';
import 'package:uptrack_mobile/util/date_format.dart';

Incident _incident(
  String id, {
  String monitorId = 'm1',
  String monitorName = 'Homepage',
  String? acknowledgedAt,
  String? resolvedAt,
}) => Incident(
  id: id,
  monitorId: monitorId,
  status: resolvedAt == null ? 'ongoing' : 'resolved',
  insertedAt: '2026-09-27T10:00:00Z',
  monitorName: monitorName,
  startedAt: '2026-09-27T10:00:00Z',
  acknowledgedAt: acknowledgedAt,
  resolvedAt: resolvedAt,
);

IncidentDetailData _detail({
  required Incident incident,
  bool offline = false,
}) => IncidentDetailData(
  incident: incident,
  updates: const <IncidentUpdate>[],
  offline: offline,
);

/// Fake seam: every mutation is scripted, and every call is counted so a
/// test can assert what was (and was not) sent.
class FakeDetailRepository implements IncidentDetailRepository {
  FakeDetailRepository({
    required this.onLoad,
    this.onAcknowledge,
    this.onEscalate,
    this.onSnooze,
  });

  Future<IncidentDetailData> Function(String id) onLoad;
  Future<IncidentDetailData> Function(String id)? onAcknowledge;
  Future<EscalateResult> Function(String id)? onEscalate;
  Future<SnoozeResult> Function(String monitorId)? onSnooze;

  int acknowledgements = 0;
  int escalations = 0;
  int snoozes = 0;
  final List<String> snoozedMonitors = <String>[];

  @override
  Future<IncidentDetailData> load(String id) => onLoad(id);

  @override
  Future<IncidentDetailData> acknowledge(String id) {
    acknowledgements++;
    final Future<IncidentDetailData> Function(String id)? handler =
        onAcknowledge;
    if (handler == null) {
      throw StateError('acknowledge was not scripted');
    }
    return handler(id);
  }

  @override
  Future<EscalateResult> escalate(String id) {
    escalations++;
    final Future<EscalateResult> Function(String id)? handler = onEscalate;
    if (handler == null) {
      throw StateError('escalate was not scripted');
    }
    return handler(id);
  }

  @override
  Future<SnoozeResult> snooze(String monitorId) {
    snoozes++;
    snoozedMonitors.add(monitorId);
    final Future<SnoozeResult> Function(String monitorId)? handler = onSnooze;
    if (handler == null) {
      throw StateError('snooze was not scripted');
    }
    return handler(monitorId);
  }
}

DioException _boom({int status = 0, String? serverError}) => DioException(
  requestOptions: RequestOptions(path: '/api/incidents/i1'),
  message: 'Connection refused',
  response: status == 0
      ? null
      : Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/api/incidents/i1'),
          statusCode: status,
          data: <String, dynamic>{
            if (serverError case final String message) 'error': message,
          },
        ),
);

/// Pumps the detail screen with a scripted repository.
Future<void> pumpDetail(
  WidgetTester tester,
  FakeDetailRepository repo, {
  String incidentId = 'i1',
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [incidentDetailRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: IncidentDetailScreen(incidentId: incidentId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('response outcomes are truthful', () {
    test('escalate reports published alerts, never delivery', () {
      final IncidentResponseOutcome outcome = interpretEscalate(
        const EscalateResult(escalated: true, stepsFired: 2),
      );
      expect(outcome, isA<IncidentEscalated>());
      expect(outcome.message, 'Escalation sent. 2 alerts published.');
      expect(outcome.message, isNot(contains('notified')));
      expect(outcome.message, isNot(contains('delivered')));
    });

    test('escalate singular copy for one published alert', () {
      expect(
        interpretEscalate(const EscalateResult(escalated: true, stepsFired: 1))
            .message,
        'Escalation sent. 1 alert published.',
      );
    });

    test('escalated false and zero steps are neutral no-ops', () {
      for (final EscalateResult result in const <EscalateResult>[
        EscalateResult(escalated: false, stepsFired: 0),
        EscalateResult(escalated: true, stepsFired: 0),
        EscalateResult(escalated: false, stepsFired: 3),
      ]) {
        final IncidentResponseOutcome outcome = interpretEscalate(result);
        expect(outcome, isA<IncidentEscalationNoop>());
        expect(outcome.message, 'No escalation was sent.');
        // Must not imply an exhausted policy or a delivered notification.
        expect(outcome.message, isNot(contains('policy')));
        expect(outcome.message, isNot(contains('exhausted')));
      }
    });

    test('snooze states the expiry and full mobile-push suppression', () {
      final IncidentSnoozed outcome = interpretSnooze(
        const SnoozeResult(snoozedUntil: '2026-09-27T11:00:00Z'),
      ) as IncidentSnoozed;
      expect(
        outcome.message,
        contains(formatTimestamp('2026-09-27T11:00:00Z')),
      );
      expect(outcome.message, contains('including recovery updates'));
      expect(
        outcome.message,
        isNot(contains('recovery updates still come through')),
      );
    });

    test('acknowledge follows the server answer, not the tap', () {
      expect(
        interpretAcknowledge(
          _detail(
            incident: _incident('i1', acknowledgedAt: '2026-09-27T10:05:00Z'),
          ),
        ),
        isA<IncidentAcknowledged>(),
      );
      expect(
        interpretAcknowledge(_detail(incident: _incident('i1'))),
        isA<IncidentAcknowledgedNoop>(),
      );
    });
  });

  group('response eligibility', () {
    test('escalate is refused once acknowledged, snooze is not', () {
      final ResponseEligibility acked = ResponseEligibility.from(
        _detail(
          incident: _incident('i1', acknowledgedAt: '2026-09-27T10:05:00Z'),
        ),
      );
      expect(acked.canEscalate, isFalse);
      expect(acked.canSnooze, isTrue);
      expect(acked.escalateRefusal, isNotNull);
      expect(acked.snoozeRefusal, isNull);
    });

    test('resolved and offline incidents refuse every mutation', () {
      for (final IncidentDetailData data in <IncidentDetailData>[
        _detail(incident: _incident('i1', resolvedAt: '2026-09-27T11:00:00Z')),
        _detail(incident: _incident('i1'), offline: true),
      ]) {
        final ResponseEligibility eligibility = ResponseEligibility.from(data);
        expect(eligibility.canEscalate, isFalse);
        expect(eligibility.canSnooze, isFalse);
      }
    });

    test('missing detail refuses everything', () {
      final ResponseEligibility eligibility = ResponseEligibility.from(null);
      expect(eligibility.canEscalate, isFalse);
      expect(eligibility.canSnooze, isFalse);
      expect(eligibility.escalateRefusal, isNotNull);
    });
  });

  group('IncidentDetailScreen response section', () {
    testWidgets('acknowledge, escalate and snooze are offered when open', (
      WidgetTester tester,
    ) async {
      await pumpDetail(
        tester,
        FakeDetailRepository(
          onLoad: (String id) async => _detail(incident: _incident(id)),
        ),
      );

      expect(find.text('Response'), findsOneWidget);
      expect(find.text('Acknowledge'), findsOneWidget);
      expect(find.text('Escalate'), findsOneWidget);
      expect(find.text('Snooze 1 hour'), findsOneWidget);
    });

    testWidgets('escalate confirms scope before sending', (
      WidgetTester tester,
    ) async {
      final FakeDetailRepository repo = FakeDetailRepository(
        onLoad: (String id) async => _detail(incident: _incident(id)),
        onEscalate: (String id) async =>
            const EscalateResult(escalated: true, stepsFired: 2),
      );
      await pumpDetail(tester, repo);

      await tester.tap(find.text('Escalate'));
      await tester.pumpAndSettle();

      // The confirmation names what escalation does.
      expect(find.text(IncidentEscalateConfirmation.title), findsOneWidget);
      expect(
        find.textContaining('remaining configured policy steps'),
        findsOneWidget,
      );
      // Nothing sent before confirming.
      expect(repo.escalations, 0);

      await tester.tap(find.text('Escalate now'));
      await tester.pumpAndSettle();

      expect(repo.escalations, 1);
      expect(find.text('Escalation sent. 2 alerts published.'), findsOneWidget);
    });

    testWidgets('cancelling the escalation sends nothing', (
      WidgetTester tester,
    ) async {
      final FakeDetailRepository repo = FakeDetailRepository(
        onLoad: (String id) async => _detail(incident: _incident(id)),
        onEscalate: (String id) async =>
            const EscalateResult(escalated: true, stepsFired: 1),
      );
      await pumpDetail(tester, repo);

      await tester.tap(find.text('Escalate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.escalations, 0);
      expect(find.textContaining('Escalation sent'), findsNothing);
    });

    testWidgets('an escalation no-op is reported neutrally', (
      WidgetTester tester,
    ) async {
      final FakeDetailRepository repo = FakeDetailRepository(
        onLoad: (String id) async => _detail(incident: _incident(id)),
        onEscalate: (String id) async =>
            const EscalateResult(escalated: false, stepsFired: 0),
      );
      await pumpDetail(tester, repo);

      await tester.tap(find.text('Escalate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escalate now'));
      await tester.pumpAndSettle();

      expect(repo.escalations, 1);
      expect(find.text('No escalation was sent.'), findsOneWidget);
    });

    testWidgets('snooze confirms scope and shows the returned expiry', (
      WidgetTester tester,
    ) async {
      final FakeDetailRepository repo = FakeDetailRepository(
        onLoad: (String id) async => _detail(incident: _incident(id)),
        onSnooze: (String monitorId) async =>
            const SnoozeResult(snoozedUntil: '2026-09-27T11:00:00Z'),
      );
      await pumpDetail(tester, repo);

      await tester.tap(find.text('Snooze 1 hour'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('including recovery updates'),
        findsOneWidget,
        reason: 'the confirmation must state recovery updates are suppressed',
      );
      expect(find.textContaining('does not stop team alerts'), findsOneWidget);
      expect(repo.snoozes, 0);

      await tester.tap(find.text('Pause for 1 hour'));
      await tester.pumpAndSettle();

      expect(repo.snoozes, 1);
      // The monitor comes from the loaded incident, not a guess.
      expect(repo.snoozedMonitors, <String>['m1']);
      expect(
        find.textContaining(formatTimestamp('2026-09-27T11:00:00Z')),
        findsWidgets,
      );
    });

    testWidgets('acknowledged incidents keep snooze but not escalate', (
      WidgetTester tester,
    ) async {
      final FakeDetailRepository repo = FakeDetailRepository(
        onLoad: (String id) async => _detail(
          incident: _incident(id, acknowledgedAt: '2026-09-27T10:05:00Z'),
        ),
        onEscalate: (String id) async =>
            const EscalateResult(escalated: true, stepsFired: 1),
        onSnooze: (String monitorId) async =>
            const SnoozeResult(snoozedUntil: '2026-09-27T11:00:00Z'),
      );
      await pumpDetail(tester, repo);

      await tester.ensureVisible(find.text('Escalate'));
      await tester.tap(find.text('Escalate'));
      await tester.pumpAndSettle();
      expect(repo.escalations, 0);
      // Both are disabled rather than removed, and tapping sends nothing.
      await tester.tap(find.text('Acknowledge'));
      await tester.pumpAndSettle();
      expect(repo.acknowledgements, 0);

      await tester.ensureVisible(find.text('Snooze 1 hour'));
      await tester.tap(find.text('Snooze 1 hour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause for 1 hour'));
      await tester.pumpAndSettle();
      expect(repo.snoozes, 1);
    });

    testWidgets('a resolved incident offers no response mutations', (
      WidgetTester tester,
    ) async {
      final FakeDetailRepository repo = FakeDetailRepository(
        onLoad: (String id) async => _detail(
          incident: _incident(id, resolvedAt: '2026-09-27T11:00:00Z'),
        ),
      );
      await pumpDetail(tester, repo);

      expect(
        find.text('This incident is resolved. Nothing left to respond to.'),
        findsOneWidget,
      );
      for (final String label in <String>[
        'Acknowledge',
        'Escalate',
        'Snooze 1 hour',
      ]) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(repo.acknowledgements, 0);
      expect(repo.escalations, 0);
      expect(repo.snoozes, 0);
    });

    testWidgets('offline disables every action with a reason', (
      WidgetTester tester,
    ) async {
      final FakeDetailRepository repo = FakeDetailRepository(
        onLoad: (String id) async =>
            _detail(incident: _incident(id), offline: true),
      );
      await pumpDetail(tester, repo);

      expect(find.text('Response actions need a connection.'), findsOneWidget);
      for (final String label in <String>[
        'Acknowledge',
        'Escalate',
        'Snooze 1 hour',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(repo.acknowledgements, 0);
      expect(repo.escalations, 0);
      expect(repo.snoozes, 0);
    });

    testWidgets('mutations are serialized while one is in flight', (
      WidgetTester tester,
    ) async {
      final Completer<EscalateResult> gate = Completer<EscalateResult>();
      final FakeDetailRepository repo = FakeDetailRepository(
        onLoad: (String id) async => _detail(incident: _incident(id)),
        onEscalate: (String id) => gate.future,
      );
      await pumpDetail(tester, repo);

      await tester.tap(find.text('Escalate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escalate now'));
      // A busy CircularProgressIndicator animates forever, so settle is not
      // an option while the request is gated.
      await tester.pump();

      // While escalating, no other action may start.
      await tester.tap(find.text('Snooze 1 hour'));
      await tester.pump();
      expect(repo.snoozes, 0);
      await tester.tap(find.text('Acknowledge'));
      await tester.pump();
      expect(repo.acknowledgements, 0);

      gate.complete(const EscalateResult(escalated: true, stepsFired: 1));
      await tester.pumpAndSettle();
      expect(repo.escalations, 1);
    });

    testWidgets('repeating an action after it settles works', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      final FakeDetailRepository repo = FakeDetailRepository(
        onLoad: (String id) async => _detail(incident: _incident(id)),
        onEscalate: (String id) async {
          calls++;
          return const EscalateResult(escalated: true, stepsFired: 1);
        },
      );
      await pumpDetail(tester, repo);

      for (int attempt = 0; attempt < 2; attempt++) {
        await tester.ensureVisible(find.text('Escalate'));
        await tester.tap(find.text('Escalate'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Escalate now'));
        await tester.pumpAndSettle();
      }

      expect(calls, 2);
      expect(repo.escalations, 2);
    });

    testWidgets('a failed action shows retryable feedback and no success', (
      WidgetTester tester,
    ) async {
      final FakeDetailRepository repo = FakeDetailRepository(
        onLoad: (String id) async => _detail(incident: _incident(id)),
        onEscalate: (String id) async => throw _boom(),
      );
      await pumpDetail(tester, repo);

      await tester.tap(find.text('Escalate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escalate now'));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not escalate this incident. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('Escalation sent'), findsNothing);
      expect(find.textContaining('No escalation was sent'), findsNothing);

      // The action is offered again, so the failure is retryable.
      await tester.ensureVisible(find.text('Escalate'));
      expect(find.text('Escalate'), findsOneWidget);
    });

    testWidgets('a 401 is reported as an expired session, not a server error', (
      WidgetTester tester,
    ) async {
      final FakeDetailRepository repo = FakeDetailRepository(
        onLoad: (String id) async => _detail(incident: _incident(id)),
        onSnooze: (String monitorId) async =>
            throw _boom(status: 401, serverError: 'unauthorized'),
      );
      await pumpDetail(tester, repo);

      await tester.tap(find.text('Snooze 1 hour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause for 1 hour'));
      await tester.pumpAndSettle();

      expect(
        find.text('Session expired. Sign in again, then retry this action.'),
        findsOneWidget,
      );
      expect(find.textContaining('paused until'), findsNothing);
    });

    testWidgets('a result arriving after the incident changed is dropped', (
      WidgetTester tester,
    ) async {
      final Completer<EscalateResult> gate = Completer<EscalateResult>();
      final FakeDetailRepository repo = FakeDetailRepository(
        onLoad: (String id) async => _detail(incident: _incident(id)),
        onEscalate: (String id) => gate.future,
      );
      await pumpDetail(tester, repo);

      await tester.tap(find.text('Escalate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escalate now'));
      await tester.pump();

      // The screen is rebuilt for a different incident while the request is
      // in flight (deep link / route reuse).
      await tester.pumpWidget(
        ProviderScope(
          overrides: [incidentDetailRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const IncidentDetailScreen(incidentId: 'i2'),
          ),
        ),
      );
      await tester.pump();

      gate.complete(const EscalateResult(escalated: true, stepsFired: 2));
      await tester.pumpAndSettle();

      // The stale result belongs to i1 and must not be shown on i2.
      expect(find.textContaining('Escalation sent'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an eligibility change during the dialog blocks the action', (
      WidgetTester tester,
    ) async {
      // Open, unacknowledged when the button is tapped.
      bool acknowledged = false;
      final FakeDetailRepository repo = FakeDetailRepository(
        onLoad: (String id) async => _detail(
          incident: _incident(
            id,
            acknowledgedAt: acknowledged ? '2026-09-27T10:05:00Z' : null,
          ),
        ),
        onEscalate: (String id) async =>
            const EscalateResult(escalated: true, stepsFired: 2),
      );
      await pumpDetail(tester, repo);

      await tester.tap(find.text('Escalate'));
      await tester.pumpAndSettle();
      expect(find.text(IncidentEscalateConfirmation.title), findsOneWidget);

      // Someone else acknowledges the incident while the dialog is open, and
      // the screen reloads with the new fact.
      acknowledged = true;
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(IncidentDetailScreen)),
      );
      container.invalidate(incidentDetailProvider('i1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Escalate now'));
      await tester.pumpAndSettle();

      expect(
        repo.escalations,
        0,
        reason: 'escalation is a server no-op once acknowledged',
      );
      expect(find.textContaining('Nothing was sent'), findsOneWidget);
    });

    testWidgets('no optimistic snooze or escalate success', (
      WidgetTester tester,
    ) async {
      final Completer<SnoozeResult> gate = Completer<SnoozeResult>();
      final FakeDetailRepository repo = FakeDetailRepository(
        onLoad: (String id) async => _detail(incident: _incident(id)),
        onSnooze: (String monitorId) => gate.future,
      );
      await pumpDetail(tester, repo);

      await tester.tap(find.text('Snooze 1 hour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause for 1 hour'));
      await tester.pump();

      // In flight: no success copy, only progress.
      expect(find.textContaining('paused until'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      gate.complete(const SnoozeResult(snoozedUntil: '2026-09-27T11:00:00Z'));
      await tester.pumpAndSettle();
      expect(find.textContaining('paused until'), findsWidgets);
    });

    testWidgets('a disposed dialog does not act on a stale screen', (
      WidgetTester tester,
    ) async {
      final FakeDetailRepository repo = FakeDetailRepository(
        onLoad: (String id) async => _detail(incident: _incident(id)),
        onEscalate: (String id) async =>
            const EscalateResult(escalated: true, stepsFired: 1),
      );
      await pumpDetail(tester, repo);

      // Open the confirmation, then replace the screen (route change).
      await tester.tap(find.text('Escalate'));
      await tester.pumpAndSettle();
      expect(find.text(IncidentEscalateConfirmation.title), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      // The late dialog result must not reach a disposed state.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repo.escalations, 0);
    });

    testWidgets('the response section survives 200% text', (
      WidgetTester tester,
    ) async {
      await pumpDetail(
        tester,
        FakeDetailRepository(
          onLoad: (String id) async => _detail(incident: _incident(id)),
        ),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      for (final String label in <String>[
        'Response',
        'Acknowledge',
        'Escalate',
        'Snooze 1 hour',
      ]) {
        await tester.ensureVisible(find.text(label));
        expect(
          find.text(label),
          findsOneWidget,
          reason: '$label must remain reachable at 200% text',
        );
      }
    });
  });
}
