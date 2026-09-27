import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/uptrack_api.dart';
import '../app.dart' show routerProvider;
import '../data/local/database_providers.dart' show cacheRepositoryProvider;
import '../features/auth/auth_controller.dart' show uptrackApiProvider;
import '../widgets/widget_store.dart';
import 'fcm_data.dart';
import 'push_actions.dart';
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
    notifier: notifier,
    onForegroundData: (Map<Object?, Object?> data) async {
      await fcmData.handle(data);
    },
  );
});

/// Initializes [pushServiceProvider] exactly once per process.
/// Extracted for tests (a plain function over a [WidgetRef]).
Future<void> initializePush(WidgetRef ref) async {
  await ref.read(pushServiceProvider).initialize();
}
