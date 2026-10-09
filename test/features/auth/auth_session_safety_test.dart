import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/data/local/database_providers.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/auth/token_storage.dart';
import 'package:uptrack_mobile/features/incidents/incidents_controller.dart';

/// Fake adapter that answers the sign-in/revocation endpoints immediately and
/// parks every other request until the test releases it, so sign-out can be
/// observed while a pre-logout request is still in flight.
class _SessionAdapter implements HttpClientAdapter {
  final Map<String, Completer<ResponseBody>> _pending =
      <String, Completer<ResponseBody>>{};

  final List<String> seen = <String>[];

  static ResponseBody _body(
    Object? json,
    int status, {
    bool sessionCookie = false,
  }) => ResponseBody.fromString(
    jsonEncode(json),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['application/json'],
      if (sessionCookie)
        'set-cookie': <String>['_uptrack_key=abc123; Path=/; HttpOnly'],
    },
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final String key = '${options.method} ${options.path}';
    seen.add(key);
    switch (key) {
      case 'POST $kLoginPath':
        return Future<ResponseBody>.value(
          _body(meFixture(), 200, sessionCookie: true),
        );
      case 'POST $kDeviceTokensPath':
        return Future<ResponseBody>.value(_body(issuanceFixture(), 201));
      case 'DELETE $kDeviceTokensPath/$kIssuedDeviceTokenId':
      case 'DELETE $kPushDevicesPath':
      case 'POST $kLogoutPath':
        return Future<ResponseBody>.value(
          _body(<String, Object?>{'ok': true}, 200),
        );
    }
    final Completer<ResponseBody> completer = Completer<ResponseBody>();
    _pending[key] = completer;
    return completer.future;
  }

  /// Completes the pending `METHOD path` request with [body].
  Future<void> release(String method, String path, Object? body) async {
    final String key = '$method $path';
    // Dio reaches the adapter asynchronously, so the gate may not exist yet.
    for (
      int attempt = 0;
      attempt < 100 && !_pending.containsKey(key);
      attempt++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    final Completer<ResponseBody>? gate = _pending[key];
    if (gate == null) {
      throw StateError('no pending $key');
    }
    _pending.remove(key);
    gate.complete(_body(body, 200));
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> meFixture() => <String, Object?>{
  'user': <String, Object?>{
    'id': '11111111-1111-4111-8111-111111111111',
    'name': 'Ada',
    'email': 'ada@example.com',
    'provider': null,
    'role': 'owner',
    'is_admin': false,
    'preferred_locale': null,
    'inserted_at': '2026-01-01T00:00:00Z',
  },
  'organization': <String, Object?>{
    'id': '22222222-2222-4222-8222-222222222222',
    'name': 'Acme',
    'slug': 'acme',
    'plan': 'free',
  },
};

const String kIssuedDeviceTokenId = '44444444-4444-4444-8444-444444444444';

Map<String, Object?> issuanceFixture() => <String, Object?>{
  'id': kIssuedDeviceTokenId,
  'label': null,
  'token': 'udt_test_raw_token',
  'created_at': '2026-01-01T00:00:00',
};

Map<String, Object?> incidentFixture(String id) => <String, Object?>{
  'id': id,
  'monitor_id': 'm1',
  'monitor_name': 'Homepage',
  'status': 'ongoing',
  'inserted_at': '2026-09-27T10:00:00Z',
  'started_at': '2026-09-27T10:00:00Z',
  'acknowledged_at': null,
  'resolved_at': null,
};

IncidentSnapshot oldSessionSnapshot(String id) => IncidentSnapshot(
  id: id,
  monitorId: 'm1',
  monitorName: 'Homepage',
  status: 'ongoing',
  insertedAt: '2026-09-27T10:00:00Z',
);

void main() {
  // Sign-out clears the session's push notifications over a platform channel,
  // which needs a live binary messenger even in these unit tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MemoryTokenStore store;
  late AuthTokenHolder holder;
  late _SessionAdapter adapter;

  /// Held open by the widget wipe so sign-out can be inspected mid-flight;
  /// completed by the test to let sign-out finish.
  late Completer<void> widgetGate;

  /// Completed once the widget wipe has been entered.
  late Completer<void> widgetClearEntered;

  /// When true the widget wipe throws instead of being parked.
  late bool widgetClearFails;

  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = MemoryTokenStore();
    holder = AuthTokenHolder();
    adapter = _SessionAdapter();
    widgetGate = Completer<void>();
    widgetClearEntered = Completer<void>();
    widgetClearFails = false;
    container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(store),
        authTokenHolderProvider.overrideWithValue(holder),
        dioProvider.overrideWithValue(
          buildAppDio(holder: holder, onUnauthorized: () {}, adapter: adapter),
        ),
        appDatabaseProvider.overrideWithValue(db),
        // Gates the R2.4 widget wipe so sign-out can be observed while it is
        // blocked, after the session epoch has already advanced.
        clearWidgetDataProvider.overrideWithValue(() {
          widgetClearEntered.complete();
          if (widgetClearFails) {
            return Future<void>.error(StateError('widget channel unavailable'));
          }
          return widgetGate.future;
        }),
      ],
    );
    addTearDown(() {
      container.dispose();
      db.close();
    });
  });

  /// Signs in so sign-out has a device token to revoke and a session to end.
  Future<void> signIn() async {
    await container
        .read(authControllerProvider.notifier)
        .signInWithPassword(email: 'ada@example.com', password: 'secret');
    expect(container.read(authControllerProvider).status, AuthStatus.signedIn);
  }

  group('sign-out ordering', () {
    test('the session epoch advances before signed-out is published', () async {
      await signIn();
      final CacheRepository cache = container.read(cacheRepositoryProvider);
      await cache.saveIncidents(
        <IncidentSnapshot>[oldSessionSnapshot('i-old-session')],
        session: cache.sessionEpoch,
        revision: cache.incidentRevision,
      );
      final int epochBeforeLogout = cache.sessionEpoch;

      // A feed load is in flight under the pre-logout epoch. Waiting for
      // the request to reach the adapter matters: a load started *after* the
      // epoch advanced would be a legitimate next-session request.
      final ApiIncidentsRepository feed = ApiIncidentsRepository(
        api: container.read(uptrackApiProvider),
        cache: cache,
      );
      final Future<IncidentsData> load = feed.load();
      await _waitForRequest(adapter, 'GET $kIncidentsPath');

      final Future<void> logout = container
          .read(authControllerProvider.notifier)
          .signOut(pushToken: 'fcm-token-1');
      await widgetClearEntered.future;

      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedOut,
        reason: 'signed-out is published while the widget wipe is blocked',
      );
      expect(
        cache.sessionEpoch,
        epochBeforeLogout + 1,
        reason:
            'the epoch must already be advanced once signed-out is'
            ' visible, so a new sign-in cannot run under the old session',
      );

      // The pre-logout response lands while sign-out is still blocked: it
      // must neither reach the screen nor be written to disk.
      await adapter.release('GET', kIncidentsPath, <String, Object?>{
        'data': <Object?>[incidentFixture('i-late')],
      });
      await expectLater(load, throwsA(isA<SessionEndedException>()));
      expect(
        (await cache.getIncidents()).data.map((CachedIncident row) => row.id),
        isNot(contains('i-late')),
        reason:
            'a pre-logout response must not be persisted or returned'
            ' once signed-out is visible',
      );

      widgetGate.complete();
      await logout;

      expect(
        (await cache.getIncidents()).data,
        isEmpty,
        reason: 'the cache wipe still completes once the widget wipe returns',
      );
      expect(await store.readDeviceToken(), isNull);
    });

    test('a failing widget clear does not skip the cache cleanup', () async {
      widgetClearFails = true;
      await signIn();
      final CacheRepository cache = container.read(cacheRepositoryProvider);
      await cache.saveIncidents(
        <IncidentSnapshot>[oldSessionSnapshot('i-old-session')],
        session: cache.sessionEpoch,
        revision: cache.incidentRevision,
      );

      await container.read(authControllerProvider.notifier).signOut();

      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedOut,
      );
      expect(
        (await cache.getIncidents()).data,
        isEmpty,
        reason: 'the cache wipe must run even when the widget wipe throws',
      );
      expect(await store.readDeviceToken(), isNull);
    });
  });
}

/// Waits until [adapter] has actually received `METHOD path`.
Future<void> _waitForRequest(_SessionAdapter adapter, String key) async {
  for (
    int attempt = 0;
    attempt < 100 && !adapter.seen.contains(key);
    attempt++
  ) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(adapter.seen, contains(key), reason: '$key never reached the adapter');
}
