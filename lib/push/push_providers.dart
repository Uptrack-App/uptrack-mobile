import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/uptrack_api.dart';
import '../app.dart' show routerProvider;
import '../features/auth/auth_controller.dart' show uptrackApiProvider;
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
    onNavigate: (String location) => ref.read(routerProvider).go(location),
  );
});

/// Initializes [pushServiceProvider] exactly once per process.
/// Extracted for tests (a plain function over a [WidgetRef]).
Future<void> initializePush(WidgetRef ref) async {
  await ref.read(pushServiceProvider).initialize();
}
