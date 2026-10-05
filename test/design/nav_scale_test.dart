import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/design/uptrack_design.dart';

Finder _destination(int index) =>
    find.byKey(ValueKey<String>('destination-$index'));

Future<void> pumpNav(
  WidgetTester tester, {
  required double width,
  required double textScale,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  int selected = 0;
  await tester.pumpWidget(
    StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) => MaterialApp(
        theme: AppTheme.light,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: UptrackAdaptiveScaffold(
          selectedIndex: selected,
          onDestinationSelected: (int index) =>
              setState(() => selected = index),
          child: const Scaffold(
            body: UptrackMetricTile(label: 'Average uptime', value: '99.9%'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('adaptive navigation at 200% text', () {
    for (final double width in <double>[320, 390]) {
      testWidgets('bar at $width shows only the selected label', (
        WidgetTester tester,
      ) async {
        await pumpNav(tester, width: width, textScale: 2);

        expect(tester.takeException(), isNull, reason: 'no overflow at 200%');
        final NavigationBar bar = tester.widget<NavigationBar>(
          find.byType(NavigationBar),
        );
        expect(
          bar.labelBehavior,
          NavigationDestinationLabelBehavior.onlyShowSelected,
          reason: 'four doubled labels do not fit a phone-width bar',
        );

        // Tapping another destination moves the visible label with it.
        await tester.tap(_destination(2));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .labelBehavior,
          NavigationDestinationLabelBehavior.onlyShowSelected,
        );
        expect(
          tester
              .widget<UptrackAdaptiveScaffold>(
                find.byType(UptrackAdaptiveScaffold),
              )
              .selectedIndex,
          2,
        );
      });
    }

    testWidgets('every destination stays named and reachable', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpNav(tester, width: 390, textScale: 2);

      for (var i = 0; i < UptrackAdaptiveScaffold.labels.length; i++) {
        final String label = UptrackAdaptiveScaffold.labels[i];
        // The tooltip is the long-press affordance, and it survives the label
        // being hidden.
        expect(find.byTooltip(label), findsOneWidget, reason: '$label tooltip');
        final SemanticsNode node = tester.getSemantics(_destination(i));
        expect(
          node.label,
          contains(label),
          reason: '$label must still be announced by name',
        );
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
          reason: '$label must remain tappable',
        );
        expect(
          node.flagsCollection.isSelected,
          i == 0 ? Tristate.isTrue : Tristate.isFalse,
          reason: 'only the selected destination reports itself selected',
        );
      }
      handle.dispose();
    });

    testWidgets('normal text keeps every label visible', (
      WidgetTester tester,
    ) async {
      await pumpNav(tester, width: 390, textScale: 1);

      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).labelBehavior,
        NavigationDestinationLabelBehavior.alwaysShow,
      );
      for (final String label in UptrackAdaptiveScaffold.labels) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('the wide rail still fits at 200% text', (
      WidgetTester tester,
    ) async {
      await pumpNav(tester, width: 1024, textScale: 2);

      expect(tester.takeException(), isNull);
      final NavigationRail rail = tester.widget<NavigationRail>(
        find.byType(NavigationRail),
      );
      expect(
        rail.extended,
        isFalse,
        reason: 'the extended rail cannot hold four doubled labels',
      );
      expect(rail.labelType, NavigationRailLabelType.all);
    });
  });
}
