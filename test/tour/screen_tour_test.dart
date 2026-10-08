/// Screen tour: renders every main screen of the real demo app (and the
/// sign-in screen) at iPhone size in light and dark, for design review.
///
/// Off by default so CI never runs it. Render with:
///   flutter test test/tour/screen_tour_test.dart --dart-define=TOUR=true \
///     --update-goldens
/// PNGs land in test/tour/out/ (git-ignored).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/demo_session.dart';
import 'package:uptrack_mobile/features/auth/login_screen.dart';
import 'package:uptrack_mobile/features/auth/social_login.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/push/push_service.dart';
import 'package:uptrack_mobile/theme/app_theme.dart';
import 'package:uptrack_mobile/util/date_format.dart';

const bool _tour = bool.fromEnvironment('TOUR');

/// iPhone 15-class logical size and insets.
const Size _phone = Size(390, 844);
const double _dpr = 2;

class _NoPush extends PushService {
  _NoPush()
    : super(
        registerToken: ({
          required String platform,
          required String token,
          String? environment,
        }) async {},
        onNavigate: (String location) {},
      );

  @override
  Future<void> initialize() async {}
}

Future<void> _loadFonts() async {
  const families = <String, List<String>>{
    'MaterialIcons': <String>['fonts/MaterialIcons-Regular.otf'],
    'IBMPlexSans': <String>[
      'assets/fonts/IBMPlexSans-Regular.ttf',
      'assets/fonts/IBMPlexSans-Medium.ttf',
      'assets/fonts/IBMPlexSans-SemiBold.ttf',
    ],
    'IBMPlexMono': <String>[
      'assets/fonts/IBMPlexMono-Regular.ttf',
      'assets/fonts/IBMPlexMono-Medium.ttf',
    ],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final asset in entry.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
}

void _setPhone(WidgetTester tester, {double height = 844}) {
  tester.view.physicalSize = Size(_phone.width * _dpr, height * _dpr);
  tester.view.devicePixelRatio = _dpr;
  tester.view.padding = const FakeViewPadding(
    top: 47 * _dpr,
    bottom: 34 * _dpr,
  );
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  // Demo requests resolve on real futures; let them land, then settle.
  for (int i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

const Map<String, String> _routes = <String, String>{
  'dashboard': '/',
  'monitors': '/monitors',
  'monitor_detail': '/monitors/demo-api',
  'incidents': '/incidents',
  'incident_detail': '/incidents/demo-incident',
  'settings': '/settings',
  'status': '/status?slug=demo',
};

void main() {
  setUpAll(() async {
    displayTimeZone = (DateTime t) => t.toUtc();
    await _loadFonts();
  });

  for (final Brightness b in Brightness.values) {
    final String mode = b == Brightness.dark ? 'dark' : 'light';

    for (final MapEntry<String, String> r in _routes.entries) {
      for (final bool tall in <bool>[false, true]) {
        final String name = '${r.key}_$mode${tall ? '_full' : ''}';
        testWidgets('tour $name', skip: !_tour, (WidgetTester tester) async {
          _setPhone(tester, height: tall ? 2200 : 844);
          tester.platformDispatcher.platformBrightnessTestValue = b;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          await tester.pumpWidget(
            UptrackDemoApp(
              onExit: () {},
              initialLocation: r.value,
              pushService: _NoPush(),
            ),
          );
          await _settle(tester);
          await expectLater(
            find.byType(UptrackDemoApp),
            matchesGoldenFile('out/$name.png'),
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await _settle(tester);
        });
      }
    }

    testWidgets('tour login_$mode', skip: !_tour, (WidgetTester tester) async {
      _setPhone(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
            socialProvidersProvider.overrideWith((ref) async => <String>{}),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: b == Brightness.dark ? AppTheme.dark : AppTheme.light,
            home: const LoginScreen(),
          ),
        ),
      );
      await _settle(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('out/login_$mode.png'),
      );
    });
  }
}
