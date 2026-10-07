import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// First iOS version where the server can start a Live Activity while the
/// app is closed (ActivityKit push-to-start). Decision D9 in
/// `uptrack-spec/docs/mobile/ios-release-plan.md`: older iOS versions get
/// push alerts, lock-screen buttons and the widget, but no Live Activity,
/// because a local start only works while the app is open.
const int kLiveActivityMinMajor = 17;
const int kLiveActivityMinMinor = 2;

/// Reads `major.minor` from `Platform.operatingSystemVersion`, which on iOS
/// looks like `Version 17.2 (Build 21C62)`. Null when the text has no
/// version. An unknown version is never treated as supported.
({int major, int minor})? parseIosVersion(String raw) {
  final RegExpMatch? match = RegExp(r'(\d+)\.(\d+)').firstMatch(raw);
  if (match == null) {
    return null;
  }
  return (major: int.parse(match.group(1)!), minor: int.parse(match.group(2)!));
}

/// True when Live Activities can start from a push on this device.
/// Only meaningful on iOS; every other platform returns false.
bool liveActivitiesSupported({
  required TargetPlatform platform,
  required String osVersion,
}) {
  if (platform != TargetPlatform.iOS) {
    return false;
  }
  final ({int major, int minor})? version = parseIosVersion(osVersion);
  if (version == null) {
    return false;
  }
  return version.major > kLiveActivityMinMajor ||
      (version.major == kLiveActivityMinMajor &&
          version.minor >= kLiveActivityMinMinor);
}

/// Hint for Settings → Notifications, or null when nothing needs saying
/// (not iOS, or iOS 17.2 and later).
String? liveActivityHint({
  required TargetPlatform platform,
  required String osVersion,
}) {
  if (platform != TargetPlatform.iOS) {
    return null;
  }
  if (liveActivitiesSupported(platform: platform, osVersion: osVersion)) {
    return null;
  }
  return 'Live Activities need iOS $kLiveActivityMinMajor.$kLiveActivityMinMinor '
      'or later. You still get push alerts and lock-screen buttons.';
}

/// The raw OS version text; a provider so tests can replace it.
final Provider<String> osVersionProvider = Provider<String>(
  (Ref ref) => Platform.operatingSystemVersion,
);
