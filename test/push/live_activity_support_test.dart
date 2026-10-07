import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/push/live_activity_support.dart';

void main() {
  group('parseIosVersion', () {
    test('reads major and minor from the iOS version text', () {
      expect(parseIosVersion('Version 17.2 (Build 21C62)'), (
        major: 17,
        minor: 2,
      ));
      expect(parseIosVersion('Version 16.0.3 (Build 20A392)'), (
        major: 16,
        minor: 0,
      ));
    });

    test('returns null when there is no version', () {
      expect(parseIosVersion(''), isNull);
      expect(parseIosVersion('unknown'), isNull);
    });
  });

  group('liveActivitiesSupported (D9: iOS 17.2 and later)', () {
    bool supported(String version, {TargetPlatform p = TargetPlatform.iOS}) =>
        liveActivitiesSupported(platform: p, osVersion: version);

    test('17.1 is below the line, 17.2 is on it', () {
      expect(supported('Version 17.1 (Build 21B74)'), isFalse);
      expect(supported('Version 17.2 (Build 21C62)'), isTrue);
    });

    test('later majors pass whatever the minor is', () {
      expect(supported('Version 18.0 (Build 22A3354)'), isTrue);
      expect(supported('Version 26.0 (Build 23A344)'), isTrue);
    });

    test('earlier majors fail whatever the minor is', () {
      expect(supported('Version 16.7 (Build 20H19)'), isFalse);
    });

    test('an unreadable version is never treated as supported', () {
      expect(supported('???'), isFalse);
    });

    test('other platforms are never supported', () {
      expect(supported('Version 18.0', p: TargetPlatform.android), isFalse);
    });
  });

  group('liveActivityHint', () {
    test('shows only on iOS below 17.2', () {
      expect(
        liveActivityHint(
          platform: TargetPlatform.iOS,
          osVersion: 'Version 16.4 (Build 20E247)',
        ),
        contains('iOS 17.2'),
      );
      expect(
        liveActivityHint(
          platform: TargetPlatform.iOS,
          osVersion: 'Version 17.2 (Build 21C62)',
        ),
        isNull,
      );
      expect(
        liveActivityHint(
          platform: TargetPlatform.android,
          osVersion: 'Version 16.4',
        ),
        isNull,
      );
    });

    test('an unreadable iOS version shows the hint, not silence', () {
      expect(
        liveActivityHint(platform: TargetPlatform.iOS, osVersion: '???'),
        isNotNull,
      );
    });
  });
}
