import 'package:flutter/widgets.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Compile-time observability configuration.
///
/// Values come from `--dart-define` so no secret is ever hardcoded, e.g.
/// `flutter run --dart-define=SENTRY_DSN=... --dart-define=POSTHOG_API_KEY=...`.
/// When a value is absent, that SDK stays disabled (guarded no-op).
class ObservabilityConfig {
  const ObservabilityConfig({
    this.sentryDsn = '',
    this.posthogApiKey = '',
    this.posthogHost = '',
  });

  const ObservabilityConfig.fromEnvironment()
    : this(
        sentryDsn: const String.fromEnvironment('SENTRY_DSN'),
        posthogApiKey: const String.fromEnvironment('POSTHOG_API_KEY'),
        posthogHost: const String.fromEnvironment('POSTHOG_HOST'),
      );

  final String sentryDsn;
  final String posthogApiKey;
  final String posthogHost;

  bool get isSentryEnabled => sentryDsn.isNotEmpty;
  bool get isPostHogEnabled => posthogApiKey.isNotEmpty;
}

/// Initializes Sentry + PostHog; a no-op (never throws) when unconfigured.
///
/// The [sentryInit]/[posthogInit] seams let tests verify the wiring without
/// touching the real SDKs.
Future<void> initObservability({
  ObservabilityConfig config = const ObservabilityConfig.fromEnvironment(),
  Future<void> Function(ObservabilityConfig config)? sentryInit,
  Future<void> Function(ObservabilityConfig config)? posthogInit,
}) async {
  if (!config.isSentryEnabled && !config.isPostHogEnabled) {
    return;
  }
  if (config.isSentryEnabled) {
    try {
      if (sentryInit != null) {
        await sentryInit(config);
      } else {
        await SentryFlutter.init((SentryFlutterOptions options) {
          options.dsn = config.sentryDsn;
        });
      }
    } catch (e) {
      // Observability must never crash startup.
      debugPrint('[obs] Sentry init failed: $e');
    }
  }
  if (config.isPostHogEnabled) {
    try {
      if (posthogInit != null) {
        await posthogInit(config);
      } else {
        final PostHogConfig posthogConfig = PostHogConfig(config.posthogApiKey);
        if (config.posthogHost.isNotEmpty) {
          posthogConfig.host = config.posthogHost;
        }
        await Posthog().setup(posthogConfig);
      }
    } catch (e) {
      // Observability must never crash startup.
      debugPrint('[obs] PostHog init failed: $e');
    }
  }
}

/// Screen-tracking observers for the router. Both SDK observers no-op until
/// their SDK is initialized, so wiring them unconditionally is safe.
List<NavigatorObserver> buildAppObservers({
  SentryNavigatorObserver? sentryObserver,
  PosthogObserver? posthogObserver,
}) {
  return <NavigatorObserver>[
    sentryObserver ?? SentryNavigatorObserver(),
    posthogObserver ?? PosthogObserver(),
  ];
}
