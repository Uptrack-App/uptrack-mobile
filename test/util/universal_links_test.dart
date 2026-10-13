import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uptrack_mobile/app.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/util/universal_links.dart';

/// Universal links (iOS) and app links (Android) hand the app the full
/// `https://uptrack.app/...` URL that the server puts in emails. These tests
/// pin which web URLs the app accepts and where each one lands in the app.
const String _incident = '0b7d6a52-3c1e-4f43-9a8e-2f6f1c1d9e01';
const String _monitor = '7f9c2ba4-e88f-4c2b-9a1e-5c3d2b1a0f99';

void main() {
  group('universalLinkLocation', () {
    test('the emailed magic link opens the in-app sign-in', () {
      final String? location = universalLinkLocation(
        Uri.parse(
          'https://uptrack.app/auth/verify-magic-link'
          '?token=abc123&email=ada%40example.com&client=mobile',
        ),
      );
      expect(location, isNotNull);
      final Uri uri = Uri.parse(location!);
      expect(uri.path, '/magic');
      expect(uri.queryParameters, <String, String>{
        'email': 'ada@example.com',
        'token': 'abc123',
      });
    });

    test('a web redirect in the magic link is dropped', () {
      final Uri uri = Uri.parse(
        universalLinkLocation(
          Uri.parse(
            'https://uptrack.app/auth/verify-magic-link'
            '?token=t&email=ada%40example.com&client=mobile'
            '&redirect=%2Fcheckout%3Fplan%3Dpro',
          ),
        )!,
      );
      expect(
        uri.queryParameters.keys,
        unorderedEquals(<String>['email', 'token']),
      );
    });

    test('alert email incident and monitor links open the detail screens', () {
      expect(
        universalLinkLocation(
          Uri.parse('https://uptrack.app/dashboard/incidents/$_incident'),
        ),
        '/incidents/$_incident',
      );
      expect(
        universalLinkLocation(
          Uri.parse('https://uptrack.app/dashboard/monitors/$_monitor'),
        ),
        '/monitors/$_monitor',
      );
    });

    test('rejects other hosts, schemes, ports and user info', () {
      for (final String url in <String>[
        'https://evil.test/dashboard/incidents/$_incident',
        'https://www.uptrack.app/dashboard/incidents/$_incident',
        'https://api.uptrack.app/dashboard/incidents/$_incident',
        'https://uptrack.app.evil.test/dashboard/incidents/$_incident',
        'http://uptrack.app/dashboard/incidents/$_incident',
        'https://uptrack.app:8443/dashboard/incidents/$_incident',
        'https://user@uptrack.app/dashboard/incidents/$_incident',
        'uptrack://app/dashboard/incidents/$_incident',
      ]) {
        expect(universalLinkLocation(Uri.parse(url)), isNull, reason: url);
      }
    });

    test('rejects web paths the app does not have', () {
      for (final String path in <String>[
        '/',
        '/dashboard',
        '/dashboard/incidents',
        '/dashboard/monitors',
        '/dashboard/monitors/new',
        '/dashboard/monitors/import',
        '/dashboard/monitors/$_monitor/edit',
        '/dashboard/monitors/$_monitor/browser-runs',
        '/dashboard/incidents/$_incident/',
        '/dashboard/incidents/not-a-uuid',
        '/dashboard/incidents/../settings',
        // App-internal paths are not web paths.
        '/incidents/$_incident',
        '/monitors/$_monitor',
        '/magic',
        '/billing/return',
        '/pricing',
        '/status/acme',
      ]) {
        expect(
          universalLinkLocation(Uri.parse('https://uptrack.app$path')),
          isNull,
          reason: path,
        );
      }
    });

    test('rejects a magic link without an email or token', () {
      for (final String query in <String>[
        'email=ada%40example.com&client=mobile',
        'token=abc&client=mobile',
        'token=&email=ada%40example.com',
        'token=abc&email=not-an-email',
      ]) {
        expect(
          universalLinkLocation(
            Uri.parse('https://uptrack.app/auth/verify-magic-link?$query'),
          ),
          isNull,
          reason: query,
        );
      }
    });
  });

  group('the router', () {
    Future<Uri> resolve(
      WidgetTester tester,
      GoRouter router,
      String link,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      // Ask the router where the link leads without building any screen.
      final matches = await router.routeInformationParser
          .parseRouteInformationWithDependencies(
            RouteInformation(uri: Uri.parse(link)),
            context,
          );
      return matches.uri;
    }

    testWidgets('sends an https link to the matching in-app screen', (
      WidgetTester tester,
    ) async {
      final GoRouter router = createRouter(
        authStatusOf: () => AuthStatus.signedIn,
      );
      addTearDown(router.dispose);
      expect(
        (await resolve(
          tester,
          router,
          'https://uptrack.app/dashboard/incidents/$_incident',
        )).toString(),
        '/incidents/$_incident',
      );
      expect(
        (await resolve(
          tester,
          router,
          'https://uptrack.app/dashboard/monitors/$_monitor',
        )).toString(),
        '/monitors/$_monitor',
      );
    });

    testWidgets('opens the magic link even when signed out', (
      WidgetTester tester,
    ) async {
      final GoRouter router = createRouter(
        authStatusOf: () => AuthStatus.signedOut,
      );
      addTearDown(router.dispose);
      final Uri uri = await resolve(
        tester,
        router,
        'https://uptrack.app/auth/verify-magic-link'
        '?token=abc&email=ada%40example.com&client=mobile',
      );
      expect(uri.path, '/magic');
      expect(uri.queryParameters['token'], 'abc');
    });

    testWidgets('sends an unknown or foreign https link to the home screen', (
      WidgetTester tester,
    ) async {
      final GoRouter router = createRouter(
        authStatusOf: () => AuthStatus.signedIn,
      );
      addTearDown(router.dispose);
      for (final String link in <String>[
        'https://uptrack.app/dashboard/monitors/new',
        'https://uptrack.app/pricing',
        // The app path exists, but it is not a web path.
        'https://uptrack.app/incidents/$_incident',
        'https://evil.test/dashboard/incidents/$_incident',
        'https://evil.test/monitors/$_monitor',
      ]) {
        expect(
          (await resolve(tester, router, link)).toString(),
          '/',
          reason: link,
        );
      }
    });

    testWidgets('keeps the uptrack:// scheme links working', (
      WidgetTester tester,
    ) async {
      final GoRouter router = createRouter(
        authStatusOf: () => AuthStatus.signedOut,
      );
      addTearDown(router.dispose);
      final Uri uri = await resolve(
        tester,
        router,
        'uptrack://auth/magic?email=ada%40example.com&token=abc',
      );
      expect(uri.path, '/magic');
    });
  });
}
