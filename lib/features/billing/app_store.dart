import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart' as sk2;
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// A product as the App Store returns it for the user's storefront.
/// [displayPrice] is Apple's localized price text (for example `$2.99`).
class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.displayPrice,
  });

  final String id;
  final String title;
  final String description;
  final String displayPrice;
}

enum StoreTransactionState { purchased, restored, pending, canceled, failed }

/// What `Product.purchase()` answered. The transaction itself (for
/// [success] and [unverified]) arrives on [AppStoreClient.updates], and it
/// can arrive after `buy` returns.
enum StorePurchaseResult { success, unverified, pending, userCancelled }

/// One update from StoreKit: a new purchase, a restored or renewed
/// transaction, an unfinished transaction from an earlier launch, or a
/// purchase that is pending (Ask to Buy) or canceled.
class StoreTransaction {
  const StoreTransaction({
    required this.productId,
    required this.state,
    this.transactionId,
    this.signedTransaction = '',
    this.errorMessage,
    this.appAccountToken,
    this.expiresAt,
  });

  final String productId;
  final StoreTransactionState state;

  /// StoreKit `Transaction.id`. Null when there is no transaction yet
  /// (pending or canceled).
  final String? transactionId;

  /// The StoreKit 2 JWS (`VerificationResult.jwsRepresentation`) that the
  /// server checks.
  final String signedTransaction;
  final String? errorMessage;

  /// The `appAccountToken` of the purchase: the organization ID that the
  /// app set at purchase time. StoreKit gives it in upper case.
  final String? appAccountToken;

  /// When the subscription period of this transaction ends (StoreKit
  /// `expirationDate`). Null when StoreKit gives none.
  final DateTime? expiresAt;

  bool get hasTransaction =>
      transactionId != null && signedTransaction.isNotEmpty;
}

/// The App Store, as the app uses it. Tests use a fake; iOS uses
/// [StoreKitAppStore].
abstract class AppStoreClient {
  Future<bool> isAvailable();

  /// Products the App Store knows. A missing ID is not in the result.
  Future<List<StoreProduct>> products(Set<String> ids);

  /// All transaction updates (purchase results, `Transaction.updates`,
  /// restores).
  Stream<List<StoreTransaction>> get updates;

  /// `Transaction.unfinished`: transactions that a crash or a failed server
  /// call left open in an earlier launch.
  Future<List<StoreTransaction>> unfinished();

  /// The live subscriptions of this Apple ID: not expired, not revoked and
  /// not replaced by an upgrade. Reads StoreKit's data on the device, so it
  /// shows no App Store sign-in. The result is not sent on [updates].
  Future<List<StoreTransaction>> currentEntitlements();

  /// Starts a purchase and returns StoreKit's purchase result. The
  /// transaction arrives on [updates], before or after this returns.
  /// [appAccountToken] is the organization ID (lowercase UUID).
  Future<StorePurchaseResult> buy(
    String productId, {
    required String appAccountToken,
  });

  /// `Transaction.finish()`. Call it only after the server accepted the
  /// transaction.
  Future<void> finish(String transactionId);

  /// Sends the current entitlements on [updates] as restored, in one batch.
  /// The batch is sent also when it is empty, and it can arrive after this
  /// returns.
  Future<void> restore();

  /// Apple's "Manage Subscriptions" sheet.
  Future<void> showManageSubscriptions();

  /// Opens a web page (Terms of Use, Privacy Policy) in an in-app browser.
  Future<void> openUrl(Uri url);
}

/// StoreKit 2 through the official `in_app_purchase_storekit` plugin (the iOS
/// implementation of `in_app_purchase`). The app depends on the iOS package
/// only, so the Android app gets no Play Billing library (plan D9).
class StoreKitAppStore implements AppStoreClient {
  StoreKitAppStore() {
    if (!_registered) {
      InAppPurchaseStoreKitPlatform.registerPlatform();
      _registered = true;
    }
  }

  static bool _registered = false;

  InAppPurchasePlatform get _platform => InAppPurchasePlatform.instance;

  @override
  Future<bool> isAvailable() => _platform.isAvailable();

  @override
  Future<List<StoreProduct>> products(Set<String> ids) async {
    final List<sk2.SK2Product> products = await sk2.SK2Product.products(
      ids.toList(),
    );
    return <StoreProduct>[
      for (final sk2.SK2Product p in products)
        StoreProduct(
          id: p.id,
          title: p.displayName,
          description: p.description,
          displayPrice: p.displayPrice,
        ),
    ];
  }

  @override
  Stream<List<StoreTransaction>> get updates => _platform.purchaseStream.map(
    (List<PurchaseDetails> list) => <StoreTransaction>[
      for (final PurchaseDetails d in list) _fromDetails(d),
    ],
  );

  static StoreTransaction _fromDetails(PurchaseDetails d) => StoreTransaction(
    productId: d.productID,
    state: switch (d.status) {
      PurchaseStatus.purchased => StoreTransactionState.purchased,
      PurchaseStatus.restored => StoreTransactionState.restored,
      PurchaseStatus.pending => StoreTransactionState.pending,
      PurchaseStatus.canceled => StoreTransactionState.canceled,
      PurchaseStatus.error => StoreTransactionState.failed,
    },
    transactionId: d.purchaseID,
    signedTransaction: d.verificationData.serverVerificationData,
    errorMessage: d.error?.message,
    appAccountToken: d is SK2PurchaseDetails ? d.appAccountToken : null,
    expiresAt: d is SK2PurchaseDetails ? _fromMillis(d.expirationDate) : null,
  );

  /// The plugin gives dates as milliseconds since the epoch, in text.
  static DateTime? _fromMillis(String? ms) {
    final int? v = ms == null ? null : int.tryParse(ms);
    return v == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
  }

  @override
  Future<List<StoreTransaction>> unfinished() async {
    final List<sk2.SK2Transaction> list =
        await sk2.SK2Transaction.unfinishedTransactions();
    return <StoreTransaction>[
      for (final sk2.SK2Transaction t in list)
        StoreTransaction(
          productId: t.productId,
          state: StoreTransactionState.purchased,
          transactionId: t.id,
          signedTransaction: t.receiptData ?? '',
          appAccountToken: t.appAccountToken,
          expiresAt: _fromMillis(t.expirationDate),
        ),
    ];
  }

  /// StoreKit `Transaction.all` through `SK2Transaction.transactions()`.
  /// The plugin reads it on the device and never calls `AppStore.sync()`,
  /// so there is no sign-in prompt. `restorePurchases()` reads
  /// `Transaction.currentEntitlements` without a prompt too, but it sends
  /// the result on the purchase stream, where each one would go to the
  /// server.
  @override
  Future<List<StoreTransaction>> currentEntitlements() async =>
      liveEntitlements(await sk2.SK2Transaction.transactions(), DateTime.now());

  /// The transactions of [all] that still give access at [now]. The plugin
  /// gives no revocation date or upgrade flag, so they come from the
  /// transaction's JSON (`revocationDate`, `isUpgraded`).
  @visibleForTesting
  static List<StoreTransaction> liveEntitlements(
    List<sk2.SK2Transaction> all,
    DateTime now,
  ) {
    final List<StoreTransaction> live = <StoreTransaction>[];
    for (final sk2.SK2Transaction t in all) {
      final DateTime? expiresAt = _fromMillis(t.expirationDate);
      if (expiresAt == null || !expiresAt.isAfter(now)) continue;
      final Map<String, Object?> json = _json(t.jsonRepresentation);
      if (json['revocationDate'] != null || json['isUpgraded'] == true) {
        continue;
      }
      live.add(
        StoreTransaction(
          productId: t.productId,
          state: StoreTransactionState.purchased,
          transactionId: t.id,
          appAccountToken: t.appAccountToken,
          expiresAt: expiresAt,
        ),
      );
    }
    return live;
  }

  static Map<String, Object?> _json(String? text) {
    if (text == null || text.isEmpty) return const <String, Object?>{};
    try {
      final Object? v = jsonDecode(text);
      return v is Map<String, Object?> ? v : const <String, Object?>{};
    } on FormatException {
      return const <String, Object?>{};
    }
  }

  @override
  Future<StorePurchaseResult> buy(
    String productId, {
    required String appAccountToken,
  }) async {
    final sk2.SK2ProductPurchaseResult result = await sk2.SK2Product.purchase(
      productId,
      options: sk2.SK2ProductPurchaseOptions(appAccountToken: appAccountToken),
    );
    return switch (result) {
      sk2.SK2ProductPurchaseResult.success => StorePurchaseResult.success,
      sk2.SK2ProductPurchaseResult.unverified => StorePurchaseResult.unverified,
      sk2.SK2ProductPurchaseResult.pending => StorePurchaseResult.pending,
      sk2.SK2ProductPurchaseResult.userCancelled =>
        StorePurchaseResult.userCancelled,
    };
  }

  @override
  Future<void> finish(String transactionId) =>
      sk2.SK2Transaction.finish(int.parse(transactionId));

  @override
  Future<void> restore() => sk2.SK2Transaction.restorePurchases();

  @override
  Future<void> showManageSubscriptions() =>
      sk2.AppStore().showManageSubscriptions();

  @override
  Future<void> openUrl(Uri url) async {
    await UrlLauncherPlatform.instance.launchUrl(
      url.toString(),
      const LaunchOptions(mode: PreferredLaunchMode.inAppBrowserView),
    );
  }
}

/// The App Store on iOS; null on Android and web, where the app sells nothing
/// (plan D9).
AppStoreClient? createPlatformAppStore() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
  return StoreKitAppStore();
}
