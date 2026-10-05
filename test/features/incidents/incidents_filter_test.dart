import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/incident.dart';
import 'package:uptrack_mobile/features/incidents/incidents_controller.dart';
import 'package:uptrack_mobile/features/incidents/incidents_screen.dart';

String at(int hours) =>
    DateTime.utc(2026, 9, 26).add(Duration(hours: hours)).toIso8601String();

Incident _incident(
  String id,
  String monitorName, {
  int? hours,
  String? startedAt,
  String? insertedAt,
  String? acknowledgedAt,
  String? resolvedAt,
}) => Incident(
  id: id,
  monitorId: 'monitor-$id',
  status: 'ongoing',
  insertedAt: insertedAt ?? at(hours ?? 0),
  monitorName: monitorName,
  startedAt: startedAt ?? (hours == null ? null : at(hours)),
  acknowledgedAt: acknowledgedAt,
  resolvedAt: resolvedAt,
);

class _FakeIncidentsRepository implements IncidentsRepository {
  _FakeIncidentsRepository(this.incidents, {this.offline = false});

  final List<Incident> incidents;
  final bool offline;
  int loads = 0;

  @override
  Future<IncidentsData> load() async {
    loads++;
    return IncidentsData(incidents: incidents, offline: offline);
  }
}

Finder _chip(IncidentStatusFilter filter) =>
    find.byKey(ValueKey<String>('incident-filter-${filter.queryValue}'));

/// Whether [filter] reports itself as the selected control.
///
/// Read from the semantics tree by label, so the assertion states the promise
/// the user experiences ("this control is the selected one") rather than the
/// widget class that happens to implement it. The calling test owns a
/// `tester.ensureSemantics()` handle, because that must be disposed inside the
/// test body.
bool _selected(WidgetTester tester, IncidentStatusFilter filter) =>
    tester
        .getSemantics(find.bySemanticsLabel(filter.label))
        .flagsCollection
        .isSelected ==
    Tristate.isTrue;

Future<void> pumpFeed(
  WidgetTester tester,
  IncidentsRepository repo, {
  IncidentStatusFilter? linkFilter,
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [incidentsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: IncidentsScreen(filter: linkFilter),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// One unacknowledged open incident, one acknowledged open incident and one
/// resolved row: the fixture that makes the two filters distinguishable.
final List<Incident> _queue = <Incident>[
  _incident('newer-open', 'Needs attention newer', hours: 5),
  _incident('older-open', 'Needs attention older', hours: 1),
  _incident('acked-open', 'Acknowledged open', hours: 2, acknowledgedAt: at(3)),
  _incident('done', 'Recently resolved', hours: 6, resolvedAt: at(7)),
];

void main() {
  group('filterIncidents', () {
    test('needs acknowledgement keeps only the outstanding queue', () {
      expect(
        filterIncidents(
          _queue,
          status: IncidentStatusFilter.needsAcknowledgement,
        ).map((Incident i) => i.id),
        <String>['older-open', 'newer-open'],
        reason: 'oldest outstanding first, and nothing already acknowledged',
      );
    });

    test('open still includes acknowledged incidents', () {
      expect(
        filterIncidents(
          _queue,
          status: IncidentStatusFilter.open,
        ).map((Incident i) => i.id),
        containsAll(<String>['newer-open', 'older-open', 'acked-open']),
        reason:
            '"open" is about resolved_at; the needs-acknowledgement filter is '
            'the one that drops acknowledged rows',
      );
    });

    test('all keeps the response order untouched', () {
      expect(
        filterIncidents(_queue).map((Incident i) => i.id),
        _queue.map((Incident i) => i.id),
      );
    });
  });

  group('incidentsEmptyMessage', () {
    test('an empty queue never claims there are no open incidents', () {
      expect(
        incidentsEmptyMessage(
          IncidentStatusFilter.needsAcknowledgement,
          hasAny: true,
        ),
        'No incidents need acknowledgement.',
      );
      expect(
        incidentsEmptyMessage(
          IncidentStatusFilter.needsAcknowledgement,
          hasAny: false,
        ),
        'No incidents.',
      );
    });

    test('the open filter keeps its own copy', () {
      expect(
        incidentsEmptyMessage(IncidentStatusFilter.open, hasAny: true),
        'No open incidents.',
      );
      expect(
        incidentsEmptyMessage(IncidentStatusFilter.all, hasAny: false),
        'No incidents.',
      );
    });
  });

  group('incidentFilterFromQuery', () {
    test('round-trips every filter and ignores unknown values', () {
      for (final IncidentStatusFilter filter in IncidentStatusFilter.values) {
        expect(incidentFilterFromQuery(filter.queryValue), filter);
      }
      expect(incidentFilterFromQuery(null), isNull);
      expect(incidentFilterFromQuery('needs-acknowledgement'), isNotNull);
      expect(
        incidentFilterFromQuery('nonsense'),
        isNull,
        reason: 'an unknown value must fall back, not crash the route',
      );
    });
  });

  group('IncidentsScreen', () {
    testWidgets('the needs-acknowledgement filter hides owned and resolved', (
      WidgetTester tester,
    ) async {
      await pumpFeed(tester, _FakeIncidentsRepository(_queue));

      await tester.tap(_chip(IncidentStatusFilter.needsAcknowledgement));
      await tester.pumpAndSettle();

      expect(find.text('Needs attention older'), findsOneWidget);
      expect(find.text('Needs attention newer'), findsOneWidget);
      expect(find.text('Acknowledged open'), findsNothing);
      expect(find.text('Recently resolved'), findsNothing);
    });

    testWidgets('an empty queue with an acknowledged incident says so', (
      WidgetTester tester,
    ) async {
      // Everything still open has been acknowledged, yet one still is: the
      // copy must not say there are no open incidents.
      await pumpFeed(
        tester,
        _FakeIncidentsRepository(<Incident>[
          _incident(
            'acked',
            'Acknowledged open',
            hours: 2,
            acknowledgedAt: at(3),
          ),
          _incident('done', 'Recently resolved', hours: 6, resolvedAt: at(7)),
        ]),
        linkFilter: IncidentStatusFilter.open,
      );
      expect(find.text('Acknowledged open'), findsOneWidget);

      await tester.tap(_chip(IncidentStatusFilter.needsAcknowledgement));
      await tester.pumpAndSettle();
      expect(find.text('No incidents need acknowledgement.'), findsOneWidget);
      expect(
        find.text('No open incidents.'),
        findsNothing,
        reason: 'an incident is still open; only the queue is empty',
      );
    });

    testWidgets('a deep link opens the filter it names', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpFeed(
        tester,
        _FakeIncidentsRepository(_queue),
        linkFilter: IncidentStatusFilter.needsAcknowledgement,
      );

      expect(
        _selected(tester, IncidentStatusFilter.needsAcknowledgement),
        isTrue,
      );
      expect(find.text('Needs attention older'), findsOneWidget);
      expect(find.text('Acknowledged open'), findsNothing);

      // The user can still choose another filter afterwards.
      await tester.tap(_chip(IncidentStatusFilter.all));
      await tester.pumpAndSettle();
      expect(find.text('Acknowledged open'), findsOneWidget);
      expect(_selected(tester, IncidentStatusFilter.all), isTrue);
      handle.dispose();
    });

    testWidgets('no deep link starts on All', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpFeed(tester, _FakeIncidentsRepository(_queue));

      expect(_selected(tester, IncidentStatusFilter.all), isTrue);
      expect(find.text('Recently resolved'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the offline fallback keeps the queue and its honesty', (
      WidgetTester tester,
    ) async {
      await pumpFeed(
        tester,
        _FakeIncidentsRepository(<Incident>[
          _incident('q', 'Needs attention', hours: 1),
        ], offline: true),
        linkFilter: IncidentStatusFilter.needsAcknowledgement,
      );

      expect(find.text('Offline — showing cached data'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
    });

    testWidgets('200% text keeps every filter visible and wraps them', (
      WidgetTester tester,
    ) async {
      await pumpFeed(
        tester,
        _FakeIncidentsRepository(_queue),
        textScaler: const TextScaler.linear(2),
        // A narrow phone, where three labels on one row cannot fit.
        size: const Size(320, 900),
      );

      expect(tester.takeException(), isNull, reason: 'no overflow at 200%');
      for (final IncidentStatusFilter filter in IncidentStatusFilter.values) {
        expect(
          _chip(filter),
          findsOneWidget,
          reason: '${filter.label} must stay reachable at 200% text',
        );
      }

      // Wrapped onto more than one row rather than squeezed onto one: the chips
      // occupy two distinct rows at this width and scale.
      final Set<double> rows = <double>{
        for (final IncidentStatusFilter filter in IncidentStatusFilter.values)
          tester.getTopLeft(_chip(filter)).dy,
      };
      expect(rows.length, greaterThan(1), reason: 'the filters must wrap');

      // Each chip keeps a real tap target even when its text is doubled.
      for (final IncidentStatusFilter filter in IncidentStatusFilter.values) {
        expect(
          tester.getSize(_chip(filter)).height,
          greaterThanOrEqualTo(48),
          reason: '${filter.label} must keep a 48dp target at 200%',
        );
      }

      // And they still work at that size.
      await tester.tap(_chip(IncidentStatusFilter.open));
      await tester.pumpAndSettle();
      expect(find.text('Recently resolved'), findsNothing);
      expect(find.text('Needs attention older'), findsOneWidget);
    });

    testWidgets('the selected filter is announced as selected', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpFeed(
        tester,
        _FakeIncidentsRepository(_queue),
        linkFilter: IncidentStatusFilter.needsAcknowledgement,
      );

      // Located by label, not by key: the promise under test is that the
      // control is announced by name *and* as the selected one.
      final SemanticsNode selected = tester.getSemantics(
        find.bySemanticsLabel('Needs acknowledgement'),
      );
      expect(selected.label, contains('Needs acknowledgement'));
      expect(selected.flagsCollection.isSelected, Tristate.isTrue);
      expect(selected.flagsCollection.isButton, isTrue);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Open'))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      handle.dispose();
    });
  });
}
