import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/features/auth/demo_session.dart';

/// Lets the demo's HTTP + Drift work settle: both use timers and isolates that
/// never settle under fake-async `pumpAndSettle` alone.
Future<void> settleData(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
    () async => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

/// A phone-shaped view with a status bar and a gesture bar.
void _phoneWithInsets(
  WidgetTester tester, {
  double top = 44,
  double bottom = 34,
}) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: top, bottom: bottom);
  tester.view.viewPadding = FakeViewPadding(top: top, bottom: bottom);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

void main() {
  group('demo session insets', () {
    testWidgets('the banner consumes the status bar exactly once', (
      WidgetTester tester,
    ) async {
      _phoneWithInsets(tester);

      await tester.pumpWidget(DemoSessionScreen(onExit: () {}));
      await settleData(tester);

      // The sample-data banner keeps its own status-bar inset.
      expect(find.text('Demo · sample data'), findsOneWidget);
      expect(find.text('Exit demo'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Demo · sample data')).dy,
        greaterThanOrEqualTo(44),
        reason: 'the banner must still clear the status bar',
      );

      // The routed screen underneath starts immediately below the banner and its
      // app bar is a plain toolbar. Before the fix the child inherited the
      // status-bar padding the banner had already consumed, which added a blank
      // band the height of the status bar above every demo screen.
      final Rect appBar = tester.getRect(find.byType(AppBar));
      final Rect banner = tester.getRect(
        find.ancestor(
          of: find.text('Demo · sample data'),
          matching: find.byType(Material),
        ),
      );
      expect(
        appBar.top,
        banner.bottom,
        reason: 'no gap above the routed app bar',
      );
      expect(
        appBar.height,
        lessThanOrEqualTo(kToolbarHeight + 4),
        reason: 'the app bar must not reserve the status bar a second time',
      );
      expect(find.text('Dashboard'), findsWidgets);
    });

    testWidgets('the bottom gesture inset still reaches the routed screens', (
      WidgetTester tester,
    ) async {
      _phoneWithInsets(tester);

      await tester.pumpWidget(DemoSessionScreen(onExit: () {}));
      await settleData(tester);

      final Iterable<MediaQueryData> paddings = tester
          .widgetList<MediaQuery>(find.byType(MediaQuery))
          .map((MediaQuery m) => m.data);
      expect(
        paddings.any(
          (MediaQueryData m) => m.padding.bottom == 34 && m.padding.top == 0,
        ),
        isTrue,
        reason:
            'only the consumed top padding is dropped; the gesture bar inset '
            'must survive for the routed screens',
      );
      // The shell's navigation bar stays inside the gesture area rather than
      // under it.
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        tester.getRect(find.byType(NavigationBar)).bottom,
        844,
        reason: 'the bar spans to the bottom edge and insets itself',
      );
    });

    testWidgets('a screen outside the demo keeps its own status-bar inset', (
      WidgetTester tester,
    ) async {
      _phoneWithInsets(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(appBar: AppBar(title: Text('Plain screen'))),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(AppBar)).height,
        greaterThanOrEqualTo(kToolbarHeight + 44),
        reason:
            'outside the demo nothing has consumed the status bar, so the app '
            'bar must still reserve it',
      );
    });
  });
}
