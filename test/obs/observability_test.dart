import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:uptrack_mobile/obs/observability.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unconfigured init is a no-op that never throws', () async {
    bool called = false;
    await initObservability(
      config: const ObservabilityConfig(),
      sentryInit: (ObservabilityConfig _) async {
        called = true;
      },
      posthogInit: (ObservabilityConfig _) async {
        called = true;
      },
    );
    expect(called, isFalse);
  });

  test('configured init delegates to both SDK seams', () async {
    const ObservabilityConfig config = ObservabilityConfig(
      sentryDsn: 'https://public@sentry.io/1',
      posthogApiKey: 'phc_test',
      posthogHost: 'https://example.com',
    );
    bool sentryCalled = false;
    bool posthogCalled = false;
    await initObservability(
      config: config,
      sentryInit: (ObservabilityConfig seen) async {
        sentryCalled = true;
        expect(seen.sentryDsn, config.sentryDsn);
      },
      posthogInit: (ObservabilityConfig seen) async {
        posthogCalled = true;
        expect(seen.posthogApiKey, config.posthogApiKey);
      },
    );
    expect(sentryCalled, isTrue);
    expect(posthogCalled, isTrue);
  });

  test('throwing SDK init does not propagate', () async {
    const ObservabilityConfig config = ObservabilityConfig(
      sentryDsn: 'https://public@sentry.io/1',
      posthogApiKey: 'phc_test',
    );
    await initObservability(
      config: config,
      sentryInit: (ObservabilityConfig _) async {
        throw StateError('sentry down');
      },
      posthogInit: (ObservabilityConfig _) async {
        throw StateError('posthog down');
      },
    );
  });

  test('default config is disabled without dart-defines', () {
    const ObservabilityConfig config = ObservabilityConfig.fromEnvironment();
    expect(config.isSentryEnabled, isFalse);
    expect(config.isPostHogEnabled, isFalse);
  });

  test('buildAppObservers returns screen-tracking observers', () {
    final List<NavigatorObserver> observers = buildAppObservers();
    expect(observers, hasLength(2));
    expect(observers.whereType<SentryNavigatorObserver>(), hasLength(1));
    expect(observers.whereType<PosthogObserver>(), hasLength(1));
  });
}
