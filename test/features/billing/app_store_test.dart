import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart' as sk2;
import 'package:uptrack_mobile/features/billing/app_store.dart';

/// A transaction as `SK2Transaction.transactions()` (StoreKit
/// `Transaction.all`) gives it: dates in milliseconds, in text.
sk2.SK2Transaction _tx(
  String id, {
  required DateTime expires,
  String? token = 'ORG',
  Map<String, Object?> json = const <String, Object?>{},
}) => sk2.SK2Transaction(
  id: id,
  originalId: '1',
  productId: 'app.uptrack.mobile.pro.monthly',
  purchaseDate: '0',
  expirationDate: expires.millisecondsSinceEpoch.toString(),
  appAccountToken: token,
  jsonRepresentation: jsonEncode(<String, Object?>{
    'transactionId': id,
    ...json,
  }),
);

void main() {
  test('live entitlements: not expired, not revoked, not upgraded', () {
    final DateTime now = DateTime.utc(2026, 10, 23);
    final DateTime later = now.add(const Duration(days: 10));
    final List<StoreTransaction> live = StoreKitAppStore.liveEntitlements(
      <sk2.SK2Transaction>[
        _tx('live', expires: later),
        _tx('expired', expires: now.subtract(const Duration(days: 1))),
        _tx(
          'revoked',
          expires: later,
          json: <String, Object?>{'revocationDate': 1761177600000},
        ),
        _tx(
          'upgraded',
          expires: later,
          json: <String, Object?>{'isUpgraded': true},
        ),
      ],
      now,
    );
    expect(live.map((StoreTransaction t) => t.transactionId), <String>['live']);
    expect(live.single.appAccountToken, 'ORG');
    expect(live.single.productId, 'app.uptrack.mobile.pro.monthly');
    expect(live.single.expiresAt, later);
  });
}
