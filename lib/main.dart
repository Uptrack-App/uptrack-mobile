import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'obs/observability.dart';
import 'theme/appearance.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Guarded no-op unless SENTRY_DSN / POSTHOG_API_KEY dart-defines are set.
  await initObservability();
  // Read the saved light/dark choice first, so the first frame is right.
  await sharedAppearance.load();
  runApp(const ProviderScope(child: UptrackApp()));
}
