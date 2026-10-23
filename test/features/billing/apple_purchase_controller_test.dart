import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/billing/app_store.dart';
import 'package:uptrack_mobile/features/billing/apple_purchase_controller.dart';

import '../auth/auth_test.dart' show FakeAdapter, jsonResponse, meFixture;
import 'fake_app_store.dart';

const String _orgId = '2C9F7B1E-4D3A-4F2B-9E8D-7A6B5C4D3E2F';
const String _proMonthly = 'app.uptrack.mobile.pro.monthly';
const String _teamMonthly = 'app.uptrack.mobile.team.monthly';

Map<String, Object?> _me({String role = 'owner', String orgId = _orgId}) {
  final Map<String, Object?> me = meFixture();
  (me['user']! as Map<String, Object?>)['role'] = role;
  (me['organization']! as Map<String, Object?>)['id'] = orgId;
  return me;
}

Map<String, Object?> _subscriptionBody(String plan, String productId) =>
    <String, Object?>{
      'plan': plan,
      'data': <String, Object?>{
        'id': 's1',
        'plan': plan,
        'status': 'active',
        'provider': 'apple',
        'apple_product_id': productId,
      },
    };

class _Harness {
  _Harness({
    required this.store,
    this.role = 'owner',
    this.transactionStatus = 200,
    this.transactionBody,
  }) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:4000'));
    dio.httpClientAdapter = FakeAdapter((RequestOptions o) async {
      if (o.path == kGetMePath) return jsonResponse(_me(role: role));
      if (o.path == kAppleTransactionsPath) {
        if (gate != null) await gate!.future;
        posted.add(
          (o.data as Map<dynamic, dynamic>)['signed_transaction'] as String,
        );
        if (transactionStatus == -1) {
          throw DioException.connectionError(
            requestOptions: o,
            reason: 'offline',
          );
        }
        return jsonResponse(
          transactionBody ?? _subscriptionBody('pro', _proMonthly),
          transactionStatus,
        );
      }
      return jsonResponse(<String, Object?>{'plan': 'free', 'data': null});
    });
    container = ProviderContainer(
      overrides: [
        appStoreClientProvider.overrideWithValue(store),
        uptrackApiProvider.overrideWithValue(UptrackApi(dio: dio)),
      ],
    );
  }

  final FakeAppStore store;
  final String role;
  int transactionStatus;
  Completer<void>? gate;
  Map<String, Object?>? transactionBody;
  final List<String> posted = <String>[];
  late final ProviderContainer container;

  ApplePurchaseController get controller =>
      container.read(applePurchaseControllerProvider.notifier);
  ApplePurchaseState get state =>
      container.read(applePurchaseControllerProvider);

  Future<void> settle() async {
    for (int i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

void main() {
  test(
    'purchase: token = lowercase org ID, JWS to server, then finish',
    () async {
      final FakeAppStore store = FakeAppStore();
      final _Harness h = _Harness(store: store);
      addTearDown(h.container.dispose);
      h.controller; // start listening
      await h.settle();

      await h.controller.buy(_proMonthly);
      await h.settle();

      expect(store.buys.single.productId, _proMonthly);
      expect(store.buys.single.appAccountToken, _orgId.toLowerCase());
      expect(h.posted, <String>['jws.tx-$_proMonthly']);
      expect(store.finished, <String>['tx-$_proMonthly']);
      expect(h.state.busy, isFalse);
      expect(h.state.notice?.kind, PurchaseNoticeKind.success);
      expect(h.state.notice?.message, 'Thank you. Your plan is now Pro.');
    },
  );

  for (final ({int status, Map<String, Object?> body, String text}) c
      in <({int status, Map<String, Object?> body, String text})>[
        (
          status: 409,
          body: <String, Object?>{
            'error_code': 'subscription_exists',
            'provider': 'paddle',
          },
          text: 'Your plan is managed on the web.',
        ),
        (
          status: 409,
          body: <String, Object?>{
            'error_code': 'subscription_exists',
            'provider': 'apple',
          },
          text: 'already has an App Store subscription',
        ),
        (
          status: 422,
          body: <String, Object?>{'error_code': 'sandbox_not_allowed'},
          text: 'Test purchases are not enabled for this account.',
        ),
        (
          status: 422,
          body: <String, Object?>{'error_code': 'invalid_transaction'},
          text: 'could not confirm this App Store purchase',
        ),
        (
          status: 403,
          body: <String, Object?>{'error_code': 'not_owner'},
          text: 'Only the organization owner',
        ),
        (status: 404, body: <String, Object?>{}, text: 'not available yet'),
        (status: 500, body: <String, Object?>{}, text: 'Your purchase is safe'),
        (status: -1, body: <String, Object?>{}, text: 'Your purchase is safe'),
      ]) {
    test('server ${c.status}: the transaction stays unfinished', () async {
      final FakeAppStore store = FakeAppStore();
      final _Harness h = _Harness(
        store: store,
        transactionStatus: c.status,
        transactionBody: c.body,
      );
      addTearDown(h.container.dispose);
      h.controller;
      await h.settle();

      await h.controller.buy(_proMonthly);
      await h.settle();

      expect(h.posted, hasLength(1));
      expect(store.finished, isEmpty);
      expect(h.state.busy, isFalse);
      expect(h.state.notice?.kind, PurchaseNoticeKind.error);
      expect(h.state.notice?.message, contains(c.text));
    });
  }

  test('a member cannot buy (D8): no App Store sheet', () async {
    final FakeAppStore store = FakeAppStore();
    final _Harness h = _Harness(store: store, role: 'member');
    addTearDown(h.container.dispose);
    await h.controller.buy(_proMonthly);
    await h.settle();
    expect(store.buys, isEmpty);
    expect(
      h.state.notice?.message,
      'Only the organization owner can buy a plan.',
    );
  });

  test('pending (Ask to Buy): no server call, an approval message', () async {
    final FakeAppStore store = FakeAppStore(
      onBuy: (String id) =>
          StoreTransaction(productId: id, state: StoreTransactionState.pending),
    );
    final _Harness h = _Harness(store: store);
    addTearDown(h.container.dispose);
    h.controller;
    await h.settle();
    await h.controller.buy(_proMonthly);
    await h.settle();
    expect(h.posted, isEmpty);
    expect(h.state.busy, isFalse);
    expect(h.state.notice?.message, contains('waits for approval'));

    // The approval arrives later on Transaction.updates.
    store.emit(<StoreTransaction>[purchased(_proMonthly, 'tx-approved')]);
    await h.settle();
    expect(h.posted, <String>['jws.tx-approved']);
    expect(store.finished, <String>['tx-approved']);
  });

  test('cancel: no server call and no message', () async {
    final FakeAppStore store = FakeAppStore(
      onBuy: (String id) => StoreTransaction(
        productId: id,
        state: StoreTransactionState.canceled,
      ),
    );
    final _Harness h = _Harness(store: store);
    addTearDown(h.container.dispose);
    h.controller;
    await h.settle();
    await h.controller.buy(_proMonthly);
    await h.settle();
    expect(h.posted, isEmpty);
    expect(h.state.busy, isFalse);
    expect(h.state.notice, isNull);
  });

  test('a store error ends the purchase with a message', () async {
    final FakeAppStore store = FakeAppStore()
      ..buyError = PlatformException(code: 'storekit2_failed_to_fetch_product');
    final _Harness h = _Harness(store: store);
    addTearDown(h.container.dispose);
    await h.controller.buy(_proMonthly);
    await h.settle();
    expect(h.state.busy, isFalse);
    expect(h.state.notice?.kind, PurchaseNoticeKind.error);
  });

  test(
    'restart: unfinished transactions go to the server, then finish',
    () async {
      final FakeAppStore store = FakeAppStore(
        leftovers: <StoreTransaction>[purchased(_teamMonthly, 'tx-old')],
      );
      final _Harness h = _Harness(
        store: store,
        transactionBody: _subscriptionBody('team', _teamMonthly),
      );
      addTearDown(h.container.dispose);
      await h.controller.finishLeftovers();
      await h.settle();
      expect(h.posted, <String>['jws.tx-old']);
      expect(store.finished, <String>['tx-old']);
      // Silent: there was no user action.
      expect(h.state.notice, isNull);
    },
  );

  test(
    'restart: a failed leftover stays unfinished for the next launch',
    () async {
      final FakeAppStore store = FakeAppStore(
        leftovers: <StoreTransaction>[purchased(_teamMonthly, 'tx-old')],
      );
      final _Harness h = _Harness(store: store, transactionStatus: 503);
      addTearDown(h.container.dispose);
      await h.controller.finishLeftovers();
      await h.settle();
      expect(h.posted, <String>['jws.tx-old']);
      expect(store.finished, isEmpty);
    },
  );

  test('the same transaction twice is sent once while in flight', () async {
    final FakeAppStore store = FakeAppStore(
      leftovers: <StoreTransaction>[purchased(_proMonthly, 'tx-1')],
    );
    final _Harness h = _Harness(store: store);
    addTearDown(h.container.dispose);
    final Future<void> leftovers = h.controller.finishLeftovers();
    // Transaction.updates also gives the unfinished one at launch.
    store.emit(<StoreTransaction>[purchased(_proMonthly, 'tx-1')]);
    await leftovers;
    await h.settle();
    expect(h.posted, hasLength(1));
  });

  test('restore: each entitlement goes to the server, then finish', () async {
    final FakeAppStore store = FakeAppStore(
      restored: <StoreTransaction>[restoredTx(_teamMonthly, 'tx-r')],
    );
    final _Harness h = _Harness(
      store: store,
      transactionBody: _subscriptionBody('team', _teamMonthly),
    );
    addTearDown(h.container.dispose);
    h.controller;
    await h.settle();
    await h.controller.restore();
    await h.settle();
    expect(store.restores, 1);
    expect(h.posted, <String>['jws.tx-r']);
    expect(store.finished, <String>['tx-r']);
    expect(h.state.restoring, isFalse);
    expect(h.state.notice?.message, 'Purchases restored. Your plan is Team.');
  });

  test('restore with nothing to restore says so', () async {
    final FakeAppStore store = FakeAppStore();
    final _Harness h = _Harness(store: store);
    addTearDown(h.container.dispose);
    h.controller;
    await h.settle();
    await h.controller.restore();
    expect(h.posted, isEmpty);
    expect(h.state.notice?.message, contains('No App Store subscription'));
  });

  test(
    'upgrade: buying another product of the group is a normal purchase',
    () async {
      final FakeAppStore store = FakeAppStore();
      final _Harness h = _Harness(
        store: store,
        transactionBody: _subscriptionBody('team', _teamMonthly),
      );
      addTearDown(h.container.dispose);
      h.controller;
      await h.settle();
      await h.controller.buy(_teamMonthly);
      await h.settle();
      expect(store.buys.single.productId, _teamMonthly);
      expect(store.finished, <String>['tx-$_teamMonthly']);
      expect(h.state.notice?.message, 'Thank you. Your plan is now Team.');
    },
  );

  test('no App Store (Android): IAP is off and nothing runs', () {
    final ProviderContainer c = ProviderContainer(
      overrides: [appStoreClientProvider.overrideWithValue(null)],
    );
    addTearDown(c.dispose);
    expect(c.read(appleIapEnabledProvider), isFalse);
    expect(c.read(applePurchaseControllerProvider).busy, isFalse);
  });

  test('the define is off by default', () {
    final ProviderContainer c = ProviderContainer(
      overrides: [appStoreClientProvider.overrideWithValue(FakeAppStore())],
    );
    addTearDown(c.dispose);
    expect(c.read(appleIapEnabledProvider), isFalse);
  });

  test('a second sign-in sends a still unfinished transaction again', () async {
    final FakeAppStore store = FakeAppStore(
      leftovers: <StoreTransaction>[purchased(_proMonthly, 'tx-1')],
    );
    final _Harness h = _Harness(store: store, transactionStatus: 503);
    addTearDown(h.container.dispose);
    await h.controller.finishLeftovers();
    expect(store.finished, isEmpty);
    h.transactionStatus = 200;
    await h.controller.finishLeftovers();
    expect(h.posted, <String>['jws.tx-1', 'jws.tx-1']);
    expect(store.finished, <String>['tx-1']);
  });

  group('the StoreKit update arrives after buy/restore return', () {
    Future<void> late() =>
        Future<void>.delayed(const Duration(milliseconds: 60));

    test('purchase: busy until the server answers, then thanks', () async {
      final FakeAppStore store = FakeAppStore()..lateUpdates = true;
      final _Harness h = _Harness(store: store);
      addTearDown(h.container.dispose);
      h.controller;
      await h.settle();

      await h.controller.buy(_proMonthly);
      await h.settle();
      // StoreKit has not sent the transaction yet: still busy.
      expect(h.state.busyProductId, _proMonthly);

      await late();
      expect(store.finished, <String>['tx-$_proMonthly']);
      expect(h.state.busy, isFalse);
      expect(h.state.notice?.message, 'Thank you. Your plan is now Pro.');
    });

    test('purchase: a 409 after the charge is shown to the user', () async {
      final FakeAppStore store = FakeAppStore()..lateUpdates = true;
      final _Harness h = _Harness(
        store: store,
        transactionStatus: 409,
        transactionBody: <String, Object?>{
          'error_code': 'subscription_exists',
          'provider': 'paddle',
        },
      );
      addTearDown(h.container.dispose);
      h.controller;
      await h.settle();
      await h.controller.buy(_proMonthly);
      await late();
      expect(store.finished, isEmpty);
      expect(h.state.busy, isFalse);
      expect(h.state.notice?.kind, PurchaseNoticeKind.error);
    });

    test('restore: the late entitlement is restored, with a message', () async {
      final FakeAppStore store = FakeAppStore(
        restored: <StoreTransaction>[restoredTx(_teamMonthly, 'tx-r')],
      )..lateUpdates = true;
      final _Harness h = _Harness(
        store: store,
        transactionBody: _subscriptionBody('team', _teamMonthly),
      );
      addTearDown(h.container.dispose);
      h.controller;
      await h.settle();
      await h.controller.restore();
      expect(h.posted, <String>['jws.tx-r']);
      expect(store.finished, <String>['tx-r']);
      expect(h.state.restoring, isFalse);
      expect(h.state.notice?.message, 'Purchases restored. Your plan is Team.');
    });

    test('restore: nothing to restore, after the empty batch', () async {
      final FakeAppStore store = FakeAppStore()..lateUpdates = true;
      final _Harness h = _Harness(store: store);
      addTearDown(h.container.dispose);
      h.controller;
      await h.settle();
      await h.controller.restore();
      expect(h.state.restoring, isFalse);
      expect(h.state.notice?.message, contains('No App Store subscription'));
    });
  });
}
