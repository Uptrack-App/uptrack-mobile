import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/push/fcm_data.dart';
import 'package:uptrack_mobile/push/push_channels.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/push/push_presentation.dart';
import 'package:uptrack_mobile/push/push_service.dart';
import 'package:uptrack_mobile/widgets/widget_snapshot.dart';
import 'package:uptrack_mobile/widgets/widget_store.dart';

/// Plan item 4.5: severity, per-user overrides and quiet hours change how a
/// push is shown.
///
/// The server resolves the per-user override and the quiet-hours downgrade
/// (`resolve_interruption_level` + `effective_interruption_override` in
/// uptrack-server `push_apns.rs` / `push_fanout.rs`) and puts the result in
/// `aps.interruption-level` (iOS) and the FCM `android.priority` (NORMAL only
/// for `passive`). These tests feed the client the payloads the server
/// really sends and check what the user sees.

/// What Swift `messagePayload` forwards for a server APNs payload while the
/// app is in the foreground.
Map<String, Object?> iosForeground({
  required String severity,
  required String level,
}) => <String, Object?>{
  'title': 'DB primary is DOWN',
  'body': 'Connection refused',
  'incident_id': '5f0c1c9e-0000-4000-8000-000000000001',
  'severity': severity,
  'interruption_level': level,
  'presented_by_os': 'true',
  'collapse_key': '5f0c1c9e-0000-4000-8000-000000000001',
};

/// What Kotlin `onMessageReceived` forwards for a server FCM message while
/// the app is in the foreground. `interruption_level` is present only when
/// the message arrived with NORMAL priority (server: `passive` only).
Map<String, Object?> androidForeground({
  required String severity,
  bool normalPriority = false,
}) => <String, Object?>{
  'title': 'DB primary is DOWN',
  'body': 'Connection refused',
  'incident_id': '5f0c1c9e-0000-4000-8000-000000000001',
  'severity': severity,
  if (normalPriority) 'interruption_level': 'passive',
};

class _RecordingNotifier implements LocalNotifier {
  final List<PushMessage> shown = <PushMessage>[];

  @override
  Future<void> initialize({
    required void Function(PushMessage message) onTap,
  }) async {}

  @override
  Future<PushMessage?> initialNotification() async => null;

  @override
  Future<void> showForeground(PushMessage message) async => shown.add(message);
}

class _RecordingRefresher implements WidgetRefresher {
  final List<PushMessage> applied = <PushMessage>[];

  @override
  Future<WidgetUpdateAction> applyPush(PushMessage message) async {
    applied.add(message);
    return WidgetUpdateAction.update;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('interruption level (mirrors the server)', () {
    test('severity defaults when the payload has no level', () {
      PushInterruptionLevel level(String? s) =>
          PushPresentation.levelFor(severity: s);
      expect(level('p1'), PushInterruptionLevel.timeSensitive);
      expect(level('p2'), PushInterruptionLevel.timeSensitive);
      expect(level('p3'), PushInterruptionLevel.active);
      expect(level('info'), PushInterruptionLevel.passive);
      expect(level('p9'), PushInterruptionLevel.active);
      expect(level(''), PushInterruptionLevel.active);
      expect(level(null), PushInterruptionLevel.active);
    });

    test('the server-resolved level wins; unknown values are ignored', () {
      // p1 with the user override `passive`.
      expect(
        PushPresentation.levelFor(severity: 'p1', interruptionLevel: 'passive'),
        PushInterruptionLevel.passive,
      );
      // info with the user override `time-sensitive`.
      expect(
        PushPresentation.levelFor(
          severity: 'info',
          interruptionLevel: 'time-sensitive',
        ),
        PushInterruptionLevel.timeSensitive,
      );
      // `critical` needs an entitlement the app does not hold.
      expect(
        PushPresentation.levelFor(
          severity: 'p1',
          interruptionLevel: 'critical',
        ),
        PushInterruptionLevel.timeSensitive,
      );
      expect(
        PushPresentation.levelFor(severity: 'p3', interruptionLevel: ' loud '),
        PushInterruptionLevel.active,
      );
    });

    test('PushMessage carries the level and the OS-presented flag', () {
      final PushMessage message = PushMessage.fromMap(
        iosForeground(severity: 'p1', level: 'active'),
      )!;
      expect(message.interruption, PushInterruptionLevel.active);
      expect(message.presentedByOs, isTrue);
      final PushMessage again = PushMessage.fromMap(message.toMap())!;
      expect(again.interruption, PushInterruptionLevel.active);
      expect(again.presentedByOs, isTrue);
    });
  });

  group('iOS foreground presentation', () {
    test('passive shows in the list only: no banner, no sound', () {
      expect(
        PushPresentation.iosForegroundOptions(PushInterruptionLevel.passive),
        <String>['list'],
      );
    });

    test('active and time-sensitive show a banner with sound', () {
      for (final PushInterruptionLevel level in <PushInterruptionLevel>[
        PushInterruptionLevel.active,
        PushInterruptionLevel.timeSensitive,
      ]) {
        expect(PushPresentation.iosForegroundOptions(level), <String>[
          'banner',
          'list',
          'sound',
          'badge',
        ]);
      }
    });

    test('Swift willPresent applies the same table', () {
      final String swift = File('ios/Runner/AppDelegate.swift')
          .readAsStringSync();
      final RegExpMatch? fn = RegExp(
        r'static func presentationOptions\(forInterruptionLevel[\s\S]*?\n  \}',
      ).firstMatch(swift);
      expect(fn, isNotNull, reason: 'willPresent ignores interruption-level');
      final String body = fn!.group(0)!;
      List<String> options(String arm) {
        final RegExpMatch m = RegExp('$arm[^\\[]*\\[([^\\]]*)\\]')
            .firstMatch(body)!;
        return m
            .group(1)!
            .split(',')
            .map((String o) => o.trim().replaceFirst('.', ''))
            .toList();
      }

      expect(
        options('case "passive":'),
        PushPresentation.iosForegroundOptions(PushInterruptionLevel.passive),
      );
      expect(
        options('default:'),
        PushPresentation.iosForegroundOptions(PushInterruptionLevel.active),
      );
      expect(
        swift,
        contains('return Self.presentationOptions('),
        reason: 'willPresent must return the mapped options',
      );
      expect(swift, contains('payload["interruption_level"]'));
      expect(swift, contains('payload["presented_by_os"] = "true"'));
    });

    test(
      'the OS banner is the only one: Dart does not show a second copy',
      () async {
        final _RecordingNotifier notifier = _RecordingNotifier();
        final _RecordingRefresher refresher = _RecordingRefresher();
        final FcmDataHandler handler = FcmDataHandler(
          notifier: notifier,
          refresher: refresher,
        );

        await handler.handle(iosForeground(severity: 'p1', level: 'passive'));

        expect(
          notifier.shown,
          isEmpty,
          reason:
              'willPresent already presents it; a local copy doubles the '
              'banner and ignores the interruption level',
        );
        expect(refresher.applied, hasLength(1), reason: 'widget still updates');
      },
    );

    test('PushService without a data handler also skips the copy', () async {
      final _RecordingNotifier notifier = _RecordingNotifier();
      final PushService service = PushService(
        registerToken: ({
          required String platform,
          required String token,
          String? environment,
        }) async {},
        onNavigate: (_) {},
        events: const MethodChannel(PushChannels.events),
        tokenChannel: const MethodChannel(PushChannels.token),
        notifier: notifier,
      );
      await service.initialize();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            PushChannels.events,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(
                PushEventMethods.onForegroundMessage,
                iosForeground(severity: 'p2', level: 'time-sensitive'),
              ),
            ),
            (_) {},
          );
      expect(notifier.shown, isEmpty);
    });
  });

  group('Android foreground presentation', () {
    const MethodCodec codec = StandardMethodCodec();
    const String channelName = 'dexterous.com/flutter/local_notifications';
    late List<MethodCall> calls;
    TargetPlatform? previous;

    setUp(() {
      previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName, codec), (
            MethodCall call,
          ) async {
            calls.add(call);
            return call.method == 'initialize' ? true : null;
          });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = previous;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(channelName, codec),
              null,
            );
      });
    });

    Future<Map<Object?, Object?>> render(Map<String, Object?> payload) async {
      final FlutterLocalNotificationsNotifier notifier =
          FlutterLocalNotificationsNotifier();
      await notifier.initialize(onTap: (_) {});
      await notifier.showForeground(PushMessage.fromMap(payload)!);
      final MethodCall show = calls.lastWhere(
        (MethodCall c) => c.method == 'show',
      );
      final Map<Object?, Object?> args =
          show.arguments as Map<Object?, Object?>;
      return args['platformSpecifics']! as Map<Object?, Object?>;
    }

    test('P1 at HIGH priority: high channel, not silent', () async {
      final Map<Object?, Object?> spec = await render(
        androidForeground(severity: 'p1'),
      );
      expect(spec['channelId'], PushChannelIds.p1);
      expect(spec['silent'], isFalse);
    });

    test(
      'P1 with the user override passive (NORMAL priority) is silent',
      () async {
        final Map<Object?, Object?> spec = await render(
          androidForeground(severity: 'p1', normalPriority: true),
        );
        expect(
          spec['channelId'],
          PushChannelIds.p1,
          reason: 'the channel stays the one the user owns for P1',
        );
        expect(spec['silent'], isTrue, reason: 'passive must not buzz');
      },
    );

    test('info defaults to passive and is silent', () async {
      final Map<Object?, Object?> spec = await render(
        androidForeground(severity: 'info', normalPriority: true),
      );
      expect(spec['channelId'], PushChannelIds.fallback);
      expect(spec['silent'], isTrue);
    });

    test('the channels exist before the first system-rendered push', () {
      // Background FCM alerts are rendered by the system on the channel the
      // server names (`incidents`). A missing channel sends them to FCM's
      // generic fallback channel, which the user never configured.
      final String activity = File(
        'android/app/src/main/kotlin/app/uptrack/uptrack_mobile/'
        'MainActivity.kt',
      ).readAsStringSync();
      final String onCreate = RegExp(r'override fun onCreate[\s\S]*?\n    \}')
          .firstMatch(activity)!
          .group(0)!;
      expect(onCreate, contains('UptrackNotificationChannels.ensureAll(this)'));
    });

    test('foreground pushes are drawn natively (safe action buttons)', () {
      // In the foreground the native receiver draws the alert, so its action
      // buttons use the non-exported trampoline; Dart only refreshes the
      // widget (presented_by_os) and shows no plugin copy.
      const String dir =
          'android/app/src/main/kotlin/app/uptrack/uptrack_mobile/';
      final String service = File('${dir}UptrackFirebaseMessagingService.kt')
          .readAsStringSync();
      final String fn = RegExp(
        r'override fun onMessageReceived[\s\S]*?\n    \}',
      ).firstMatch(service)!.group(0)!;
      expect(fn, contains('payload["presented_by_os"] = "true"'));
      final String foreground = fn.substring(
        fn.indexOf('MainActivity.isForeground'),
        fn.indexOf('sendBroadcast(forward)'),
      );
      expect(
        foreground,
        isNot(contains('return')),
        reason: 'the foreground path must still draw the native alert',
      );
      expect(fn, contains('sendBroadcast(forward)'));
      expect(
        fn,
        contains('UptrackDataMessageReceiver.EXTRA_INTERRUPTION_LEVEL'),
      );
      final String receiver = File('${dir}UptrackDataMessageReceiver.kt')
          .readAsStringSync();
      expect(
        receiver,
        matches(
          RegExp(
            r'EXTRA_INTERRUPTION_LEVEL\)\s*==\s*"passive"[\s\S]{0,80}setSilent\(true\)',
          ),
        ),
      );
    });

    test('Kotlin forwards NORMAL priority as passive', () {
      final String service = File(
        'android/app/src/main/kotlin/app/uptrack/uptrack_mobile/'
        'UptrackFirebaseMessagingService.kt',
      ).readAsStringSync();
      expect(
        service,
        matches(
          RegExp(
            r'originalPriority\s*==\s*RemoteMessage\.PRIORITY_NORMAL[\s\S]{0,200}'
            r'"interruption_level"[\s\S]{0,40}"passive"',
          ),
        ),
      );
    });
  });

  group('iOS local copy (if ever shown) carries the level', () {
    test('Darwin details follow the interruption level', () {
      final DarwinNotificationDetails passive =
          FlutterLocalNotificationsNotifier.darwinDetailsFor(
            PushMessage.fromMap(
              iosForeground(severity: 'p1', level: 'passive'),
            )!,
          );
      expect(passive.interruptionLevel, InterruptionLevel.passive);
      expect(passive.presentSound, isFalse);
      expect(passive.presentBanner, isFalse);
      expect(passive.categoryIdentifier, 'UPTRACK_INCIDENT');

      final DarwinNotificationDetails ts =
          FlutterLocalNotificationsNotifier.darwinDetailsFor(
            PushMessage.fromMap(
              iosForeground(severity: 'p1', level: 'time-sensitive'),
            )!,
          );
      expect(ts.interruptionLevel, InterruptionLevel.timeSensitive);
      expect(ts.presentSound, isTrue);
      expect(ts.threadIdentifier, '5f0c1c9e-0000-4000-8000-000000000001');
      expect(jsonEncode(ts.categoryIdentifier), '"UPTRACK_INCIDENT"');
    });
  });
}
