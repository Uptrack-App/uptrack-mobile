import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// First iOS version where the server can start a Live Activity while the
/// app is closed (ActivityKit push-to-start). Below it, iOS 16.1 to 17.1
/// starts the activity locally while the app runs (plan item 5.3, see
/// `lib/widgets/live_activity_sync.dart`); iOS 16.0 has no ActivityKit.
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
  const String fallback = 'You still get push alerts and lock-screen buttons.';
  final ({int major, int minor})? version = parseIosVersion(osVersion);
  if (version == null ||
      (version.major == 16 && version.minor < 1) ||
      version.major < 16) {
    return 'Live Activities need iOS 16.1 or later. $fallback';
  }
  return 'A Live Activity starts only while Uptrack is open. With iOS '
      '$kLiveActivityMinMajor.$kLiveActivityMinMinor or later, it also starts '
      'when the app is closed.';
}

/// The raw OS version text; a provider so tests can replace it.
final Provider<String> osVersionProvider = Provider<String>(
  (Ref ref) => Platform.operatingSystemVersion,
);
