import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uptrack_mobile/app.dart';
import 'package:uptrack_mobile/theme/app_theme.dart';

void main() {
  testWidgets('dark app theme builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: Text('Dark theme')),
      ),
    );

    expect(find.text('Dark theme'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Dark theme'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('app shell shows dashboard and navigates to monitors', (
    WidgetTester tester,
  ) async {
    final GoRouter router = createRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [routerProvider.overrideWithValue(router)],
        child: const UptrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);

    router.go('/monitors');
    await tester.pumpAndSettle();

    expect(find.text('Monitors'), findsOneWidget);
  });
}
