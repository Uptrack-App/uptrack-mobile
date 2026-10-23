import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
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

/// The App Store on iOS when the build turns on [kAppleIapEnabled]; null on
/// Android, web and builds without the define, so they never register the
/// StoreKit plugin. Tests override it.
final Provider<AppStoreClient?> appStoreClientProvider =
    Provider<AppStoreClient?>(
      (Ref ref) => kAppleIapEnabled ? createPlatformAppStore() : null,
    );

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
  /// How long the app waits for StoreKit's transaction update after
  /// `Product.purchase()` or Restore Purchases answered.
  static const Duration kUpdateTimeout = Duration(seconds: 30);

  /// The wait that the controller uses. Tests make it short.
  @visibleForTesting
  static Duration updateTimeout = kUpdateTimeout;

  StreamSubscription<List<StoreTransaction>>? _updates;
  final Set<String> _inFlight = <String>{};

  /// Products whose transaction is with the server now.
  final List<String> _delivering = <String>[];
  List<Future<void>> _restoreDeliveries = <Future<void>>[];
  Completer<void>? _restoreBatch;
  int _restoredSeen = 0;
  Timer? _updateTimeout;

  /// A purchase whose StoreKit update did not come in time. Its late update
  /// still shows its result to the user.
  String? _lateProductId;

  AppStoreClient? get _store => ref.read(appStoreClientProvider);

  @override
  ApplePurchaseState build() {
    final AppStoreClient? store = ref.watch(appStoreClientProvider);
    if (store != null) {
      _updates = store.updates.listen(_onUpdates);
      ref.onDispose(() => _updates?.cancel());
    }
    ref.onDispose(() => _updateTimeout?.cancel());
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
      final StorePurchaseResult result = await store.buy(
        productId,
        appAccountToken: token,
      );
      if (!ref.mounted) return;
      // StoreKit also sends the outcome on the updates stream, before or
      // after `buy` returns. When that update came first, it already ended
      // the purchase.
      if (state.busyProductId != productId) return;
      switch (result) {
        case StorePurchaseResult.success:
        case StorePurchaseResult.unverified:
          // Stay busy: the transaction arrives on the updates stream, then
          // goes to the server. Stop waiting if it never arrives.
          _updateTimeout?.cancel();
          _updateTimeout = Timer(updateTimeout, () {
            if (ref.mounted &&
                state.busyProductId == productId &&
                !_delivering.contains(productId)) {
              _lateProductId = productId;
              _notice(
                const PurchaseNotice(
                  'The App Store has not confirmed the purchase yet. Your plan changes when it does. If it does not change, tap Restore Purchases.',
                  PurchaseNoticeKind.info,
                ),
                endPurchaseOf: productId,
              );
            }
          });
        case StorePurchaseResult.pending:
          state = const ApplePurchaseState(notice: _pendingNotice);
        case StorePurchaseResult.userCancelled:
          state = ApplePurchaseState(notice: state.notice);
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
    } on Object {
      if (!ref.mounted) return;
      _fail(productId, 'Could not start the purchase. Try again later.');
    }
  }

  static const PurchaseNotice _pendingNotice = PurchaseNotice(
    'The purchase waits for approval. Your plan starts when it is approved.',
    PurchaseNoticeKind.info,
  );

  /// Restore Purchases: StoreKit sends the current entitlements, and each one
  /// goes to the server (the same call as a purchase).
  Future<void> restore() async {
    final AppStoreClient? store = _store;
    if (store == null || state.busy) return;
    state = const ApplePurchaseState(restoring: true);
    _restoredSeen = 0;
    _restoreDeliveries = <Future<void>>[];
    final Completer<void> batch = _restoreBatch = Completer<void>();
    try {
      await store.restore();
      // StoreKit sends the entitlements in one batch (also an empty one),
      // before or after `restore` returns.
      bool answered = true;
      await batch.future.timeout(
        updateTimeout,
        onTimeout: () => answered = false,
      );
      await Future.wait(List<Future<void>>.of(_restoreDeliveries));
      if (!ref.mounted) return;
      if (_restoredSeen == 0) {
        state = ApplePurchaseState(
          notice: answered
              ? const PurchaseNotice(
                  'No App Store subscription to restore for this Apple ID.',
                  PurchaseNoticeKind.info,
                )
              : const PurchaseNotice(
                  'The App Store did not answer. Tap Restore Purchases again later.',
                  PurchaseNoticeKind.error,
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
    } on Object {
      // Never stay in the restoring state.
      if (!ref.mounted) return;
      state = const ApplePurchaseState(
        notice: PurchaseNotice(
          'The App Store is not available right now. Try again later.',
          PurchaseNoticeKind.error,
        ),
      );
    } finally {
      if (identical(_restoreBatch, batch)) _restoreBatch = null;
    }
  }

  void _onUpdates(List<StoreTransaction> updates) {
    for (final StoreTransaction t in updates) {
      final bool mine = state.busyProductId == t.productId;
      switch (t.state) {
        case StoreTransactionState.pending:
          if (mine) state = const ApplePurchaseState(notice: _pendingNotice);
        case StoreTransactionState.canceled:
          if (mine) state = ApplePurchaseState(notice: state.notice);
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
          final bool restoring = state.restoring;
          final bool late = _lateProductId == t.productId;
          if (late) _lateProductId = null;
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
          final Future<void> delivery = _deliver(
            t,
            userVisible: mine || restoring || late,
          );
          if (restoring) _restoreDeliveries.add(delivery);
      }
    }
    final Completer<void>? batch = _restoreBatch;
    if (batch != null &&
        !batch.isCompleted &&
        (updates.isEmpty ||
            updates.any(
              (StoreTransaction t) => t.state == StoreTransactionState.restored,
            ))) {
      batch.complete();
    }
  }

  Future<void> _deliver(StoreTransaction t, {required bool userVisible}) async {
    final String id = t.transactionId!;
    if (!_inFlight.add(id)) return;
    _delivering.add(t.productId);
    final UptrackApi api = ref.read(uptrackApiProvider);
    final AppStoreClient? store = _store;
    try {
      // The controller outlives a sign-out, and the API sends the token of
      // the account that is signed in now. Send a transaction only to its
      // own organization; the server would refuse it anyway (422).
      final CurrentUserResponse me = await api.getMe();
      if (t.appAccountToken?.toLowerCase() !=
          me.organization.id.toLowerCase()) {
        // An expired one grants nothing any more, and the server has its
        // state from Apple's notifications. Finish it: left unfinished, it
        // blocks every new purchase of this product on this device (the
        // plugin refuses a product with an unfinished transaction).
        final DateTime? expiresAt = t.expiresAt;
        if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
          await store?.finish(id);
        }
        if (userVisible) {
          _notice(
            const PurchaseNotice(
              'This App Store subscription belongs to another Uptrack organization. Sign in to that organization to use it.',
              PurchaseNoticeKind.error,
            ),
            endPurchaseOf: t.productId,
          );
        }
        return;
      }
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
      _delivering.remove(t.productId);
      if (ref.mounted && state.busyProductId == t.productId) {
        _updateTimeout?.cancel();
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

const String _invalidTransaction =
    'Uptrack could not confirm this App Store purchase. Tap Restore Purchases to try again.';

/// User text for a failed `POST /api/billing/apple/transactions` (D7, D8).
String appleTransactionErrorMessage(DioException e) {
  final Object? data = e.response?.data;
  final Object? code = data is Map ? data['error_code'] : null;
  switch (code) {
    case 'not_owner':
      return 'Only the organization owner can buy or restore a plan.';
    case 'subscription_exists':
      // D7: the App Store subscription of this Apple ID stays live and
      // renews, but it gives no plan. Tell the user how to stop it.
      final Object? provider = data is Map ? data['provider'] : null;
      if (provider == 'apple') {
        return 'This organization already has an App Store subscription from another Apple ID. To stop paying twice, cancel the subscription of this Apple ID: open the Settings app, tap your name, then tap Subscriptions.';
      }
      return 'Your plan is managed on the web. This organization already has a subscription, so the App Store cannot add a second one. To stop paying twice, cancel the App Store subscription: open the Settings app, tap your name, then tap Subscriptions.';
    case 'sandbox_not_allowed':
      // A Sandbox (TestFlight or test) purchase for an organization that
      // is not on the server's sandbox list. Like every 422, the
      // transaction stays unfinished.
      return 'Test purchases are not enabled for this account.';
    case 'invalid_transaction':
      return _invalidTransaction;
  }
  switch (e.response?.statusCode) {
    case 422:
      return _invalidTransaction;
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
