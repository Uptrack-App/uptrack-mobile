import '../features/auth/auth_controller.dart' show parseMagicLink;

/// The only web host whose links open the app (universal links on iOS, app
/// links on Android). It must match the `applinks:` entitlement, the Android
/// `autoVerify` intent filter, and the files that uptrack.app serves at
/// `/.well-known/apple-app-site-association` and `/.well-known/assetlinks.json`.
const String kUniversalLinkHost = 'uptrack.app';

/// Server ids are UUIDs. The web route `/dashboard/monitors/new` and other
/// sibling paths must not open the app, so the id must be a whole UUID.
final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Maps an `https://uptrack.app/...` link to an in-app location, or returns
/// null when the app has no screen for it.
///
/// Accepted links (the URLs that the server writes into emails):
/// * `/auth/verify-magic-link?token=…&email=…` → `/magic?email=…&token=…`.
///   Other query values (such as a web `redirect`) are dropped.
/// * `/dashboard/incidents/<uuid>` → `/incidents/<uuid>`
/// * `/dashboard/monitors/<uuid>` → `/monitors/<uuid>`
String? universalLinkLocation(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.host != kUniversalLinkHost ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443) {
    return null;
  }
  if (uri.path == '/auth/verify-magic-link') {
    final ({String email, String token})? magic = parseMagicLink(uri);
    if (magic == null) return null;
    return Uri(
      path: '/magic',
      queryParameters: <String, String>{
        'email': magic.email,
        'token': magic.token,
      },
    ).toString();
  }
  final List<String> segments = uri.pathSegments;
  if (segments.length == 3 &&
      segments[0] == 'dashboard' &&
      _uuid.hasMatch(segments[2])) {
    switch (segments[1]) {
      case 'incidents':
        return '/incidents/${segments[2]}';
      case 'monitors':
        return '/monitors/${segments[2]}';
    }
  }
  return null;
}
