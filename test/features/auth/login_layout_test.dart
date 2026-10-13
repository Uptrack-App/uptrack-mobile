import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/features/auth/login_screen.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/social_login.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/theme/app_theme.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'login supports large text and reduced motion in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
              socialProvidersProvider.overrideWith(
                (ref) async => {'google', 'github'},
              ),
            ],
            child: MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: const LoginScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final animation
            in tester.widgetList<TweenAnimationBuilder<double>>(
              find.byType(TweenAnimationBuilder<double>),
            )) {
          expect(animation.duration, Duration.zero);
        }
        expect(find.widgetWithText(TextFormField, 'Password'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Email me a sign-in link'),
          200,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Email me a sign-in link'));
        await tester.pumpAndSettle();
        expect(find.text('Enter your email'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
