import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android app links for https://uptrack.app.
///
/// Android opens these links in the app only when the intent filter has
/// `android:autoVerify="true"` AND uptrack.app serves a matching
/// `/.well-known/assetlinks.json`. The paths must match the web URLs that
/// `universalLinkLocation` (lib/util/universal_links.dart) accepts.
void main() {
  final String manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  String appLinkFilter() {
    final RegExpMatch? match = RegExp(
      r'<intent-filter android:autoVerify="true">(.*?)</intent-filter>',
      dotAll: true,
    ).firstMatch(manifest);
    expect(match, isNotNull, reason: 'no autoVerify intent filter');
    return match!.group(1)!;
  }

  test('one verified https filter for uptrack.app only', () {
    expect(RegExp('android:autoVerify="true"').allMatches(manifest).length, 1);
    final String filter = appLinkFilter();
    expect(filter, contains('android.intent.action.VIEW'));
    expect(filter, contains('android.intent.category.DEFAULT'));
    expect(filter, contains('android.intent.category.BROWSABLE'));
    expect(filter, contains('android:scheme="https"'));
    expect(filter, isNot(contains('android:scheme="http"')));
    final Set<String> hosts = RegExp(r'android:host="([^"]+)"')
        .allMatches(filter)
        .map((RegExpMatch m) => m.group(1)!)
        .toSet();
    expect(hosts, <String>{'uptrack.app'});
  });

  test('the filter lists only the paths the app handles', () {
    final String filter = appLinkFilter();
    final Set<String> paths = RegExp(r'android:path(?:Pattern)?="([^"]+)"')
        .allMatches(filter)
        .map((RegExpMatch m) => m.group(1)!)
        .toSet();
    const String uuid = '........-....-....-....-............';
    expect(paths, <String>{
      '/auth/verify-magic-link',
      '/dashboard/incidents/$uuid',
      '/dashboard/monitors/$uuid',
    });
    expect(filter, isNot(contains('pathPrefix')));
  });
}
