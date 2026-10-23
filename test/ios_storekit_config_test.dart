import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/features/billing/apple_plans.dart';

/// `ios/Runner/Uptrack.storekit` is the local StoreKit test configuration
/// (plan step 5.10). Xcode's Run action uses it (Runner scheme), so local
/// purchases need no App Store Connect products. It must list the same
/// products as the app, in one group with the D6 levels.
void main() {
  final Map<String, Object?> config = jsonDecode(
    File('ios/Runner/Uptrack.storekit').readAsStringSync(),
  ) as Map<String, Object?>;

  test('one "Uptrack" group with every product the app sells', () {
    final List<Object?> groups = config['subscriptionGroups']! as List<Object?>;
    expect(groups, hasLength(1));
    final Map<String, Object?> group = groups.single! as Map<String, Object?>;
    expect(group['name'], 'Uptrack');
    final List<Map<String, Object?>> subs =
        (group['subscriptions']! as List<Object?>).cast<Map<String, Object?>>();
    expect(
      subs.map((Map<String, Object?> s) => s['productID']).toSet(),
      kAppleProductIds,
    );
    for (final Map<String, Object?> s in subs) {
      final AppleProduct p = appleProductById(s['productID']! as String)!;
      expect(
        s['recurringSubscriptionPeriod'],
        p.period == BillingPeriod.monthly ? 'P1M' : 'P1Y',
      );
      // Levels: Business (1) > Team (2) > Pro (3).
      expect(
        s['groupNumber'],
        <String, int>{'business': 1, 'team': 2, 'pro': 3}[p.plan],
      );
    }
  });

  test('the Runner scheme runs with the StoreKit configuration', () {
    expect(
      File('ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme')
          .readAsStringSync(),
      contains('identifier = "../Runner/Uptrack.storekit"'),
    );
  });

  test('the configuration is not shipped in the app bundle', () {
    expect(
      File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
      isNot(contains('Uptrack.storekit')),
    );
  });
}
