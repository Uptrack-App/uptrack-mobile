import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/features/settings/appearance_section.dart';
import 'package:uptrack_mobile/theme/app_theme.dart';
import 'package:uptrack_mobile/theme/appearance.dart';

class _BrokenPersistence implements AppearancePersistence {
  @override
  Future<String?> read() async => throw StateError('disk gone');

  @override
  Future<void> write(String value) async => throw StateError('disk gone');
}

void main() {
  test('load restores the saved choice', () async {
    final Appearance a = Appearance(MemoryAppearancePersistence('dark'));
    await a.load();
    expect(a.mode, ThemeMode.dark);
  });

  test('missing or unknown value keeps system', () async {
    final Appearance none = Appearance(MemoryAppearancePersistence());
    await none.load();
    expect(none.mode, ThemeMode.system);

    final Appearance junk = Appearance(MemoryAppearancePersistence('purple'));
    await junk.load();
    expect(junk.mode, ThemeMode.system);
  });

  test('setMode saves the choice and notifies once', () async {
    final MemoryAppearancePersistence store = MemoryAppearancePersistence();
    final Appearance a = Appearance(store);
    int calls = 0;
    a.addListener(() => calls++);

    await a.setMode(ThemeMode.light);
    await a.setMode(ThemeMode.light);

    expect(a.mode, ThemeMode.light);
    expect(store.value, 'light');
    expect(calls, 1);
  });

  test('a broken store never throws and the choice still applies', () async {
    final Appearance a = Appearance(_BrokenPersistence());
    await a.load();
    await a.setMode(ThemeMode.dark);
    expect(a.mode, ThemeMode.dark);
  });

  testWidgets('Settings > Appearance switches the app theme', (
    WidgetTester tester,
  ) async {
    final MemoryAppearancePersistence store = MemoryAppearancePersistence();
    final Appearance appearance = Appearance(store);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appearanceProvider.overrideWithValue(appearance)],
        child: ListenableBuilder(
          listenable: appearance,
          builder: (BuildContext context, Widget? _) => MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: appearance.mode,
            home: const Scaffold(body: AppearanceSection()),
          ),
        ),
      ),
    );
    expect(find.text('Follows your device setting.'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(appearance.mode, ThemeMode.dark);
    expect(store.value, 'dark');
    expect(
      Theme.of(tester.element(find.byType(AppearanceSection))).brightness,
      Brightness.dark,
    );
    expect(find.text('Saved on this device.'), findsOneWidget);
  });
}
