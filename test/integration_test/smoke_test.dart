import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uptrack_mobile/app.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/features/auth/social_login.dart';
import 'package:uptrack_mobile/push/push_message.dart';
import 'package:uptrack_mobile/push/push_providers.dart';
import 'package:uptrack_mobile/push/push_service.dart';

/// Emulator smoke harness (T042): the app launches to the login screen
/// without crashing and the sign-in form validates.
///
/// Runs in two modes:
/// * host (`flutter test`): plugin seams are stubbed (secure storage +
///   local notifications have no host implementation under flutter_test);
/// * device (`flutter test <this file> -d <emulator>`): same assertions
///   execute against the real Android runtime.
///
/// Native push registration (T028 Swift/Kotlin) and physical-device E2E
/// (T043/T044) stay out of scope here.
class _NoopNotifier implements LocalNotifier {
  @override
  Future<void> initialize({
    required void Function(PushMessage message) onTap,
  }) async {}

  @override
  Future<PushMessage?> initialNotification() async => null;

  @override
  Future<void> showForeground(PushMessage message) async {}
}

PushService _stubPushService() {
  return PushService(
    registerToken: ({
      required String platform,
      required String token,
      String? environment,
    }) async {},
    onNavigate: (_) {},
    notifier: _NoopNotifier(),
  );
}

Future<ProviderContainer> _pumpApp(WidgetTester tester) async {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
      socialProvidersProvider.overrideWith((ref) async => <String>{}),
      pushServiceProvider.overrideWithValue(_stubPushService()),
      // Real redirect logic (signed-out → /login) without the
      // Sentry/PostHog navigator observers: those call native plugin
      // channels with no host implementation under flutter_test
      // (same reason widget_test.dart overrides the router).
      routerProvider.overrideWithValue(
        createRouter(authStatusOf: () => AuthStatus.signedOut),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const UptrackApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('smoke: app launches to the login screen', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester);

    // Signed out with an empty token store → router redirects to /login.
    expect(find.text('Welcome to Uptrack'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Email me a sign-in link'),
      findsOneWidget,
    );
  });

  testWidgets('smoke: empty sign-in shows validation (no crash)', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _pumpApp(tester);

    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Email me a sign-in link'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Email me a sign-in link'),
    );
    await tester.pumpAndSettle();

    // Form validation runs; nothing is submitted and the app stays put.
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Welcome to Uptrack'), findsOneWidget);
    expect(container.read(authControllerProvider).status, AuthStatus.signedOut);
  });
}
