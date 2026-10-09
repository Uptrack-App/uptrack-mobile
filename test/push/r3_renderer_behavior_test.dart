import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/push/push_actions.dart';
import 'package:uptrack_mobile/push/push_channels.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/push/push_service.dart';

/// R3 early slice: the local renderer's behaviour against the *real*
/// `flutter_local_notifications` platform channel.
///
/// `r3_notification_contract_test.dart` proves the Dart and Kotlin halves agree
/// on constants by parsing both sources. It cannot prove that the Dart
/// foreground renderer actually *emits* that contract, nor what it does when
/// the plugin hands it an action tap. These tests drive the plugin's own method
/// channel so both are answered at runtime.
///
/// Nothing here claims background or cold-start qualification: the renderer
/// registers only the main-isolate `onDidReceiveNotificationResponse`
/// callback, which is exactly the foreground/unforegrounded live channel. A
/// background engine delivers actions through a different callback and
/// dispatcher handle, and that contract is R3-deferred to the single owner.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodCodec codec = StandardMethodCodec();
  const String channelName = 'dexterous.com/flutter/local_notifications';

  late List<MethodCall> calls;
  late List<PushMessage> taps;
  late List<PushActionRequest> actions;
  late TestDefaultBinaryMessenger messenger;

  /// The map `getNotificationAppLaunchDetails` should answer with.
  Object? launchDetails;
  TargetPlatform? previousPlatform;

  setUpAll(() {
    // The plugin branches on `defaultTargetPlatform`; pin Android so the
    // Android platform implementation is the one under test.
    previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = previousPlatform;
  });

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    calls = <MethodCall>[];
    taps = <PushMessage>[];
    actions = <PushActionRequest>[];
    launchDetails = null;
    messenger.setMockMethodCallHandler(MethodChannel(channelName, codec), (
      MethodCall call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return launchDetails;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(MethodChannel(channelName, codec), null);
  });

  /// A renderer wired to recording callbacks, as [PushService] would not wire
  /// it: this slice's service passes no `onAction`, so the callback is supplied
  /// here purely to observe what the renderer *offers*.
  FlutterLocalNotificationsNotifier buildNotifier() =>
      FlutterLocalNotificationsNotifier(onAction: actions.add);

  Future<FlutterLocalNotificationsNotifier> initialized() async {
    final FlutterLocalNotificationsNotifier notifier = buildNotifier();
    await notifier.initialize(onTap: taps.add);
    return notifier;
  }

  /// Delivers a native `didReceiveNotificationResponse` on the plugin channel,
  /// exactly as the Android host does when a notification or one of its action
  /// buttons is tapped.
  Future<void> deliverResponse({String? actionId, String? payload}) async {
    await messenger.handlePlatformMessage(
      channelName,
      codec.encodeMethodCall(
        MethodCall('didReceiveNotificationResponse', <String, Object?>{
          'notificationId': 1001,
          'actionId': actionId,
          'input': null,
          'payload': payload,
          'notificationResponseType':
              NotificationResponseType.selectedNotification.index,
        }),
      ),
      (ByteData? _) {},
    );
  }

  /// The `platformSpecifics` map of the last `show` call.
  Map<Object?, Object?> lastShowDetails() {
    final MethodCall show = calls.lastWhere(
      (MethodCall call) => call.method == 'show',
      orElse: () => throw StateError('the plugin was never asked to show'),
    );
    final Map<Object?, Object?> args = show.arguments as Map<Object?, Object?>;
    return args['platformSpecifics']! as Map<Object?, Object?>;
  }

  /// The `getNotificationAppLaunchDetails` answer for a cold start, shaped
  /// exactly as the Android host sends it: a bool `notificationLaunchedApp`
  /// and a nested response whose `notificationResponseType` is the int enum
  /// index the plugin indexes `NotificationResponseType.values` with.
  Map<Object?, Object?> launch(
    bool launchedApp, {
    String? actionId,
    String? payload,
  }) {
    return <Object?, Object?>{
      'notificationLaunchedApp': launchedApp,
      'notificationResponse': <Object?, Object?>{
        'notificationId': 1001,
        'actionId': actionId,
        'input': null,
        'payload': payload,
        'notificationResponseType':
            NotificationResponseType.selectedNotification.index,
      },
    };
  }

  group('showForeground emits the shared per-severity contract', () {
    test(
      'a p1 alert renders on the p1 channel with high/high settings',
      () async {
        final FlutterLocalNotificationsNotifier notifier = await initialized();
        await notifier.showForeground(
          const PushMessage(
            title: 'Database down',
            body: 'Latency 4.2s',
            incidentId: 'inc-1',
            severity: 'p1',
          ),
        );

        final Map<Object?, Object?> details = lastShowDetails();
        expect(details['channelId'], PushChannelIds.p1);
        expect(details['channelName'], 'P1 critical alerts');
        expect(details['channelDescription'], isNotEmpty);
        // NotificationManager IMPORTANCE_HIGH = 4, PRIORITY_HIGH = 1.
        expect(details['importance'], 4);
        expect(details['priority'], 1);
        expect(details['category'], 'event');
        expect(
          details['channelBypassDnd'],
          isFalse,
          reason: 'no DND claim: the user always owns interruption',
        );

        final MethodCall show = calls.last;
        final Map<Object?, Object?> args =
            show.arguments as Map<Object?, Object?>;
        expect(args['title'], 'Database down');
        expect(args['body'], 'Latency 4.2s');
        expect(
          args['id'],
          const PushMessage(incidentId: 'inc-1', severity: 'p1').notificationId,
        );

        // The payload is the message itself, so a tap can be routed later.
        expect(jsonDecode(args['payload']! as String), <String, Object?>{
          'title': 'Database down',
          'body': 'Latency 4.2s',
          'incident_id': 'inc-1',
          'severity': 'p1',
        });

        expect(_actionIds(details), <String>[
          PushIntentIdentity.acknowledge,
          PushIntentIdentity.escalate,
          PushIntentIdentity.snooze,
        ]);
        expect(
          _showsUserInterface(details),
          everyElement(isFalse),
          reason:
              'the renderer serves the foreground only and never pulls UI up',
        );
      },
    );

    test(
      'p2/p3 map to their own channels and unknown to the fallback',
      () async {
        final FlutterLocalNotificationsNotifier notifier = await initialized();
        for (final (
              String severity,
              String channel,
              int importance,
              int priority,
            )
            in <(String, String, int, int)>[
              ('p2', PushChannelIds.p2, 3, 0),
              ('p3', PushChannelIds.p3, 2, -1),
              ('info', PushChannelIds.fallback, 3, 0),
              ('nonsense', PushChannelIds.fallback, 3, 0),
              ('', PushChannelIds.fallback, 3, 0),
            ]) {
          await notifier.showForeground(
            PushMessage(incidentId: 'inc-1', severity: severity),
          );
          final Map<Object?, Object?> details = lastShowDetails();
          expect(details['channelId'], channel, reason: 'severity "$severity"');
          expect(
            details['importance'],
            importance,
            reason: 'severity "$severity"',
          );
          expect(details['priority'], priority, reason: 'severity "$severity"');
        }
      },
    );

    test('actions narrow to what can actually be applied', () async {
      final FlutterLocalNotificationsNotifier notifier = await initialized();

      // Incident + monitor is still an incident alert.
      await notifier.showForeground(
        const PushMessage(incidentId: 'inc-1', monitorId: 'mon-1'),
      );
      expect(_actionIds(lastShowDetails()), PushIntentIdentity.actionIds);

      // Monitor-only: Acknowledge/Escalate are incident-scoped endpoints.
      await notifier.showForeground(const PushMessage(monitorId: 'mon-1'));
      expect(_actionIds(lastShowDetails()), <String>[
        PushIntentIdentity.snooze,
      ]);

      // No usable target: nothing to triage, so no action buttons.
      await notifier.showForeground(const PushMessage(title: 'no target'));
      expect(_actionIds(lastShowDetails()), isEmpty);

      // An unsanitizable id is not a target either.
      await notifier.showForeground(const PushMessage(incidentId: 'inc 1'));
      expect(_actionIds(lastShowDetails()), isEmpty);
    });

    test(
      'a missing title or body still renders under stable defaults',
      () async {
        final FlutterLocalNotificationsNotifier notifier = await initialized();
        await notifier.showForeground(
          const PushMessage(incidentId: 'inc-1', severity: 'p2'),
        );
        final MethodCall show = calls.last;
        final Map<Object?, Object?> args =
            show.arguments as Map<Object?, Object?>;
        expect(args['title'], 'Uptrack');
        expect(args['body'], '');
      },
    );
  });

  group('an action tap is never a body tap', () {
    test('an action id goes to onAction and leaves onTap untouched', () async {
      final FlutterLocalNotificationsNotifier notifier = await initialized();
      await deliverResponse(
        actionId: PushIntentIdentity.acknowledge,
        payload: jsonEncode(<String, Object?>{
          'incident_id': 'inc-1',
          'severity': 'p1',
        }),
      );

      expect(taps, isEmpty, reason: 'an action must not navigate as a tap');
      expect(actions, hasLength(1));
      expect(actions.single.action, PushAction.acknowledge);
      expect(actions.single.incidentId, 'inc-1');
      expect(actions.single.monitorId, isNull);
      expect(notifier.lastUnhandledAction, actions.single);
    });

    test('a monitor-scoped action resolves to the monitor id', () async {
      await initialized();
      await deliverResponse(
        actionId: PushIntentIdentity.snooze,
        payload: jsonEncode(<String, Object?>{'monitor_id': 'mon-1'}),
      );

      expect(taps, isEmpty);
      expect(actions.single.action, PushAction.snooze);
      expect(actions.single.monitorId, 'mon-1');
      expect(actions.single.incidentId, isNull);
    });

    test(
      'an unknown action id is dropped, never downgraded to a tap',
      () async {
        final FlutterLocalNotificationsNotifier notifier = await initialized();
        await deliverResponse(
          actionId: 'app.uptrack.mobile.UPTRACK_DELETE_EVERYTHING',
          payload: jsonEncode(<String, Object?>{'incident_id': 'inc-1'}),
        );

        expect(taps, isEmpty);
        expect(actions, isEmpty);
        expect(notifier.lastUnhandledAction, isNull);
      },
    );

    test('an action with no usable target is dropped, not a tap', () async {
      final FlutterLocalNotificationsNotifier notifier = await initialized();
      await deliverResponse(
        actionId: PushIntentIdentity.acknowledge,
        payload: jsonEncode(<String, Object?>{'incident_id': 'inc 1'}),
      );
      await deliverResponse(
        actionId: PushIntentIdentity.acknowledge,
        payload: null,
      );
      await deliverResponse(
        actionId: PushIntentIdentity.acknowledge,
        payload: 'not json at all',
      );

      expect(taps, isEmpty);
      expect(actions, isEmpty);
      expect(notifier.lastUnhandledAction, isNull);
    });

    test('an empty action id is a body tap', () async {
      await initialized();
      await deliverResponse(
        actionId: '',
        payload: jsonEncode(<String, Object?>{'incident_id': 'inc-1'}),
      );

      expect(actions, isEmpty);
      expect(taps, hasLength(1));
      expect(taps.single.incidentId, 'inc-1');
      expect(taps.single.routeLocation, '/incidents/inc-1');
    });

    test('a body tap with no payload navigates nothing', () async {
      await initialized();
      await deliverResponse(actionId: '', payload: null);

      expect(taps, isEmpty);
      expect(actions, isEmpty);
    });
  });

  group('a cold start preserves the action instead of reporting a tap', () {
    test(
      'a launching action reports no tap and hands over the request',
      () async {
        launchDetails = launch(
          true,
          actionId: PushIntentIdentity.escalate,
          payload: jsonEncode(<String, Object?>{'incident_id': 'inc-1'}),
        );
        final FlutterLocalNotificationsNotifier notifier = await initialized();

        expect(await notifier.initialNotification(), isNull);
        expect(actions.single.action, PushAction.escalate);
        expect(actions.single.incidentId, 'inc-1');
        expect(notifier.lastUnhandledAction, actions.single);
      },
    );

    test('a launching body tap still yields a routable message', () async {
      launchDetails = launch(
        true,
        payload: jsonEncode(<Object?, Object?>{
          'incident_id': 'inc-1',
          'monitor_id': 'mon-1',
        }),
      );
      final FlutterLocalNotificationsNotifier notifier = await initialized();

      final PushMessage? message = await notifier.initialNotification();
      expect(message?.incidentId, 'inc-1');
      expect(message?.routeLocation, '/incidents/inc-1');
      expect(actions, isEmpty);
    });

    test('a normal launch reports nothing at all', () async {
      launchDetails = null;
      final FlutterLocalNotificationsNotifier notifier = await initialized();
      expect(await notifier.initialNotification(), isNull);
      expect(actions, isEmpty);
      expect(notifier.lastUnhandledAction, isNull);
    });

    test('a launch that did not launch the app reports nothing', () async {
      launchDetails = launch(
        false,
        payload: jsonEncode(<Object?, Object?>{'incident_id': 'inc-1'}),
      );
      final FlutterLocalNotificationsNotifier notifier = await initialized();
      expect(await notifier.initialNotification(), isNull);
    });

    test('the renderer registers only the main-isolate response callback', () async {
      await initialized();
      // The renderer arms the plugin exactly once, with the Android settings
      // the plugin requires when it is targeting Android.
      final MethodCall initialize = calls.firstWhere(
        (MethodCall call) => call.method == 'initialize',
      );
      final Map<Object?, Object?> settings =
          initialize.arguments as Map<Object?, Object?>;
      // A white silhouette: Android draws status-bar icons from alpha only, so
      // the full-colour launcher icon would show as a white square.
      expect(settings['defaultIcon'], '@drawable/ic_notification');
      // The deferred runtime gate, asserted so it cannot be forgotten: the
      // renderer registers **no** background response callback, and passes no
      // `onDidReceiveBackgroundNotificationResponse`. An installed
      // `ActionBroadcastReceiver` can therefore deliver an action through the
      // live channel while the app is foregrounded, but a background/killed app
      // would use a background engine and a dispatcher handle that this slice
      // does not establish. Background and cold-start local actions are
      // therefore NOT qualified here; the single owner must choose a
      // UI-start/auth-safe dispatch or a real background callback contract and
      // verify it on device.
      expect(
        RegExp('onDidReceiveBackgroundNotificationResponse')
            .hasMatch(_rendererSource()),
        isFalse,
        reason:
            'a background callback needs an @pragma entry point and an '
            'auth-safe dispatcher handle — single-owner scope, not this slice',
      );
    });
  });
}

/// Action ids in the order they reach Android.
List<String> _actionIds(Map<Object?, Object?> details) {
  final List<Object?> actions =
      (details['actions'] as List<Object?>?) ?? const <Object?>[];
  return <String>[
    for (final Object? action in actions)
      (action! as Map<Object?, Object?>)['id']! as String,
  ];
}

/// `showsUserInterface` for every action on a rendered notification.
List<bool> _showsUserInterface(Map<Object?, Object?> details) {
  final List<Object?> actions =
      (details['actions'] as List<Object?>?) ?? const <Object?>[];
  return <bool>[
    for (final Object? action in actions)
      (action! as Map<Object?, Object?>)['showsUserInterface']! as bool,
  ];
}

/// The renderer's own source text, for the one structural check above.
String _rendererSource() =>
    File('lib/push/push_service.dart').readAsStringSync();
