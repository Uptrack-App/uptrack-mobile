import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/uptrack_api.dart';
import '../app.dart' show routerProvider;
import '../data/local/database_providers.dart' show cacheRepositoryProvider;
import '../features/auth/auth_controller.dart'
    show AuthState, AuthStatus, authControllerProvider, uptrackApiProvider;
import '../widgets/widget_store.dart';
import 'fcm_data.dart';
import 'push_actions.dart';
import 'push_registration.dart';
import 'push_route_gate.dart';
import 'push_service.dart';

/// Dart-side push plumbing (T027): token refresh → `POST /api/push/devices`,
/// notification taps → `router.go`.
///
/// Constructed without side effects so tests can override it with a fake;
/// [UptrackApp] initializes the live instance once at startup (see
/// `lib/app.dart`).
final Provider<PushService> pushServiceProvider = Provider<PushService>((
  Ref ref,
) {
  final UptrackApi api = ref.watch(uptrackApiProvider);
  // Deep links wait for a session (a cold-start tap races the restore).
  final PushRouteGate gate = ref.watch(pushRouteGateProvider);
  void navigate(String location) => gate.navigate(location);
  // Foreground path (T056): FCM data messages refresh the Glance/WidgetKit
  // home widget from the Drift cache best-effort, then display locally.
  // The refresher closure is lazy — no DB access until a push arrives.
  // Buttons on a notification the Dart renderer showed (Android) run
  // through the same action path as the native ones (plan 4.6).
  late final PushService service;
  final FlutterLocalNotificationsNotifier notifier =
      FlutterLocalNotificationsNotifier(
        onAction: (PushActionRequest request) =>
            unawaited(service.handleAction(request)),
      );
  final FcmDataHandler fcmData = FcmDataHandler(
    notifier: notifier,
    refresher: WidgetRefresher.fromCache(
      ref.watch(cacheRepositoryProvider),
      store: const HomeWidgetStore(),
    ),
  );
  service = PushService(
    registerToken:
        ({
          required String platform,
          required String token,
          String? environment,
        }) => api.registerPushDevice(
          platform: platform,
          token: token,
          environment: environment,
        ),
    onNavigate: navigate,
    actionHandler: PushActionHandler(
      api: api,
      onNavigate: navigate,
      retryDelays: ref.watch(pushActionRetryDelaysProvider),
    ),
    registerLiveActivity: api.registerLiveActivity,
    notifier: notifier,
    onForegroundData: (Map<Object?, Object?> data) async {
      await fcmData.handle(data);
    },
    registrationStore: ref.watch(pushRegistrationStoreProvider),
    isSignedIn: () =>
        ref.read(authControllerProvider).status == AuthStatus.signedIn,
    requestPermission: notifier.requestAndroidPermission,
    waitForSession: () async {
      await ref.read(authControllerProvider.notifier).restored;
      return ref.read(authControllerProvider).status == AuthStatus.signedIn;
    },
  );
  return service;
});

/// Retry waits for a lock-screen action that could not reach the server.
/// A provider so tests can make them instant.
final Provider<List<Duration>> pushActionRetryDelaysProvider =
    Provider<List<Duration>>((Ref ref) => PushActionHandler.defaultRetryDelays);

/// Parks notification deep links until a session exists (plan 4.2).
final Provider<PushRouteGate> pushRouteGateProvider = Provider<PushRouteGate>(
  (Ref ref) => PushRouteGate(
    isSignedIn: () =>
        ref.read(authControllerProvider).status == AuthStatus.signedIn,
    go: (String location) => ref.read(routerProvider).go(location),
  ),
);

/// Registers the push device whenever a session starts (sign-in or a
/// restored session; plan 4.3) and opens a parked deep link (plan 4.2). Reading it once keeps the listener alive for
/// the life of the container.
final Provider<void> pushAuthBindingProvider = Provider<void>((Ref ref) {
  final PushService service = ref.watch(pushServiceProvider);
  final PushRouteGate gate = ref.watch(pushRouteGateProvider);
  ref.listen<AuthStatus>(
    authControllerProvider.select((AuthState state) => state.status),
    (AuthStatus? previous, AuthStatus next) {
      if (previous != next) {
        final bool signedIn = next == AuthStatus.signedIn;
        gate.onAuthChanged(signedIn: signedIn);
        unawaited(service.onAuthChanged(signedIn: signedIn));
      }
    },
  );
});

/// Initializes [pushServiceProvider] exactly once per process and binds it
/// to the auth session. Extracted for tests (a plain function over a
/// [WidgetRef]).
Future<void> initializePush(WidgetRef ref) async {
  ref.read(pushAuthBindingProvider);
  await ref.read(pushServiceProvider).initialize();
}
