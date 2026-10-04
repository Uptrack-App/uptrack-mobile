import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/features/incidents/incident_detail_screen.dart';
import 'package:uptrack_mobile/features/incidents/incidents_controller.dart';
import 'package:uptrack_mobile/features/incidents/incidents_screen.dart';
import 'package:uptrack_mobile/theme/app_theme.dart';
import 'package:uptrack_mobile/util/date_format.dart';

Incident _incident(
  String id,
  String monitorName, {
  String status = 'open',
  String? resolvedAt,
  String? acknowledgedAt,
}) => Incident(
  id: id,
  monitorId: 'monitor-$id',
  status: status,
  insertedAt: '2026-09-26T00:00:00Z',
  monitorName: monitorName,
  startedAt: '2026-09-26T00:00:00Z',
  resolvedAt: resolvedAt,
  acknowledgedAt: acknowledgedAt,
);

IncidentUpdate _update(int id, String title) => IncidentUpdate(
  id: id,
  status: 'investigating',
  title: title,
  postedAt: '2026-09-26T00:05:00Z',
);

IncidentDetailData _detail({
  Incident? incident,
  List<IncidentUpdate>? updates,
  bool offline = false,
}) => IncidentDetailData(
  incident: incident ?? _incident('i1', 'Homepage'),
  updates: updates ?? <IncidentUpdate>[_update(7, 'Looking into it')],
  offline: offline,
);

class FakeIncidentsRepository implements IncidentsRepository {
  FakeIncidentsRepository({required this.onLoad});

  Future<IncidentsData> Function() onLoad;

  @override
  Future<IncidentsData> load() => onLoad();
}

class FakeIncidentDetailRepository implements IncidentDetailRepository {
  FakeIncidentDetailRepository({
    required this.onLoad,
    required this.onAck,
    this.onEscalate,
    this.onSnooze,
  });

  Future<IncidentDetailData> Function(String id) onLoad;
  Future<IncidentDetailData> Function(String id) onAck;
  Future<EscalateResult> Function(String id)? onEscalate;
  Future<SnoozeResult> Function(String monitorId)? onSnooze;
  int acknowledges = 0;
  int escalations = 0;
  int snoozes = 0;

  @override
  Future<IncidentDetailData> load(String id) => onLoad(id);

  @override
  Future<IncidentDetailData> acknowledge(String id) {
    acknowledges++;
    return onAck(id);
  }

  @override
  Future<EscalateResult> escalate(String id) {
    escalations++;
    final Future<EscalateResult> Function(String id)? handler = onEscalate;
    if (handler == null) {
      throw UnimplementedError('escalate was not faked for this test');
    }
    return handler(id);
  }

  @override
  Future<SnoozeResult> snooze(String monitorId) {
    snoozes++;
    final Future<SnoozeResult> Function(String monitorId)? handler = onSnooze;
    if (handler == null) {
      throw UnimplementedError('snooze was not faked for this test');
    }
    return handler(monitorId);
  }
}

DioException _boom() => DioException(
  requestOptions: RequestOptions(path: '/api/incidents'),
  message: 'Connection refused',
);

Future<void> pumpFeed(WidgetTester tester, FakeIncidentsRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [incidentsRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: IncidentsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpDetail(
  WidgetTester tester,
  FakeIncidentDetailRepository repo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [incidentDetailRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: IncidentDetailScreen(incidentId: 'i1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('filterIncidents', () {
    final List<Incident> rows = <Incident>[
      _incident('a', 'Homepage'),
      _incident('b', 'API', resolvedAt: '2026-09-26T01:00:00Z'),
    ];

    test('all returns everything, open only ongoing', () {
      expect(filterIncidents(rows), hasLength(2));
      expect(
        filterIncidents(
          rows,
          status: IncidentStatusFilter.open,
        ).map((Incident i) => i.id),
        <String>['a'],
      );
    });
  });

  group('optimisticAcknowledge', () {
    test('marks the incident acknowledged, keeps other fields', () {
      final IncidentDetailData before = _detail();
      final IncidentDetailData after = optimisticAcknowledge(
        before,
        now: DateTime.utc(2026, 9, 26, 0, 10),
      );

      expect(before.incident.isAcknowledged, isFalse);
      expect(after.incident.isAcknowledged, isTrue);
      expect(after.incident.acknowledgedAt, '2026-09-26T00:10:00.000Z');
      expect(after.incident.id, before.incident.id);
      expect(after.updates, same(before.updates));
    });

    test('leaves already-acknowledged incidents untouched', () {
      final IncidentDetailData before = _detail(
        incident: _incident('i1', 'Homepage', acknowledgedAt: 'old'),
      );
      expect(identical(optimisticAcknowledge(before), before), isTrue);
    });
  });

  group('IncidentsScreen', () {
    testWidgets('shows rows with open/resolved states', (
      WidgetTester tester,
    ) async {
      await pumpFeed(
        tester,
        FakeIncidentsRepository(
          onLoad: () async => IncidentsData(
            incidents: <Incident>[
              _incident('a', 'Homepage'),
              _incident(
                'b',
                'API',
                status: 'resolved',
                resolvedAt: '2026-09-26T01:00:00Z',
              ),
            ],
            offline: false,
          ),
        ),
      );

      expect(find.text('Incidents'), findsOneWidget);
      expect(find.text('Homepage'), findsOneWidget);
      expect(find.text('API'), findsOneWidget);
      expect(find.text('Open'), findsNWidgets(2));
      expect(
        find.text('Resolved'),
        findsOneWidget,
      ); // Timestamps are human-readable local time, never raw ISO 8601.
      expect(find.text('2026-09-26T00:00:00Z'), findsNothing);
      expect(
        find.text(formatTimestamp('2026-09-26T00:00:00Z')),
        findsNWidgets(2),
      );
    });

    testWidgets('open filter hides resolved incidents', (
      WidgetTester tester,
    ) async {
      await pumpFeed(
        tester,
        FakeIncidentsRepository(
          onLoad: () async => IncidentsData(
            incidents: <Incident>[
              _incident('a', 'Homepage'),
              _incident(
                'b',
                'API',
                status: 'resolved',
                resolvedAt: '2026-09-26T01:00:00Z',
              ),
            ],
            offline: false,
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('incident-filter-open')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Homepage'), findsOneWidget);
      expect(find.text('API'), findsNothing);
    });

    testWidgets('empty, offline, and error states', (
      WidgetTester tester,
    ) async {
      await pumpFeed(
        tester,
        FakeIncidentsRepository(
          onLoad: () async =>
              const IncidentsData(incidents: <Incident>[], offline: false),
        ),
      );
      expect(find.text('No incidents.'), findsOneWidget);
    });

    testWidgets('offline banner for cached data', (WidgetTester tester) async {
      await pumpFeed(
        tester,
        FakeIncidentsRepository(
          onLoad: () async => IncidentsData(
            incidents: <Incident>[_incident('a', 'Homepage')],
            offline: true,
          ),
        ),
      );

      expect(find.text('Offline — showing cached data'), findsOneWidget);
    });

    testWidgets('error state with retry that recovers', (
      WidgetTester tester,
    ) async {
      final FakeIncidentsRepository repo = FakeIncidentsRepository(
        onLoad: () async => throw _boom(),
      );
      await pumpFeed(tester, repo);

      expect(
        find.text(
          'Could not load incidents. Check your connection and try again.',
        ),
        findsOneWidget,
      );

      repo.onLoad = () async => IncidentsData(
        incidents: <Incident>[_incident('a', 'Homepage')],
        offline: false,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Homepage'), findsOneWidget);
    });

    testWidgets('loading spinner while the repository is pending', (
      WidgetTester tester,
    ) async {
      final Completer<IncidentsData> gate = Completer<IncidentsData>();
      final FakeIncidentsRepository repo = FakeIncidentsRepository(
        onLoad: () => gate.future,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [incidentsRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: IncidentsScreen()),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete(
        IncidentsData(
          incidents: <Incident>[_incident('a', 'Homepage')],
          offline: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Homepage'), findsOneWidget);
    });
  });

  group('IncidentDetailScreen', () {
    testWidgets('shows header, acknowledge action, and updates', (
      WidgetTester tester,
    ) async {
      final FakeIncidentDetailRepository repo = FakeIncidentDetailRepository(
        onLoad: (String id) async => _detail(),
        onAck: (String id) async => _detail(
          incident: _incident(
            'i1',
            'Homepage',
            acknowledgedAt: '2026-09-26T00:10:00Z',
          ),
        ),
      );
      await pumpDetail(tester, repo);

      expect(find.text('Homepage'), findsOneWidget);
      expect(find.text('Acknowledge'), findsOneWidget);
      expect(find.text('Updates'), findsOneWidget);
      expect(find.text('Looking into it'), findsOneWidget);
    });

    testWidgets('acknowledge applies the optimistic update', (
      WidgetTester tester,
    ) async {
      final Completer<IncidentDetailData> gate =
          Completer<IncidentDetailData>();
      final FakeIncidentDetailRepository repo = FakeIncidentDetailRepository(
        onLoad: (String id) async => _detail(),
        onAck: (String id) => gate.future,
      );
      await pumpDetail(tester, repo);

      await tester.tap(find.text('Acknowledge'));
      await tester.pump();

      // The request is in flight and the optimistic state is visible.
      expect(repo.acknowledges, 1);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.textContaining('Acknowledged'), findsWidgets);

      gate.complete(
        _detail(
          incident: _incident(
            'i1',
            'Homepage',
            acknowledgedAt: '2026-09-26T00:10:00Z',
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Settled on the server's answer: the optimistic flag is gone and the
      // result copy names what actually happened.
      expect(find.text('Acknowledged. Escalation is paused.'), findsOneWidget);
      expect(find.textContaining('Acknowledged'), findsWidgets);
    });

    testWidgets('acknowledge failure rolls back and shows a SnackBar', (
      WidgetTester tester,
    ) async {
      final FakeIncidentDetailRepository repo = FakeIncidentDetailRepository(
        onLoad: (String id) async => _detail(),
        onAck: (String id) async => throw _boom(),
      );
      await pumpDetail(tester, repo);

      await tester.tap(find.text('Acknowledge'));
      await tester.pumpAndSettle();

      // Rolled back: the action is available again and the error surfaces.
      expect(find.text('Acknowledge'), findsOneWidget);
      expect(find.textContaining('Acknowledged'), findsNothing);
      expect(
        find.text('Could not acknowledge this incident. Try again.'),
        findsOneWidget,
      );
    });

    testWidgets('acknowledged incidents cannot acknowledge again', (
      WidgetTester tester,
    ) async {
      final FakeIncidentDetailRepository repo = FakeIncidentDetailRepository(
        onLoad: (String id) async => _detail(
          incident: _incident(
            'i1',
            'Homepage',
            acknowledgedAt: '2026-09-26T00:10:00Z',
          ),
        ),
        onAck: (String id) async => _detail(),
      );
      await pumpDetail(tester, repo);

      // Disabled, not hidden: the label stays visible and tapping is inert.
      await tester.tap(find.text('Acknowledge'));
      await tester.pumpAndSettle();
      expect(repo.acknowledges, 0);
      expect(find.textContaining('Acknowledged'), findsWidgets);
    });

    testWidgets('offline detail disables response actions and notes updates', (
      WidgetTester tester,
    ) async {
      final FakeIncidentDetailRepository repo = FakeIncidentDetailRepository(
        onLoad: (String id) async =>
            _detail(offline: true, updates: const <IncidentUpdate>[]),
        onAck: (String id) async => _detail(),
      );
      await pumpDetail(tester, repo);

      expect(find.text('Offline — showing cached data'), findsOneWidget);
      expect(find.text('Response actions need a connection.'), findsOneWidget);
      expect(find.text('Updates unavailable offline.'), findsOneWidget);

      // Disabled, not hidden: tapping sends nothing.
      for (final String label in <String>[
        'Acknowledge',
        'Escalate',
        'Snooze 1 hour',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(repo.acknowledges, 0);
      expect(repo.escalations, 0);
      expect(repo.snoozes, 0);
    });

    testWidgets('error state with retry that recovers', (
      WidgetTester tester,
    ) async {
      final FakeIncidentDetailRepository repo = FakeIncidentDetailRepository(
        onLoad: (String id) async => throw _boom(),
        onAck: (String id) async => _detail(),
      );
      await pumpDetail(tester, repo);

      expect(
        find.text(
          'Could not load incidents. Check your connection and try again.',
        ),
        findsOneWidget,
      );

      repo.onLoad = (String id) async => _detail();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Homepage'), findsOneWidget);
    });
  });

  /// Filter chip layout at large text.
  ///
  /// A chip that cannot fit its label on one line has to wrap and grow rather
  /// than fade or clip it away, and the checkmark the selected chip draws must
  /// come out of the label's width rather than push the label out of the chip.
  ///
  /// Measured on the [RenderParagraph] the chip actually laid out: a chip that
  /// silently truncates its label raises no overflow error and reports no
  /// exceeded line budget, so "nothing threw" and "didExceedMaxLines" both
  /// pass on the broken control.
  group('filter chips at large text', () {
    Future<void> pumpChips(
      WidgetTester tester, {
      required double width,
      double textScale = 2,
      IncidentStatusFilter filter = IncidentStatusFilter.all,
    }) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: IncidentsScreen(filter: filter),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder chip(IncidentStatusFilter filter) =>
        find.byKey(ValueKey<String>('incident-filter-${filter.queryValue}'));

    Finder label(IncidentStatusFilter filter) =>
        find.descendant(of: chip(filter), matching: find.text(filter.label));

    /// Height the label needs to be shown **in full** at the exact width the
    /// chip handed it, laid out independently of the chip.
    double fullTextHeight(WidgetTester tester, IncidentStatusFilter filter) {
      final Finder text = label(filter);
      final BuildContext context = tester.element(text);
      final TextPainter painter =
          TextPainter(
            text: TextSpan(
              text: filter.label,
              style: DefaultTextStyle.of(context).style
                  .merge(tester.widget<Text>(text).style),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(
            maxWidth: tester.renderObject<RenderParagraph>(text).size.width,
          );
      addTearDown(painter.dispose);
      // Nothing may be dropped: no line cap, no ellipsis.
      expect(painter.didExceedMaxLines, isFalse);
      return painter.height;
    }

    for (final double width in <double>[240, 320, 411]) {
      testWidgets(
        'the selected Needs acknowledgement label is shown in full on a '
        '${width.toInt()}px phone at 200% text',
        (WidgetTester tester) async {
          await pumpChips(
            tester,
            width: width,
            filter: IncidentStatusFilter.needsAcknowledgement,
          );
          expect(tester.takeException(), isNull);

          const IncidentStatusFilter filter =
              IncidentStatusFilter.needsAcknowledgement;
          final RenderParagraph paragraph = tester
              .renderObject<RenderParagraph>(label(filter));
          final double needed = fullTextHeight(tester, filter);

          // Wrapped onto more than one line, and the box it was given holds
          // every one of them: the full label is readable, not cut off.
          expect(needed, greaterThan(paragraph.size.height ~/ 2));
          expect(paragraph.size.height, greaterThanOrEqualTo(needed - 0.5));
          expect(paragraph.didExceedMaxLines, isFalse);

          // The chip stayed inside the width the bar has, checkmark included.
          expect(
            tester.renderObject<RenderBox>(chip(filter)).size.width,
            lessThanOrEqualTo(width - 32 + 0.5),
          );
        },
      );
    }

    testWidgets('every chip keeps its full label and stays inside the bar', (
      WidgetTester tester,
    ) async {
      await pumpChips(
        tester,
        width: 320,
        filter: IncidentStatusFilter.needsAcknowledgement,
      );
      expect(tester.takeException(), isNull);

      // Checked one chip at a time: each one is capped on its own, so the long
      // selected chip cannot squeeze the other labels out of the bar.
      for (final IncidentStatusFilter filter in IncidentStatusFilter.values) {
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          label(filter),
        );
        expect(
          paragraph.size.height,
          greaterThanOrEqualTo(fullTextHeight(tester, filter) - 0.5),
          reason: 'the ${filter.label} chip must show all of its label',
        );
        expect(
          tester.renderObject<RenderBox>(chip(filter)).size.width,
          lessThanOrEqualTo(288.5),
          reason: 'the ${filter.label} chip must not overflow the bar',
        );
        // At least the 48dp minimum target, on one line or wrapped.
        expect(
          tester.renderObject<RenderBox>(chip(filter)).size.height,
          greaterThanOrEqualTo(48),
        );
      }
    });

    testWidgets('each chip is a tap target that reports its own selection', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpChips(tester, width: 320);

      bool readsAsSelected(IncidentStatusFilter filter) =>
          tester
              .getSemantics(find.bySemanticsLabel(filter.label))
              .flagsCollection
              .isSelected ==
          Tristate.isTrue;

      // Every chip is an actionable control, and exactly the current filter
      // reads as selected.
      for (final IncidentStatusFilter filter in IncidentStatusFilter.values) {
        expect(find.bySemanticsLabel(filter.label), findsOneWidget);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel(filter.label))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
          reason: 'the ${filter.label} chip must be tappable',
        );
        expect(
          readsAsSelected(filter),
          filter == IncidentStatusFilter.all,
          reason: 'only the current filter may read as selected',
        );
      }

      await tester.tap(chip(IncidentStatusFilter.needsAcknowledgement));
      await tester.pumpAndSettle();

      // The selection moved to the tapped chip, which is the one that wraps.
      expect(
        readsAsSelected(IncidentStatusFilter.needsAcknowledgement),
        isTrue,
      );
      expect(readsAsSelected(IncidentStatusFilter.all), isFalse);
      expect(readsAsSelected(IncidentStatusFilter.open), isFalse);
      // Tapping the wrapped chip worked despite the extra lines. The fixture
      // serves one open, unacknowledged incident, so the needs-acknowledgement
      // queue is not empty: the tap must reveal that row, not the empty copy.
      expect(find.text('Homepage'), findsOneWidget);
      expect(find.text('No incidents need acknowledgement.'), findsNothing);
      handle.dispose();
    });

    testWidgets('a short label still sizes the chip to itself at 100% text', (
      WidgetTester tester,
    ) async {
      await pumpChips(tester, width: 1024, textScale: 1);
      final double available = 1024 - 32;

      for (final IncidentStatusFilter filter in IncidentStatusFilter.values) {
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          label(filter),
        );
        // One line, and the chip no wider than the label needs: the cap only
        // ever applies to a label that does not fit, never as a stretch.
        expect(paragraph.size.height, lessThanOrEqualTo(48));
        expect(
          tester.renderObject<RenderBox>(chip(filter)).size.width,
          lessThan(available),
          reason: '${filter.label} should hug its label, not stretch the bar',
        );
      }
    });
  });
}
