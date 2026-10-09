import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/widgets/widget_group.dart';

/// Guards the iOS identity the server and Apple both depend on.
///
/// The server sends pushes to the bundle id in `APNS_BUNDLE_ID` (default
/// `app.uptrack.mobile`) and Live Activity pushes to
/// `<bundle id>.push-type.liveactivity`. If the Xcode project drifts from
/// this id, pushes fail silently, so the project is checked as text.
const String _bundleId = 'app.uptrack.mobile';
const String _widgetsBundleId = 'app.uptrack.mobile.widgets';

String _read(String path) => File(path).readAsStringSync();

Set<String> _bundleIds(String pbxproj) {
  return RegExp(
    r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);',
  ).allMatches(pbxproj).map((RegExpMatch m) => m.group(1)!.trim()).toSet();
}

void main() {
  final String pbxproj = _read('ios/Runner.xcodeproj/project.pbxproj');

  test('the app, its tests and the widget extension use the locked ids', () {
    expect(_bundleIds(pbxproj), <String>{
      _bundleId,
      '$_bundleId.RunnerTests',
      _widgetsBundleId,
    });
  });

  test('the old camel-case id is gone', () {
    expect(pbxproj, isNot(contains('uptrackMobile')));
  });

  test('the minimum iOS version is 16.0 for every target', () {
    final Set<String> targets = RegExp(
      r'IPHONEOS_DEPLOYMENT_TARGET = ([^;]+);',
    ).allMatches(pbxproj).map((RegExpMatch m) => m.group(1)!.trim()).toSet();
    expect(targets, <String>{'16.0'});
  });

  test('both entitlement files carry the app group the Dart side uses', () {
    final String app = _read('ios/Runner/UptrackMobile.entitlements');
    final String ext = _read('ios/UptrackWidgets/UptrackWidgets.entitlements');
    expect(app, contains('<string>${WidgetGroup.appGroupId}</string>'));
    expect(ext, contains('<string>${WidgetGroup.appGroupId}</string>'));
  });

  test('the app entitles push and time-sensitive alerts', () {
    final String app = _read('ios/Runner/UptrackMobile.entitlements');
    expect(app, contains('<key>aps-environment</key>'));
    expect(
      app,
      contains('<key>com.apple.developer.usernotifications.time-sensitive</key>'),
    );
  });

  test('the extension is a WidgetKit extension with its own entry point', () {
    final String plist = _read('ios/UptrackWidgets/Info.plist');
    expect(plist, contains('com.apple.widgetkit-extension'));
    expect(_read('ios/Runner/Widget/UptrackWidgets.swift'), contains('@main'));
  });

  test('the Live Activity attributes keep the name the server sends', () {
    final String shared = _read('ios/Shared/UptrackIncidentAttributes.swift');
    expect(shared, contains('struct UptrackIncident: ActivityAttributes'));
  });

  // v1 ships for iPhone only. An iPad target makes App Store Connect require
  // iPad screenshots and App Review test the iPad layout.
  test('every target builds for iPhone only', () {
    final Set<String> families = RegExp(
      r'TARGETED_DEVICE_FAMILY = ([^;]+);',
    ).allMatches(pbxproj).map((RegExpMatch m) => m.group(1)!.trim()).toSet();
    expect(families, <String>{'1'});
  });

  // The app uses only HTTPS (exempt encryption). Without this key App Store
  // Connect asks the export-compliance question on every upload.
  test('the app declares exempt encryption', () {
    final String plist = _read('ios/Runner/Info.plist');
    expect(
      plist,
      matches(RegExp(r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>')),
    );
  });

  // A file on disk is not enough: Xcode copies only files that the Runner
  // target's resources phase lists. Without it the app ships no manifest.
  test('the Runner target bundles the app privacy manifest', () {
    expect(File('ios/Runner/PrivacyInfo.xcprivacy').existsSync(), isTrue);
    expect(pbxproj, contains('PrivacyInfo.xcprivacy in Resources'));
  });
}
