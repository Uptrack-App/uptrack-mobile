import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/uptrack_api.dart';
import '../app.dart' show routerProvider;
import '../data/local/cache_repository.dart';
import '../data/local/database_providers.dart' show cacheRepositoryProvider;
import '../features/auth/auth_controller.dart' show uptrackApiProvider;
import '../widgets/live_activity_sync.dart';
import '../widgets/live_surface_sync.dart';
import '../widgets/widget_store.dart';
import 'fcm_data.dart';
import 'live_activity_support.dart' show osVersionProvider;
import 'push_actions.dart';
import 'push_message.dart';
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
  void navigate(String location) => ref.read(routerProvider).go(location);
  // Foreground path (T056): FCM data messages refresh the Glance/WidgetKit
  // home widget from the Drift cache best-effort, then display locally.
  // The refresher closure is lazy — no DB access until a push arrives.
  final LocalNotifier notifier = FlutterLocalNotificationsNotifier();
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
    actionHandler: PushActionHandler(api: api, onNavigate: navigate),
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

/// Initializes [pushServiceProvider] exactly once per process.
/// Extracted for tests (a plain function over a [WidgetRef]).
Future<void> initializePush(WidgetRef ref) async {
  await ref.read(pushServiceProvider).initialize();
}
