import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:uptrack_mobile/features/billing/app_store.dart';

/// A StoreKit stand-in. Prices here are test data: the app must show
/// whatever the store returns.
class FakeAppStore implements AppStoreClient {
  FakeAppStore({
    List<StoreProduct>? products,
    this.onBuy,
    this.restored = const <StoreTransaction>[],
    this.leftovers = const <StoreTransaction>[],
    this.entitlements = const <StoreTransaction>[],
  }) : catalog = products ?? fakeProducts();

  List<StoreProduct> catalog;
  Object? productsError;
  final StreamController<List<StoreTransaction>> _updates =
      StreamController<List<StoreTransaction>>.broadcast();

  /// What StoreKit sends after a purchase. Default: a purchased transaction.
  StoreTransaction? Function(String productId)? onBuy;
  PlatformException? buyError;
  List<StoreTransaction> restored;
  List<StoreTransaction> leftovers;

  /// The live entitlements of the Apple ID (read before a purchase).
  List<StoreTransaction> entitlements;
  Object? entitlementsError;
  int entitlementReads = 0;

  final List<({String productId, String appAccountToken})> buys =
      <({String productId, String appAccountToken})>[];
  final List<String> finished = <String>[];
  final List<Uri> opened = <Uri>[];
  int manageSheets = 0;
  int restores = 0;

  /// Like the plugin on a device: StoreKit's update reaches Dart after
  /// `buy` and `restore` return (the native side sends it from its own
  /// task, after it answers the call).
  bool lateUpdates = false;

  void emit(List<StoreTransaction> updates) => _updates.add(updates);

  void _send(List<StoreTransaction> updates) {
    if (lateUpdates) {
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 20),
          () => _updates.add(updates),
        ),
      );
    } else {
      _updates.add(updates);
    }
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<StoreProduct>> products(Set<String> ids) async {
    if (productsError != null) throw productsError!;
    return catalog.where((StoreProduct p) => ids.contains(p.id)).toList();
  }

  @override
  Stream<List<StoreTransaction>> get updates => _updates.stream;

  @override
  Future<List<StoreTransaction>> unfinished() async => leftovers;

  @override
  Future<List<StoreTransaction>> currentEntitlements() async {
    entitlementReads++;
    if (entitlementsError != null) throw entitlementsError!;
    return entitlements;
  }

  @override
  Future<StorePurchaseResult> buy(
    String productId, {
    required String appAccountToken,
  }) async {
    buys.add((productId: productId, appAccountToken: appAccountToken));
    if (buyError != null) throw buyError!;
    final StoreTransaction? result = onBuy == null
        ? purchased(
            productId,
            'tx-$productId',
            token: appAccountToken.toUpperCase(),
          )
        : onBuy!(productId);
    if (result != null) _send(<StoreTransaction>[result]);
    return switch (result?.state) {
      StoreTransactionState.pending => StorePurchaseResult.pending,
      StoreTransactionState.canceled ||
      null => StorePurchaseResult.userCancelled,
      _ => StorePurchaseResult.success,
    };
  }

  @override
  Future<void> finish(String transactionId) async {
    finished.add(transactionId);
  }

  @override
  Future<void> restore() async {
    restores++;
    // The plugin always sends one batch, also an empty one.
    _send(restored);
  }

  @override
  Future<void> showManageSubscriptions() async {
    manageSheets++;
  }

  @override
  Future<void> openUrl(Uri url) async {
    opened.add(url);
  }
}

/// The organization of the test owner. StoreKit gives the
/// `appAccountToken` back in upper case (Swift `UUID.uuidString`).
const String kFakeOrgId = '2C9F7B1E-4D3A-4F2B-9E8D-7A6B5C4D3E2F';

StoreTransaction purchased(
  String productId,
  String id, {
  String? token = kFakeOrgId,
  DateTime? expiresAt,
}) => StoreTransaction(
  productId: productId,
  state: StoreTransactionState.purchased,
  transactionId: id,
  signedTransaction: 'jws.$id',
  appAccountToken: token,
  expiresAt: expiresAt,
);

StoreTransaction restoredTx(
  String productId,
  String id, {
  String? token = kFakeOrgId,
}) => StoreTransaction(
  productId: productId,
  state: StoreTransactionState.restored,
  transactionId: id,
  signedTransaction: 'jws.$id',
  appAccountToken: token,
);

/// Made-up storefront prices (not the D6 prices), so a test catches any
/// hard-coded price.
List<StoreProduct> fakeProducts() => const <StoreProduct>[
  StoreProduct(
    id: 'app.uptrack.mobile.pro.monthly',
    title: 'Pro',
    description: 'Pro monthly',
    displayPrice: '€3.49',
  ),
  StoreProduct(
    id: 'app.uptrack.mobile.pro.yearly',
    title: 'Pro',
    description: 'Pro yearly',
    displayPrice: '€34.99',
  ),
  StoreProduct(
    id: 'app.uptrack.mobile.team.monthly',
    title: 'Team',
    description: 'Team monthly',
    displayPrice: '€21.99',
  ),
  StoreProduct(
    id: 'app.uptrack.mobile.team.yearly',
    title: 'Team',
    description: 'Team yearly',
    displayPrice: '€199.99',
  ),
  StoreProduct(
    id: 'app.uptrack.mobile.business.monthly',
    title: 'Business',
    description: 'Business monthly',
    displayPrice: '€89.99',
  ),
];
