import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/widgets/widget_store.dart';

/// R5 platform-channel class contract for the Android home widget.
///
/// The bug this pins: `home_widget` 0.10.0 resolves a bare `androidName`
/// against `Context.packageName` (the *application id*), while the provider
/// class is declared in the `namespace` package. The two differ here, so the
/// unqualified name resolved to a class that does not exist and every refresh
/// failed. These tests assert what actually crosses the channel and that the
/// constant still matches the real Gradle/manifest/Kotlin sources, so a future
/// namespace or class rename cannot silently break widget updates again.
///
/// They prove the plugin dispatch contract only — not launcher placement,
/// rendering or receiver lifecycle. That remains a native gate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('home_widget');
  final List<MethodCall> calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  /// `setAppGroupId` also crosses this channel; only the widget-class dispatch
  /// is under test here.
  List<MethodCall> updateWidgetCalls() =>
      calls.where((MethodCall call) => call.method == 'updateWidget').toList();

  group('HomeWidgetStore.refresh channel contract', () {
    test('sends updateWidget with the exact qualified native class', () async {
      final bool? result = await const HomeWidgetStore().refresh();

      expect(result, isTrue);
      final List<MethodCall> updates = updateWidgetCalls();
      expect(updates, hasLength(1));
      expect(updates.single.method, 'updateWidget');
      final Map<Object?, Object?> args =
          updates.single.arguments as Map<Object?, Object?>;
      // The value home_widget passes straight to Class.forName.
      expect(
        args['qualifiedAndroidName'],
        'app.uptrack.uptrack_mobile.UptrackStatusWidgetProvider',
      );
      expect(args['qualifiedAndroidName'], kAndroidWidgetProviderClass);
      // The iOS kind is a separate argument; the Android fix must not disturb
      // it (no iOS runtime claim is made or tested here).
      expect(args['ios'], kIosWidgetKind);
      expect(args['ios'], 'UptrackStatusWidget');
    });

    test('never sends a package-name-resolved androidName', () async {
      await const HomeWidgetStore().refresh();

      final Map<Object?, Object?> args =
          updateWidgetCalls().single.arguments as Map<Object?, Object?>;
      // `androidName`/`name` are resolved against the application id, which is
      // not this provider's package. Omitting them is the fix; sending them
      // would reintroduce the bug if the plugin ever preferred them.
      expect(args['android'], isNull);
      expect(args['name'], isNull);
    });
  });

  group('binding against the Android sources', () {
    test('qualified name is namespace + manifest receiver, not applicationId', () {
      final String gradle = File('android/app/build.gradle.kts')
          .readAsStringSync();
      final String manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      final String provider = File(
        'android/app/src/main/kotlin/app/uptrack/uptrack_mobile/'
        'UptrackStatusWidgetProvider.kt',
      ).readAsStringSync();

      final String namespace = _gradleValue(gradle, 'namespace');
      final String applicationId = _gradleValue(gradle, 'applicationId');
      final String receiver = _receiverName(manifest);

      expect(namespace, 'app.uptrack.uptrack_mobile');
      expect(applicationId, 'app.uptrack.mobile');
      expect(receiver, '.UptrackStatusWidgetProvider');
      // Manifest entries are relative to the namespace...
      expect(
        kAndroidWidgetProviderClass,
        '$namespace$receiver',
        reason: 'Dart must address the class the manifest actually declares',
      );
      // ...and that is NOT what package-name resolution would have produced.
      expect(
        '$applicationId$receiver',
        isNot(kAndroidWidgetProviderClass),
        reason: 'the two ids differ; that difference is the whole bug',
      );
      // The Kotlin source agrees, and still names the class home_widget loads.
      expect(provider, contains('package $namespace'));
      expect(provider, contains('class $kAndroidWidgetProviderSimpleName :'));
      expect(kAndroidWidgetProviderSimpleName, 'UptrackStatusWidgetProvider');
    });
  });
}

String _gradleValue(String gradle, String key) {
  final RegExpMatch? match = RegExp('$key\\s*=\\s*"([^"]+)"')
      .firstMatch(gradle);
  expect(match, isNotNull, reason: 'no $key in build.gradle.kts');
  return match!.group(1)!;
}

String _receiverName(String manifest) {
  final RegExpMatch? match = RegExp(r'<receiver\s+android:name="(\.[^"]+)"')
      .firstMatch(manifest);
  expect(match, isNotNull, reason: 'no relative widget receiver in manifest');
  return match!.group(1)!;
}
