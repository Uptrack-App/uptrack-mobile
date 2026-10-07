/// App Store screenshots: the real app in demo mode, one screen per test.
///
/// Each test opens the demo at one route, lets it load, prints
/// `SHOT_READY <name>` and holds the frame for a few seconds. The host
/// captures the simulator meanwhile, so the shot includes the real iOS status
/// bar (see tool/ios_store_screenshots.sh). Demo data needs no account and no
/// network.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uptrack_mobile/features/auth/demo_session.dart';

const List<(String, String)> _shots = <(String, String)>[
  ('01-dashboard', '/'),
  ('02-incident', '/incidents/${DemoAdapter.openIncidentId}'),
  ('03-incidents', '/incidents'),
  ('04-monitor', '/monitors/demo-checkout'),
  ('05-monitors', '/monitors'),
  ('06-settings', '/settings'),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final (String name, String location) in _shots) {
    testWidgets(name, (WidgetTester tester) async {
      await tester.pumpWidget(
        UptrackDemoApp(key: UniqueKey(), onExit: () {}, initialLocation: location),
      );
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // ignore: avoid_print
      print('SHOT_READY $name');
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 5)));
    });
  }
}
