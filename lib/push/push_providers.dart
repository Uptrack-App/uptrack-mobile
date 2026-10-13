import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/uptrack_api.dart';
import '../app.dart' show routerProvider;
import '../data/local/cache_repository.dart';
import '../data/local/database_providers.dart' show cacheRepositoryProvider;
import '../features/auth/auth_controller.dart'
    show AuthState, AuthStatus, authControllerProvider, uptrackApiProvider;
import '../widgets/live_activity_sync.dart';
import '../widgets/live_surface_sync.dart';
import '../widgets/widget_store.dart';
import 'fcm_data.dart';
import 'live_activity_support.dart' show osVersionProvider;
import 'push_actions.dart';
import 'push_message.dart';
import 'push_registration.dart';
import 'push_route_gate.dart';
import 'push_service.dart';
import 'pushed_incident_sync.dart';

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
  // No `onAction` on purpose: the plugin reads its responses from intents
  // sent to the exported launcher activity, which any app can forge. Triage
  // actions come only from the native hosts (iOS system responses, Android's
  // non-exported UptrackActionActivity), so the renderer offers no buttons.
  final FlutterLocalNotificationsNotifier notifier =
      FlutterLocalNotificationsNotifier();
  final FcmDataHandler fcmData = FcmDataHandler(
    notifier: notifier,
    refresher: WidgetRefresher.fromCache(
      ref.watch(cacheRepositoryProvider),
      store: const HomeWidgetStore(),
    ),
  );
  return PushService(
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
    unregisterLiveActivity: api.unregisterLiveActivity,
    notifier: notifier,
    onForegroundData: (Map<Object?, Object?> data) async {
      final PushMessage? message = await fcmData.handle(data);
      final String? incidentId = message?.incidentId;
      if (incidentId != null) {
        // The alert does not say open or resolved; one read of the incident
        // does, and the stored row refreshes the widget and the Live
        // Activity through [liveSurfaceSyncProvider].
        unawaited(
          syncPushedIncident(
            cache: ref.read(cacheRepositoryProvider),
            fetch: api.getIncident,
            incidentId: incidentId,
          ),
        );
      }
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
});

/// Starts (iOS 16.1 to 17.1), ends and de-duplicates incident Live
/// Activities from the cached incident feed.
final Provider<LiveActivitySync> liveActivitySyncProvider =
    Provider<LiveActivitySync>((Ref ref) {
      final WidgetRefresher refresher = WidgetRefresher.fromCache(
        ref.watch(cacheRepositoryProvider),
        store: const HomeWidgetStore(),
      );
      return LiveActivitySync(
        host: const MethodChannelLiveActivityHost(),
        loadCandidates: refresher.loadCandidates,
        mode: () => liveActivityStartMode(
          platform: defaultTargetPlatform,
          osVersion: ref.read(osVersionProvider),
        ),
      );
    });

/// Refreshes the home widget and the Live Activities after every applied
/// incident write, and on demand (app resume). Reading it attaches it.
final Provider<LiveSurfaceSync> liveSurfaceSyncProvider =
    Provider<LiveSurfaceSync>((Ref ref) {
      final CacheRepository cache = ref.watch(cacheRepositoryProvider);
      final WidgetRefresher refresher = WidgetRefresher.fromCache(
        cache,
        store: const HomeWidgetStore(),
      );
      final LiveActivitySync activities = ref.watch(liveActivitySyncProvider);
      final LiveSurfaceSync sync = LiveSurfaceSync(
        refreshWidget: () async {
          await refresher.refresh();
        },
        reconcileActivities: () async {
          await activities.reconcile();
        },
      );
      sync.attach(cache.incidentsChanged);
      ref.onDispose(() => unawaited(sync.dispose()));
      return sync;
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
