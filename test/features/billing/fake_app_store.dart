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

  final List<({String productId, String appAccountToken})> buys =
      <({String productId, String appAccountToken})>[];
  final List<String> finished = <String>[];
  final List<Uri> opened = <Uri>[];
  int manageSheets = 0;
  int restores = 0;

  void emit(List<StoreTransaction> updates) => _updates.add(updates);

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
  Future<void> buy(String productId, {required String appAccountToken}) async {
    buys.add((productId: productId, appAccountToken: appAccountToken));
    if (buyError != null) throw buyError!;
    final StoreTransaction? result = onBuy == null
        ? purchased(productId, 'tx-$productId')
        : onBuy!(productId);
    if (result != null) _updates.add(<StoreTransaction>[result]);
  }

  @override
  Future<void> finish(String transactionId) async {
    finished.add(transactionId);
  }

  @override
  Future<void> restore() async {
    restores++;
    if (restored.isNotEmpty) _updates.add(restored);
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

StoreTransaction purchased(String productId, String id) => StoreTransaction(
  productId: productId,
  state: StoreTransactionState.purchased,
  transactionId: id,
  signedTransaction: 'jws.$id',
);

StoreTransaction restoredTx(String productId, String id) => StoreTransaction(
  productId: productId,
  state: StoreTransactionState.restored,
  transactionId: id,
  signedTransaction: 'jws.$id',
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
