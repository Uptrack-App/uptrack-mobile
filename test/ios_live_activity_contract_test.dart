import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/push/push_channels.dart';
import 'package:uptrack_mobile/widgets/live_activity.dart';
import 'package:uptrack_mobile/widgets/live_activity_sync.dart';

/// Guards the native Live Activity contract as text (I2.2, I2.3): the Swift
/// side cannot run under `flutter test`, but its names and build settings
/// can drift from the Dart side without any compile error.
String _read(String path) => File(path).readAsStringSync();

void main() {
  final String pbxproj = _read('ios/Runner.xcodeproj/project.pbxproj');
  final String appDelegate = _read('ios/Runner/AppDelegate.swift');
  final String bridge = _read('ios/Runner/UptrackLiveActivityBridge.swift');
  final String logic = _read('ios/Runner/UptrackLiveActivityLogic.swift');
  final String attributes = _read('ios/Shared/UptrackIncidentAttributes.swift');

  test('the app weak-links ActivityKit in every configuration (I2.3)', () {
    // iOS 16.0 has no ActivityKit; a strong link stops the app at launch.
    final int weak = RegExp(r'"-weak_framework",\s*ActivityKit,')
        .allMatches(pbxproj)
        .length;
    expect(weak, 3, reason: 'Debug, Release and Profile of Runner');
  });

  test('the app declares Live Activity support', () {
    final String plist = _read('ios/Runner/Info.plist');
    expect(
      plist,
      matches(RegExp(r'<key>NSSupportsLiveActivities</key>\s*<true/>')),
    );
  });

  test('the bridge sources are in the Runner target', () {
    for (final String file in <String>[
      'UptrackLiveActivityBridge.swift in Sources',
      'UptrackLiveActivityLogic.swift in Sources',
    ]) {
      // One build file entry plus one sources-phase entry.
      expect(
        RegExp(RegExp.escape(file)).allMatches(pbxproj).length,
        2,
        reason: file,
      );
    }
  });

  test('channel and method names match the Dart side', () {
    expect(logic, contains('"$kLiveActivityChannel"'));
    expect(bridge, contains('"${PushEventMethods.onLiveActivityToken}"'));
    expect(bridge, contains('"${PushEventMethods.onLiveActivityEnded}"'));
    expect(
      appDelegate,
      contains('"${PushTokenMethods.getLiveActivityTokens}"'),
    );
    for (final String method in <String>['list', 'start', 'end']) {
      expect(bridge, contains('case "$method":'), reason: method);
    }
  });

  test('Live Activity tokens carry the APNs environment of the build', () {
    // One source for the environment: the push-token payload and the bridge
    // both use AppDelegate.apnsEnvironment() (Debug = sandbox).
    expect(logic, contains('"environment": environment'));
    expect(
      RegExp(r'"environment": environment').allMatches(logic).length,
      2,
      reason: 'update and push-to-start payloads',
    );
    expect(
      appDelegate,
      contains(
        'UptrackLiveActivityBridge(environment: Self.apnsEnvironment())',
      ),
    );
    expect(
      appDelegate,
      matches(
        RegExp(r'#if DEBUG\s*return "sandbox"\s*#else\s*return "production"'),
      ),
    );
    expect(bridge, contains('environment: environment'));
  });

  test('the attributes type and keys match the server payload', () {
    expect(
      attributes,
      contains('struct $kLiveActivityAttributesType: ActivityAttributes'),
    );
    for (final String key in <String>[
      'let incidentId: String',
      'let monitorName: String',
      'var title: String',
      'var body: String',
      'var status: String',
    ]) {
      expect(attributes, contains(key));
    }
  });

  test('logout ends activities on iOS 16.1, not only on 16.2+', () {
    expect(
      appDelegate,
      contains(
        'if #available(iOS 16.1, *) {\n'
        '          UptrackLiveActivityBridge.endAll()',
      ),
    );
    expect(appDelegate, isNot(contains('Activity<UptrackIncident>')));
  });

  test('ActivityKit use in the app target sits behind iOS 16.1 checks', () {
    expect(bridge, contains('@available(iOS 16.1, *)\nfinal class'));
    expect(attributes, contains('@available(iOS 16.1, *)\nstruct'));
    expect(logic, isNot(contains('import ActivityKit')));
    expect(appDelegate, isNot(contains('import ActivityKit')));
  });
}
