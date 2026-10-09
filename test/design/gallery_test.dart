import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/design/gallery/main.dart';
import 'package:uptrack_mobile/design/uptrack_design.dart';

Future<void> loadFonts() async {
  for (final family in {
    'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
    'InstrumentSans': [
      'assets/fonts/InstrumentSans-Regular.ttf',
      'assets/fonts/InstrumentSans-Medium.ttf',
      'assets/fonts/InstrumentSans-SemiBold.ttf',
    ],
    'JetBrainsMono': [
      'assets/fonts/JetBrainsMono-Regular.ttf',
      'assets/fonts/JetBrainsMono-Medium.ttf',
    ],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final file in family.value) {
      loader.addFont(rootBundle.load(file));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(loadFonts);
  for (final dark in [false, true]) {
    testWidgets('compact 200% gallery ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: GalleryExamples()),
          ),
        ),
      );
      await tester.runAsync(() => precacheImage(
        AssetImage(dark ? 'assets/brand/uptrack-wordmark-dark.png' : 'assets/brand/uptrack-wordmark-light.png'),
        tester.element(find.byType(UptrackBrand)),
      ));
      // Busy/loading fixtures deliberately animate forever; capture a stable frame.
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/gallery_compact_${dark ? 'dark' : 'light'}.png',
        ),
      );
    });
  }

  for (final dark in [false, true]) {
    testWidgets('feedback states ${dark ? 'dark' : 'light'}', (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const UptrackNotice(
                    message: 'Offline — showing cached data',
                    kind: UptrackNoticeKind.offline,
                  ),
                  UptrackNotice(
                    message: 'Could not revoke this device.',
                    kind: UptrackNoticeKind.error,
                    actionLabel: 'Refresh',
                    onAction: () {},
                  ),
                  const UptrackStateView(
                    message: 'No monitors match these filters.',
                  ),
                  UptrackStateView(
                    message: 'No cached data. Connect and refresh.',
                    actionLabel: 'Refresh',
                    onAction: () {},
                  ),
                  const UptrackMetricTile(
                    label: 'Average uptime',
                    value: null,
                    detail: 'No measurements in this period',
                  ),
                  const UptrackLifecycleBadge(open: true, acknowledged: true),
                  const UptrackStatusBadge(status: 'unrecognized'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/feedback_${dark ? 'dark' : 'light'}.png'),
      );
    });
  }

  testWidgets('confirmation cancels safely at large text and returns focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              focusNode: focus,
              autofocus: true,
              child: const Text('Open confirmation'),
              onPressed: () async {
                result = await showUptrackConfirmation(
                  context,
                  title: 'Revoke device?',
                  message: 'This device will be signed out.',
                  confirmLabel: 'Revoke device',
                  destructive: true,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open confirmation'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/confirmation_compact.png'),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    expect(focus.hasFocus, isTrue);
  });
}
