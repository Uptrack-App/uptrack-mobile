import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/app.dart' show routerProvider;
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/database_providers.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/push/push_channels.dart';
import 'package:uptrack_mobile/push/push_providers.dart';
import 'package:uptrack_mobile/push/push_route_gate.dart';

/// Plan item 4.2: a notification tap opens the right incident or monitor in
/// every app state, including a cold start that races the session restore.

/// A secure-storage stand-in whose first read waits, like the Keychain /
/// EncryptedSharedPreferences read on a real cold start.
class _SlowTokenStore implements TokenStore {
  final Completer<void> unblock = Completer<void>();

  @override
  Future<String?> readDeviceToken() async {
    await unblock.future;
    return 'udt_restored';
  }

  @override
  Future<String?> readDeviceTokenId() async => 'dt-1';

  @override
  Future<void> writeDeviceToken({
    required String token,
    required String id,
  }) async {}

  @override
  Future<void> clear() async {}
}

class _OkServer implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(<String, Object?>{'ok': true}),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Records each `go` with the auth status at that moment.
class _RecordingRouter extends Fake implements GoRouter {
  _RecordingRouter(this.statusAt);

  final AuthStatus Function() statusAt;
  final List<(String, AuthStatus)> gone = <(String, AuthStatus)>[];

  @override
  void go(String location, {Object? extra}) {
    gone.add((location, statusAt()));
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PushRouteGate', () {
    test('navigates at once while signed in', () {
      final List<String> gone = <String>[];
      final PushRouteGate gate = PushRouteGate(
        isSignedIn: () => true,
        go: gone.add,
      );
      gate.navigate('/incidents/i1');
      expect(gone, <String>['/incidents/i1']);
      expect(gate.pending, isNull);
    });

    test('parks while signed out and opens the newest target at sign-in', () {
      bool signedIn = false;
      final List<String> gone = <String>[];
      final PushRouteGate gate = PushRouteGate(
        isSignedIn: () => signedIn,
        go: gone.add,
      );
      gate.navigate('/incidents/old');
      gate.navigate('/monitors/m2');
      expect(gone, isEmpty);

      gate.onAuthChanged(signedIn: false);
      expect(gone, isEmpty);

      signedIn = true;
      gate.onAuthChanged(signedIn: true);
      gate.onAuthChanged(signedIn: true);
      expect(gone, <String>['/monitors/m2'], reason: 'once, newest only');
    });
  });

  group('cold start (killed state) races the session restore', () {
    const String plugin = 'dexterous.com/flutter/local_notifications';
    late _SlowTokenStore store;
    late ProviderContainer container;
    late _RecordingRouter router;
    TargetPlatform? previous;

    setUp(() {
      previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      final TestDefaultBinaryMessenger messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel(plugin),
        (MethodCall call) async =>
            call.method == 'getNotificationAppLaunchDetails' ? null : true,
      );
      // The native host buffered the tap that launched the app.
      messenger.setMockMethodCallHandler(
        const MethodChannel(PushChannels.token),
        (MethodCall call) async =>
            call.method == PushTokenMethods.getInitialNotification
            ? <String, Object?>{'incident_id': 'inc-cold'}
            : null,
      );
      store = _SlowTokenStore();
      final AuthTokenHolder holder = AuthTokenHolder();
      container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(store),
          authTokenHolderProvider.overrideWithValue(holder),
          dioProvider.overrideWithValue(
            buildAppDio(
              holder: holder,
              onUnauthorized: () {},
              adapter: _OkServer(),
            ),
          ),
          appDatabaseProvider.overrideWithValue(
            AppDatabase.forTesting(NativeDatabase.memory()),
          ),
          routerProvider.overrideWith((Ref ref) {
            return router = _RecordingRouter(
              () => ref.read(authControllerProvider).status,
            );
          }),
        ],
      );
      addTearDown(() {
        debugDefaultTargetPlatformOverride = previous;
        messenger.setMockMethodCallHandler(const MethodChannel(plugin), null);
        messenger.setMockMethodCallHandler(
          const MethodChannel(PushChannels.token),
          null,
        );
        container.read(appDatabaseProvider).close();
        container.dispose();
      });
    });

    test('the incident opens after the session is restored', () async {
      // App start: auth restore begins, then push initializes.
      container.read(authControllerProvider);
      container.read(pushAuthBindingProvider);
      await container.read(pushServiceProvider).initialize();
      container.read(routerProvider);

      // Storage answers only now.
      store.unblock.complete();
      await pumpEventQueue();

      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedIn,
      );
      expect(router.gone, <(String, AuthStatus)>[
        ('/incidents/inc-cold', AuthStatus.signedIn),
      ], reason: 'a go() while signed out is bounced to /login and lost');
    });
  });

  group('Android system-rendered FCM notification taps', () {
    test('MainActivity accepts the server click_action', () {
      // `CLICK_ACTION` in uptrack-server crates/api/src/push_fcm.rs. The
      // server sends a `notification` block, so in background/killed state
      // the FCM SDK renders it and its tap fires an intent with this action.
      // With no matching filter the tap opens nothing.
      const String serverClickAction = 'FLUTTER_NOTIFICATION_CLICK';
      final String manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      final RegExpMatch? mainActivity = RegExp(
        r'<activity\s[^>]*android:name="\.MainActivity"[\s\S]*?</activity>',
      ).firstMatch(manifest);
      expect(mainActivity, isNotNull);
      final Iterable<String> filters = RegExp(
        r'<intent-filter>([\s\S]*?)</intent-filter>',
      ).allMatches(mainActivity!.group(0)!).map((RegExpMatch m) => m.group(1)!);
      expect(
        filters.where(
          (String f) =>
              f.contains('android:name="$serverClickAction"') &&
              f.contains('android:name="android.intent.category.DEFAULT"'),
        ),
        hasLength(1),
      );
    });

    test('MainActivity reads the FCM data keys from the tap intent', () {
      final String activity = File(
        'android/app/src/main/kotlin/app/uptrack/uptrack_mobile/MainActivity.kt',
      ).readAsStringSync();
      // FCM copies the `data` block (incident_id, ...) into intent extras.
      expect(
        activity,
        contains('UptrackDataMessageReceiver.EXTRA_INCIDENT_ID'),
      );
      expect(activity, contains('override fun onNewIntent'));
    });
  });
}
