import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/billing_subscription.dart';
import '../../api/models/current_user.dart';
import '../../api/uptrack_api.dart';
import '../auth/auth_controller.dart';
import '../settings/billing_section.dart' show settingsBillingProvider;
import '../settings/profile_section.dart'
    show planLabel, settingsProfileProvider;
import 'app_store.dart';
import 'apple_plans.dart';

/// The App Store on iOS; null on Android and web. Tests override it.
final Provider<AppStoreClient?> appStoreClientProvider =
    Provider<AppStoreClient?>((Ref ref) => createPlatformAppStore());

/// The app sells plans with In-App Purchase: iOS only, and only when the
/// build turns on [kAppleIapEnabled]. Tests override it.
final Provider<bool> appleIapEnabledProvider = Provider<bool>(
  (Ref ref) => kAppleIapEnabled && ref.watch(appStoreClientProvider) != null,
);

/// The App Store products for this storefront, by product ID. Prices come
/// only from here, never from the app code.
final FutureProvider<Map<String, StoreProduct>> appleProductsProvider =
    FutureProvider<Map<String, StoreProduct>>((Ref ref) async {
      final AppStoreClient? store = ref.watch(appStoreClientProvider);
      if (store == null) return const <String, StoreProduct>{};
      final List<StoreProduct> products = await store.products(
        kAppleProductIds,
      );
      return <String, StoreProduct>{
        for (final StoreProduct p in products) p.id: p,
      };
    });

enum PurchaseNoticeKind { info, success, error }

class PurchaseNotice {
  const PurchaseNotice(this.message, this.kind);

  final String message;
  final PurchaseNoticeKind kind;
}

class ApplePurchaseState {
  const ApplePurchaseState({
    this.busyProductId,
    this.restoring = false,
    this.notice,
  });

  /// The product whose purchase is in progress (App Store sheet or server
  /// check).
  final String? busyProductId;
  final bool restoring;
  final PurchaseNotice? notice;

  bool get busy => busyProductId != null || restoring;
}

/// UUID text, as the organization ID and the StoreKit `appAccountToken` are.
final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// The In-App Purchase flow (plan steps 5.6 and 5.8):
///
/// 1. [buy] sets `appAccountToken` to the organization ID (lowercase UUID).
/// 2. Each signed transaction from StoreKit (a purchase, a restore, a renewal
///    or an unfinished transaction from an earlier launch) goes to
///    `POST /api/billing/apple/transactions`.
/// 3. The transaction is finished only after the server answers 200. On any
///    other answer it stays unfinished, so StoreKit gives it again at the
///    next launch, and Restore Purchases sends it again.
///
/// Upgrade and downgrade are a [buy] of another product of the same
/// subscription group: the App Store does the change.
class ApplePurchaseController extends Notifier<ApplePurchaseState> {
  StreamSubscription<List<StoreTransaction>>? _updates;
  final Set<String> _inFlight = <String>{};
  final List<Future<void>> _deliveries = <Future<void>>[];
  int _restoredSeen = 0;
  bool _sawBusyUpdate = false;

  AppStoreClient? get _store => ref.read(appStoreClientProvider);

  @override
  ApplePurchaseState build() {
    final AppStoreClient? store = ref.watch(appStoreClientProvider);
    if (store != null) {
      _updates = store.updates.listen(_onUpdates);
      ref.onDispose(() => _updates?.cancel());
    }
    return const ApplePurchaseState();
  }

  /// Sends every unfinished transaction to the server again, and finishes
  /// each one that the server accepts. Silent: there is no user action.
  /// The app calls it at each sign-in (so at each launch with a session).
  Future<void> finishLeftovers() async {
    final AppStoreClient? store = _store;
    if (store == null) return;
    final List<StoreTransaction> leftovers;
    try {
      leftovers = await store.unfinished();
    } on Object {
      return;
    }
    if (!ref.mounted) return;
    await Future.wait(<Future<void>>[
      for (final StoreTransaction t in leftovers)
        if (t.hasTransaction) _deliver(t, userVisible: false),
    ]);
  }

  void clearNotice() {
    if (state.notice != null) {
      state = ApplePurchaseState(
        busyProductId: state.busyProductId,
        restoring: state.restoring,
      );
    }
  }

  /// Starts the App Store purchase of [productId] for the caller's
  /// organization. The owner only (D8).
  Future<void> buy(String productId) async {
    final AppStoreClient? store = _store;
    if (store == null || state.busy) return;
    state = ApplePurchaseState(busyProductId: productId);
    _sawBusyUpdate = false;
    try {
      final CurrentUserResponse me = await ref.read(uptrackApiProvider).getMe();
      if (!ref.mounted) return;
      if (me.user.role != 'owner') {
        _fail(productId, 'Only the organization owner can buy a plan.');
        return;
      }
      final String token = me.organization.id.toLowerCase();
      if (!_uuid.hasMatch(token)) {
        _fail(productId, 'Could not start the purchase. Try again later.');
        return;
      }
      await store.buy(productId, appAccountToken: token);
      // StoreKit sends the result on the updates stream before `buy`
      // returns. Let that event arrive first.
      await Future<void>.delayed(Duration.zero);
      if (!ref.mounted) return;
      if (!_sawBusyUpdate && state.busyProductId == productId) {
        state = const ApplePurchaseState();
      }
    } on DioException {
      if (!ref.mounted) return;
      _fail(
        productId,
        'Could not reach Uptrack. Check your connection and try again.',
      );
    } on PlatformException catch (e) {
      if (!ref.mounted) return;
      _fail(productId, _storeError(e));
    }
  }

  /// Restore Purchases: StoreKit sends the current entitlements, and each one
  /// goes to the server (the same call as a purchase).
  Future<void> restore() async {
    final AppStoreClient? store = _store;
    if (store == null || state.busy) return;
    state = const ApplePurchaseState(restoring: true);
    _restoredSeen = 0;
    _deliveries.clear();
    try {
      await store.restore();
      await Future<void>.delayed(Duration.zero);
      await Future.wait(List<Future<void>>.of(_deliveries));
      if (!ref.mounted) return;
      if (_restoredSeen == 0) {
        state = const ApplePurchaseState(
          notice: PurchaseNotice(
            'No App Store subscription to restore for this Apple ID.',
            PurchaseNoticeKind.info,
          ),
        );
        return;
      }
      state = ApplePurchaseState(notice: state.notice);
    } on PlatformException catch (e) {
      if (!ref.mounted) return;
      state = ApplePurchaseState(
        notice: PurchaseNotice(_storeError(e), PurchaseNoticeKind.error),
      );
    }
  }

  void _onUpdates(List<StoreTransaction> updates) {
    for (final StoreTransaction t in updates) {
      final bool mine = state.busyProductId == t.productId;
      if (mine) _sawBusyUpdate = true;
      switch (t.state) {
        case StoreTransactionState.pending:
          if (mine) {
            state = const ApplePurchaseState(
              notice: PurchaseNotice(
                'The purchase waits for approval. Your plan starts when it is approved.',
                PurchaseNoticeKind.info,
              ),
            );
          }
        case StoreTransactionState.canceled:
          if (mine) state = const ApplePurchaseState();
        case StoreTransactionState.failed:
          if (mine) {
            _fail(
              t.productId,
              t.errorMessage == null || t.errorMessage!.isEmpty
                  ? 'The App Store could not complete the purchase. Try again.'
                  : 'The App Store could not complete the purchase: ${t.errorMessage}',
            );
          }
        case StoreTransactionState.purchased:
        case StoreTransactionState.restored:
          if (t.state == StoreTransactionState.restored) _restoredSeen++;
          if (!t.hasTransaction) {
            if (mine) {
              _fail(
                t.productId,
                'The App Store could not complete the purchase. Try again.',
              );
            }
            continue;
          }
          _deliveries.add(_deliver(t, userVisible: mine || state.restoring));
      }
    }
  }

  Future<void> _deliver(StoreTransaction t, {required bool userVisible}) async {
    final String id = t.transactionId!;
    if (!_inFlight.add(id)) return;
    // Read before any await: a sign-out disposes this controller.
    final UptrackApi api = ref.read(uptrackApiProvider);
    final AppStoreClient? store = _store;
    try {
      final BillingSubscriptionInfo info = await api.postAppleTransaction(
        t.signedTransaction,
      );
      // Only now: the server has the subscription.
      await store?.finish(id);
      if (!ref.mounted) return;
      ref.invalidate(settingsBillingProvider);
      ref.invalidate(settingsProfileProvider);
      if (userVisible) {
        _notice(
          PurchaseNotice(
            t.state == StoreTransactionState.restored
                ? 'Purchases restored. Your plan is ${planLabel(info.plan)}.'
                : 'Thank you. Your plan is now ${planLabel(info.plan)}.',
            PurchaseNoticeKind.success,
          ),
          endPurchaseOf: t.productId,
        );
      }
    } on DioException catch (e) {
      if (userVisible) {
        _notice(
          PurchaseNotice(
            appleTransactionErrorMessage(e),
            PurchaseNoticeKind.error,
          ),
          endPurchaseOf: t.productId,
        );
      }
    } on Object {
      if (userVisible) {
        _notice(
          const PurchaseNotice(
            'Could not confirm the purchase. Tap Restore Purchases to try again.',
            PurchaseNoticeKind.error,
          ),
          endPurchaseOf: t.productId,
        );
      }
    } finally {
      _inFlight.remove(id);
      if (ref.mounted && state.busyProductId == t.productId) {
        state = ApplePurchaseState(notice: state.notice);
      }
    }
  }

  void _notice(PurchaseNotice notice, {required String endPurchaseOf}) {
    if (!ref.mounted) return;
    state = ApplePurchaseState(
      busyProductId: state.busyProductId == endPurchaseOf
          ? null
          : state.busyProductId,
      restoring: state.restoring,
      notice: notice,
    );
  }

  void _fail(String productId, String message) {
    _notice(
      PurchaseNotice(message, PurchaseNoticeKind.error),
      endPurchaseOf: productId,
    );
  }

  static String _storeError(PlatformException e) =>
      e.code == 'storekit_duplicate_product_object'
      ? 'An earlier purchase of this plan is not complete yet. Tap Restore Purchases, then try again.'
      : 'The App Store is not available right now. Try again later.';
}

/// User text for a failed `POST /api/billing/apple/transactions` (D7, D8).
String appleTransactionErrorMessage(DioException e) {
  final Object? data = e.response?.data;
  final Object? code = data is Map ? data['error_code'] : null;
  switch (code) {
    case 'not_owner':
      return 'Only the organization owner can buy or restore a plan.';
    case 'subscription_exists':
      return 'Your plan is managed on the web. This organization already has a subscription, so the App Store cannot add a second one.';
    case 'invalid_transaction':
      return 'Uptrack could not confirm this App Store purchase. Tap Restore Purchases to try again.';
  }
  switch (e.response?.statusCode) {
    case 404:
      return 'Purchases in the app are not available yet. Try again later.';
    case 401:
      return 'Your session expired. Sign in again, then tap Restore Purchases.';
  }
  return 'Could not reach Uptrack. Your purchase is safe: the app sends it again the next time it opens. You can also tap Restore Purchases.';
}

final NotifierProvider<ApplePurchaseController, ApplePurchaseState>
applePurchaseControllerProvider =
    NotifierProvider<ApplePurchaseController, ApplePurchaseState>(
      ApplePurchaseController.new,
    );
