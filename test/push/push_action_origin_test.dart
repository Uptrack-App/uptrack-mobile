import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/push/push_message.dart';

/// Lock-screen actions mutate server state (acknowledge, escalate = pages
/// people, snooze) with the user's session. Only a tap on our own
/// notification may start one. These guards fail when an action can be
/// started by an intent or URL that another app can send.
///
/// Android: `MainActivity` is exported (it is the launcher), so anything it
/// reads from its intent is attacker-controlled. Action buttons therefore
/// fire an immutable, explicit PendingIntent to a NON-exported trampoline
/// (`UptrackActionActivity`), which hands the action over in process memory
/// (`PushActionInbox`). `MainActivity` never reads an action from an intent.
void main() {
  const String kt = 'android/app/src/main/kotlin/app/uptrack/uptrack_mobile/';
  final String manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();
  final String mainActivity = File('${kt}MainActivity.kt').readAsStringSync();
  final String intents = File('${kt}UptrackNotificationIntents.kt')
      .readAsStringSync();
  final String swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();

  String? activityBlock(String name) => RegExp(
    '<activity\\s[^>]*android:name="\\.$name"[\\s\\S]*?(/>|</activity>)',
  ).firstMatch(manifest)?.group(0);

  group('Android: an action can only come from our own PendingIntent', () {
    test('the trampoline is not exported and has no intent filter', () {
      final String? block = activityBlock('UptrackActionActivity');
      expect(block, isNotNull, reason: 'no trampoline declared');
      expect(block, contains('android:exported="false"'));
      expect(block, isNot(contains('<intent-filter')));
    });

    test('action buttons target the trampoline with an immutable intent', () {
      final String fn = RegExp(r'fun actionIntent\([\s\S]*?\n    \}')
          .firstMatch(intents)!
          .group(0)!;
      expect(
        fn,
        contains('Intent(context, UptrackActionActivity::class.java)'),
      );
      expect(fn, isNot(contains('MainActivity::class.java')));
      expect(intents, contains('PendingIntent.FLAG_IMMUTABLE'));
    });

    test('MainActivity never reads an action from its (exported) intent', () {
      for (final String forbidden in <String>[
        'EXTRA_ACTION',
        'EXTRA_TARGET_ID',
        'EXTRA_TARGET_KIND',
        'uptrack_action',
        'actionPayload(',
      ]) {
        expect(
          mainActivity,
          isNot(contains(forbidden)),
          reason: 'a forged startActivity could set $forbidden',
        );
      }
      expect(mainActivity, contains('PushActionInbox.take()'));
    });

    test('only the trampoline puts actions in the inbox', () {
      final Directory dir = Directory(kt);
      final List<String> writers = <String>[
        for (final FileSystemEntity f in dir.listSync())
          if (f is File &&
              f.path.endsWith('.kt') &&
              f.readAsStringSync().contains('PushActionInbox.put('))
            f.uri.pathSegments.last,
      ];
      expect(writers, <String>['UptrackActionActivity.kt']);
    });

    test('a plain tap only navigates and its ids are sanitized', () {
      final String tap = RegExp(r'private fun tapPayload\([\s\S]*?\n    \}')
          .firstMatch(mainActivity)!
          .group(0)!;
      expect(tap, contains('UptrackNotificationIntents.sanitizeId('));
      expect(tap, isNot(contains('"action"')));
    });
  });

  group('Dart: a forged tap can only navigate to a detail screen', () {
    test('ids outside the server alphabet produce no route', () {
      for (final String bad in <String>[
        '../settings',
        'x?filter=all',
        'a/b',
        '%2e%2e',
        ' ',
      ]) {
        expect(PushMessage(incidentId: bad).routeLocation, isNull, reason: bad);
        expect(PushMessage(monitorId: bad).routeLocation, isNull, reason: bad);
      }
      expect(
        const PushMessage(incidentId: '5f0c1c9e-0000-4000-8000-000000000001')
            .routeLocation,
        '/incidents/5f0c1c9e-0000-4000-8000-000000000001',
      );
    });

    test('only the push channel creates an action request', () {
      final List<String> callers = <String>[
        for (final FileSystemEntity f in Directory(
          'lib',
        ).listSync(recursive: true))
          if (f is File &&
              f.path.endsWith('.dart') &&
              RegExp(r'PushActionRequest\.fromMap\(|\.handleAction\(')
                  .hasMatch(f.readAsStringSync()))
            f.path,
      ];
      expect(callers, <String>['lib/push/push_service.dart']);
    });
  });

  group('iOS: actions come only from the system notification response', () {
    test('no URL handler can start an action', () {
      final String scene = File('ios/Runner/SceneDelegate.swift')
          .readAsStringSync();
      for (final String source in <String>[swift, scene]) {
        expect(source, isNot(contains('openURLContexts')));
        expect(source, isNot(contains('open url: URL')));
      }
      // The action event is sent from one place: didReceive response.
      expect(RegExp('"onNotificationAction"').allMatches(swift), hasLength(1));
      final String didReceive = RegExp(
        r'didReceive response: UNNotificationResponse[\s\S]*?\n  \}',
      ).firstMatch(swift)!.group(0)!;
      expect(didReceive, contains('"onNotificationAction"'));
    });
  });
}
