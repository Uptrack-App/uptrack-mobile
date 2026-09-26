import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'obs/observability.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Guarded no-op unless SENTRY_DSN / POSTHOG_API_KEY dart-defines are set.
  await initObservability();
  runApp(const ProviderScope(child: UptrackApp()));
}
