/// Device acceptance fixture for the bounded offline incident context (R4).
///
/// One entry point for the native run. What it pumps is the real
/// [IncidentDetailScreen] under the real [AppTheme], reading through the real
/// `ApiIncidentDetailRepository` and `CacheRepository` over a **real
/// file-backed** SQLite database, served by a strictly allowlisted local
/// transport. Nothing about the screen, the theme, the repositories or the
/// persistence is stood in for.
///
/// What the fixture deliberately provides, and what it refuses to:
///
/// * a fake local [HttpClientAdapter] whose allowlist is exactly the two reads
///   these cases need (`GET /api/incidents` and `GET /api/incidents/{id}`);
///   every other request — a mutation, an auth call, a push registration, any
///   other path — is **counted and refused**, so "this run never reached the
///   network, a mailer, an OAuth provider or FCM" is something the log proves
///   rather than something the fixture promises. The Dio instance also points
///   its base URL at the reserved `.invalid` TLD, so even a bypassed adapter
///   could not resolve a host;
/// * the minimal shell the screen needs — a [ProviderScope] whose overrides are
///   read back from the container that actually serves the rendered tree, plus
///   a [MaterialApp]. The app's router, login, demo session and push service are
///   never built at all, so there is no container a push service could be
///   injected into and no code path that could register an FCM token.
///
/// The three cases are the ones that cannot be proven by a storage-level test or
/// by an in-memory database:
///
/// 1. a detail read is saved, the app is closed (widget tree unmounted, database
///    handle closed), the **same file** is reopened with a **new** repository and
///    container, the GET now fails with a transport error — and the screen still
///    shows the saved update with its real sync time, says it is offline, and
///    offers no response action. Stored timestamps are compared before and after
///    the fallback, exactly, not through rounded display copy;
/// 2. a newer list read resolves the incident without any detail fetch; on
///    reopen the resolved summary appears **with** the older saved updates and
///   their older detail sync time, and the summary freshness is the newer stored
///   value — the new repository's memory cannot resurrect Open;
/// 3. a missing detail snapshot and a successfully saved *empty* updates list
///    stay two different sentences, built from two real incident ids rather than
///    from a fabricated `IncidentDetailData`.
///
/// Viewport: a real phone. Brightness and text scale are set on the platform
/// dispatcher, which is what `MediaQuery` reads; the viewport is a real phone
/// and is never grown to dodge a scroll — sections below the fold are reached by
/// dragging with test finders, because "reachable on a phone" is the claim.
/// A host run is given the phone this evidence is about; a device run keeps the
/// surface the OS reports (physical size, device pixel ratio, insets), asserted
/// rather than assumed.
///
/// Two modes, exactly as in the reviewed R2 fixture:
/// * host (`flutter test`): every assertion runs; the capture is skipped for
///   exactly one known reason — the integration binding's screenshot channel has
///   no host implementation and reports a `MissingPluginException`;
/// * device (`flutter test integration_test/offline_incident_device_test.dart
///   -d emulator-5554 --no-enable-impeller --no-uninstall`): the same
///   assertions, then PNGs are written under the app's own cache and the host
///   pulls them with
///   `adb exec-out run-as app.uptrack.mobile cat
///   code_cache/uptrack_r4_offline_screenshots/NAME.png`. Nothing about the
///   capture is best-effort there: a failed conversion, capture or write fails
///   the run.
///
/// `code_cache`, not `cache`, because the fixture writes under
/// [Directory.systemTemp], which on Android is the app's *code* cache
/// (`/data/user/0/app.uptrack.mobile/code_cache`) — see the `SCREENSHOT_SAVED`
/// lines in the reviewed R2 device log. Each capture prints that line with the
/// absolute path it actually wrote, and that line is the authoritative path for
/// the host to pull; the path documented above is the expected spelling of it.
///
/// What a passing run does *not* claim: service availability, delivery, a demo,
/// a live backend, a physical device, or R5 widget work.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Tristate;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/data/local/app_database.dart';
import 'package:uptrack_mobile/data/local/cache_repository.dart';
import 'package:uptrack_mobile/data/local/database_providers.dart';
import 'package:uptrack_mobile/design/components.dart' show UptrackButton;
import 'package:uptrack_mobile/features/auth/auth_controller.dart'
    show uptrackApiProvider;
import 'package:uptrack_mobile/features/incidents/incident_detail_screen.dart';
import 'package:uptrack_mobile/features/incidents/incidents_controller.dart';
import 'package:uptrack_mobile/theme/app_theme.dart';
import 'package:uptrack_mobile/util/date_format.dart';

// -- the fixture's own subject ------------------------------------------------

/// The incident whose detail read is saved and reopened offline, and the
/// monitor name the screen shows and its incident-specific labels quote.
const String kIncidentId = 'i-offline-detail';
const String kMonitorName = 'Checkout service';

/// A recognizable saved update: if the reopened screen ever lost it, the row
/// below would be missing rather than merely empty.
const String kUpdateTitle = 'Investigating elevated checkout errors';
const String kUpdateDescription =
    'Payment provider latency, still tracing the 5xx spike.';

/// The status label the screen renders for the update's `investigating` status
/// (`statusLabel` in `status_colors.dart`), i.e. what a reader is shown.
const String kUpdateStatus = 'Investigating';

/// The incident a *successful* read genuinely returned no updates for, and the
/// one that only ever appeared in a list read (so it has a cached summary row
/// and no detail snapshot at all).
const String kSavedEmptyId = 'i-saved-empty';
const String kSummaryOnlyId = 'i-summary-only';
const String kOtherMonitorName = 'Marketing website';

/// Copy the screen must show, quoted from `incident_detail_screen.dart` and
/// `incident_response.dart` rather than restated from the design review.
const String kOfflineNotice = 'Offline — showing cached data';
const String kNoUpdatesSaved = 'No updates yet.';
const String kNoSavedUpdates = 'No saved updates for offline viewing.';
const String kOfflineResponseReason = 'Response actions need a connection.';
const String kUpdatesStampPrefix = 'Updates last synced';
const String kSummaryStampPrefix = 'Last synced';

/// Incident-specific labels the three response controls announce, from the
/// screen's own `semanticLabel`s. The label sits on the actionable node, so
/// these are what a screen reader announces while the control is disabled.
const String kAcknowledgeLabel = 'Acknowledge incident $kMonitorName';
const String kEscalateLabel = 'Escalate incident $kMonitorName';
const String kSnoozeLabel =
    'Snooze your mobile alerts for 1 hour on $kMonitorName';

/// The real phone viewport used for the host run: the size of the device this
/// acceptance evidence is about. A device run keeps its own surface.
const Size kPhoneViewport = Size(390, 844);

/// True only on the Android device this run targets.
///
/// Read from the real runtime, not [defaultTargetPlatform]: a Flutter host test
/// reports Android as its target platform, so `defaultTargetPlatform` would make
/// this host run claim it had a screenshot channel and turn the one legitimate
/// skip into a failure. On Android nothing about the capture is skipped.
final bool kRunningOnAndroid = Platform.isAndroid;

/// How long a pump-and-settle may take before the run calls it a stall.
///
/// Bounded on purpose: an unbounded settle turns a widget that never stops
/// animating into a run that ends as "did not complete", which says nothing
/// about what was on screen.
const Duration _settleTimeout = Duration(seconds: 30);

/// How long each capture stage may take before the run calls it a failure.
const Duration _captureStageTimeout = Duration(seconds: 60);

/// The only two reads these cases need. Everything else is refused.
const String _listPath = kIncidentsPath;

/// Directory the device run writes its PNGs into, under the app's own cache.
///
/// [Directory.systemTemp] is the app's cache directory on Android — the *code*
/// cache, `/data/user/0/app.uptrack.mobile/code_cache` — so the host can pull
/// the captures with
/// `adb exec-out run-as app.uptrack.mobile cat
/// code_cache/uptrack_r4_offline_screenshots/NAME.png` after the suite exits.
/// The `SCREENSHOT_SAVED` line reports the absolute path that run really used.
const String _captureDirName = 'uptrack_r4_offline_screenshots';

// -- the fake local transport -------------------------------------------------

/// A strictly allowlisted local transport.
///
/// There is no network behind it. A request is answered only if it was
/// explicitly allowlisted *and* scripted; every other request is refused with a
/// transport error and recorded, so a regression that reaches for an endpoint
/// this fixture never opened fails the run instead of quietly hitting a real
/// host. Requests are recorded whether they are answered, failed or refused,
/// because "what did the app ask for while offline" is the interesting question.
class FakeTransport implements HttpClientAdapter {
  /// `METHOD path` → the JSON body it answers with.
  final Map<String, Object?> _scripted = <String, Object?>{};

  /// Allowlisted keys that answer with a transport failure instead: the
  /// "the device lost its connection" condition, as opposed to an HTTP status.
  final Set<String> _failing = <String>{};

  /// Every request the app made, in order.
  final List<String> requests = <String>[];

  /// Allowlisted requests that were answered.
  final List<String> answered = <String>[];

  /// Allowlisted requests that were answered with a transport failure.
  final List<String> transportFailures = <String>[];

  /// Requests refused for not being allowlisted.
  final List<String> refused = <String>[];

  /// Requests refused for being mutations (anything that is not a GET). Kept
  /// apart from [refused] because "the app tried to change something" is the
  /// claim these cases exist to disprove.
  final List<String> mutations = <String>[];

  /// Allows [path] and answers `method path` with [body].
  void allow(String method, String path, Object? body) {
    _scripted['$method $path'] = body;
  }

  /// Makes the allowlisted `method path` fail the way a device with no
  /// connection does, rather than answering it.
  void goOffline(String method, String path) {
    _failing.add('$method $path');
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String key = '${options.method} ${options.path}';
    requests.add(key);

    if (options.method.toUpperCase() != 'GET') {
      // A response mutation, a push registration, a logout, a token exchange:
      // none of them may be attempted here, so they are counted and refused.
      mutations.add(key);
      refused.add(key);
      throw _transportError(options, 'a mutation is not available in this run');
    }
    if (!_scripted.containsKey(key)) {
      refused.add(key);
      throw _transportError(
        options,
        'no such endpoint is available in this run',
      );
    }
    if (_failing.contains(key)) {
      transportFailures.add(key);
      throw _transportError(options, 'connection refused');
    }
    answered.add(key);
    return ResponseBody.fromString(
      jsonEncode(_scripted[key]),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  DioException _transportError(RequestOptions options, String reason) =>
      DioException.connectionError(requestOptions: options, reason: reason);

  @override
  void close({bool force = false}) {}
}

// -- one generation of the app's offline cache ---------------------------------

/// A single generation of the app's cache: a database handle over one file, the
/// repositories built on it, and the transport serving its API.
///
/// Two of these over the same [file] are what a relaunch looks like: the first
/// is closed (`await db.close()`), and the second is a brand-new handle, a
/// brand-new [CacheRepository] and a brand-new `ApiIncidentDetailRepository`
/// over the same bytes. That is what makes "the context survived the process"
/// a statement about the file rather than about a singleton still in memory.
class CacheSession {
  CacheSession({
    required this.file,
    required this.db,
    required this.cache,
    required this.api,
    required this.dio,
    required this.transport,
  });

  /// Opens a session over [file], with no in-memory shortcut.
  factory CacheSession.open(File file, FakeTransport transport) {
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase(file));
    // A reserved, non-resolvable TLD: if the adapter were ever bypassed, the
    // request could not reach a host either.
    final Dio dio = Dio(
      BaseOptions(baseUrl: 'https://uptrack-r4-fixture.invalid'),
    )..httpClientAdapter = transport;
    return CacheSession(
      file: file,
      db: db,
      cache: CacheRepository(db),
      api: UptrackApi(dio: dio),
      dio: dio,
      transport: transport,
    );
  }

  final File file;
  final AppDatabase db;
  final CacheRepository cache;
  final UptrackApi api;
  final Dio dio;
  final FakeTransport transport;

  bool _closed = false;

  /// A detail repository of its own, so a later generation is provably a
  /// different object than the one that did the online read.
  ApiIncidentDetailRepository detailRepository() =>
      ApiIncidentDetailRepository(api: api, cache: cache);

  /// Closes this generation. Idempotent, because each test closes its own
  /// session in the body and the registered tear-down closes it again for a
  /// body that threw first.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await db.close();
    dio.close(force: true);
  }
}

/// A temp directory this fixture owns outright.
///
/// Under `Directory.systemTemp`, which on Android is the app's own cache
/// directory, so nothing this run writes can reach another account's storage.
/// Removed when the test ends: registered *before* the sessions that use it, so
/// the LIFO tear-down order closes those handles first.
Directory ownedTempDir() {
  final Directory dir = Directory.systemTemp.createTempSync(
    'uptrack-r4-offline',
  );
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

/// The database file this fixture reopens. One file per test, so no case can
/// see another's rows.
File databaseFile(Directory dir) => File('${dir.path}/uptrack.db');

/// Opens a generation over [dir]'s file and registers its close.
CacheSession openSession(Directory dir, FakeTransport transport) {
  final CacheSession session = CacheSession.open(databaseFile(dir), transport);
  addTearDown(session.close);
  return session;
}

/// Waits until a write that happens *now* would be stored strictly later than
/// [after], at the resolution the cache stores timestamps at.
///
/// The cache keeps sync times at one-second resolution, so two writes inside
/// the same second are indistinguishable on disk. "Newer" has to mean newer in
/// the file, not merely later in the test. Bounded: at most [maxWait].
Future<void> waitUntilStoredLater(DateTime after, {Duration maxWait = const Duration(seconds: 8)}) async {
  int storedSecond(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000;
  final int target = storedSecond(after) + 2;
  final DateTime deadline = DateTime.now().toUtc().add(maxWait);
  while (storedSecond(DateTime.now()) < target) {
    if (DateTime.now().toUtc().isAfter(deadline)) {
      fail(
        'the wall clock never passed ${DateTime.fromMillisecondsSinceEpoch(target * 1000)}: '
        'a "newer snapshot" claim has to be newer in the stored file, not just '
        'later in the test',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Pumps until the tree is quiet, with a bounded wait.
Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    _settleTimeout,
  );
}

// -- server payloads ----------------------------------------------------------

Map<String, Object?> _incidentJson(
  String id, {
  String monitorName = kMonitorName,
  String? resolvedAt,
}) => <String, Object?>{
  'id': id,
  'monitor_id': 'm-checkout',
  'monitor_name': monitorName,
  'status': resolvedAt == null ? 'ongoing' : 'resolved',
  'inserted_at': '2026-10-04T20:55:00Z',
  'started_at': '2026-10-04T20:55:00Z',
  'acknowledged_at': null,
  'resolved_at': resolvedAt,
};

Map<String, Object?> _updateJson() => <String, Object?>{
  'id': 41,
  'status': 'investigating',
  'title': kUpdateTitle,
  'description': kUpdateDescription,
  'posted_at': '2026-10-04T21:02:00Z',
};

/// The monitor name one of the two fixture incidents is filed under, matching
/// what each list response says about it.
String kOtherMonitorNameOf(String id) =>
    id == kSavedEmptyId ? kMonitorName : kOtherMonitorName;

Map<String, Object?> _detailEnvelope(
  String id, {
  String monitorName = kMonitorName,
  String? resolvedAt,
  List<Object?> updates = const <Object?>[],
}) => <String, Object?>{
  'data': <String, Object?>{
    'incident': _incidentJson(
      id,
      monitorName: monitorName,
      resolvedAt: resolvedAt,
    ),
    'updates': updates,
  },
};

Map<String, Object?> _listEnvelope(List<Object?> incidents) =>
    <String, Object?>{'data': incidents};

// -- surface, viewport and shell ----------------------------------------------

/// Sets the surface this run is about: brightness and text scale on the platform
/// dispatcher (what `MediaQuery` actually reads), and — on the host only — the
/// phone viewport.
///
/// A device run keeps the surface the OS reported: physical size, device pixel
/// ratio and insets, because the capture comes from that surface. Overriding it
/// would leave the reported insets describing a window that is not the one being
/// captured.
void configureSurface(
  WidgetTester tester, {
  required Brightness brightness,
  double textScale = 2,
}) {
  if (!kRunningOnAndroid) {
    tester.view.physicalSize = kPhoneViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  expectPhoneViewport(tester);
  debugPrint('VIEWPORT ${describeViewport(tester)}');
}

/// The viewport in logical pixels, whatever the surface actually is.
Size logicalViewport(WidgetTester tester) =>
    tester.view.physicalSize / tester.view.devicePixelRatio;

/// The facts a capture is only interpretable next to: logical size, device pixel
/// ratio, physical size and the insets the OS reports, in logical pixels.
String describeViewport(WidgetTester tester) {
  final double dpr = tester.view.devicePixelRatio;
  final Size logical = logicalViewport(tester);
  return 'logical=${logical.width.toStringAsFixed(1)}x'
      '${logical.height.toStringAsFixed(1)} '
      'dpr=${dpr.toStringAsFixed(3)} '
      'physical=${tester.view.physicalSize.width.toStringAsFixed(0)}x'
      '${tester.view.physicalSize.height.toStringAsFixed(0)} '
      'insetTop=${(tester.view.padding.top / dpr).toStringAsFixed(1)} '
      'insetBottom=${(tester.view.padding.bottom / dpr).toStringAsFixed(1)} '
      'insetLeft=${(tester.view.padding.left / dpr).toStringAsFixed(1)} '
      'insetRight=${(tester.view.padding.right / dpr).toStringAsFixed(1)}';
}

/// A device run must be a phone-sized surface at its own metrics.
void expectPhoneViewport(WidgetTester tester) {
  if (!kRunningOnAndroid) {
    return;
  }
  expect(
    tester.view.devicePixelRatio,
    greaterThanOrEqualTo(1.5),
    reason:
        'a real Android surface keeps its own pixel ratio; forcing one would '
        'report the OS insets against a surface that is not being captured: '
        '${describeViewport(tester)}',
  );
  expect(
    tester.view.padding.top,
    greaterThan(0),
    reason:
        'a real status bar is a real inset and must not be zeroed: '
        '${describeViewport(tester)}',
  );
  final Size logical = logicalViewport(tester);
  expect(
    logical.width,
    inInclusiveRange(320, 480),
    reason:
        'a phone-width surface, not a tablet or a window: '
        '${describeViewport(tester)}',
  );
  expect(
    logical.height,
    inInclusiveRange(640, 1000),
    reason: 'a phone-height surface: ${describeViewport(tester)}',
  );
}

/// The top inset as the layout sees it, read where it still exists.
///
/// Read at the screen, above the `Scaffold` that consumes it, and cross-checked
/// against the inset the OS reports on the view ([FlutterView.padding] in
/// physical pixels over the surface's own device pixel ratio). Reading it at a
/// descendant would measure zero — the `SafeArea`/`Scaffold` has already applied
/// the inset as padding and removed it from the `MediaQuery` of its subtree —
/// and a run that zeroed a real inset, or divided one by a ratio it chose
/// itself, would then fail to notice.
double screenTopInset(WidgetTester tester) {
  final BuildContext above = tester.element(
    find.byType(IncidentDetailScreen),
  );
  final double consumed = MediaQuery.paddingOf(above).top;
  final double reported = tester.view.padding.top / tester.view.devicePixelRatio;
  expect(
    consumed,
    closeTo(reported, 1),
    reason:
        'the inset the layout consumed must be the one the OS reports, not one '
        'this run invented: ${describeViewport(tester)}',
  );
  return consumed;
}

/// The minimal shell the detail screen needs: a [ProviderScope] and a
/// [MaterialApp] carrying the real [AppTheme].
///
/// The two overrides are the production boundary the screen reads through, and
/// the test reads them back from the container that actually serves the tree
/// ([detailContainer]) rather than trusting that they were installed. Nothing
/// else is built: no router, no login, no demo session and no push service, so
/// there is nothing here that could register an FCM token or send an email.
Future<void> pumpDetail(
  WidgetTester tester, {
  required CacheSession session,
  required String incidentId,
  required Brightness brightness,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        uptrackApiProvider.overrideWithValue(session.api),
        cacheRepositoryProvider.overrideWithValue(session.cache),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: IncidentDetailScreen(incidentId: incidentId),
      ),
    ),
  );
  await settle(tester);
}

/// The container that resolved the services for the rendered screen.
ProviderContainer detailContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(IncidentDetailScreen)));

/// Asserts the container that serves the rendered tree is this fixture's
/// session, and that the detail repository inside it is a real
/// `ApiIncidentDetailRepository` — not a fake parked on an outer scope.
void expectSessionUnderTest(
  WidgetTester tester,
  CacheSession session,
  String incidentId,
) {
  final ProviderContainer container = detailContainer(tester);
  expect(
    container.read(uptrackApiProvider),
    same(session.api),
    reason:
        'the screen must read the API of this generation, not a leftover one',
  );
  expect(container.read(cacheRepositoryProvider), same(session.cache));
  final IncidentDetailRepository repository = container.read(
    incidentDetailRepositoryProvider,
  );
  expect(repository, isA<ApiIncidentDetailRepository>());
  expect(
    (repository as ApiIncidentDetailRepository).confirmedDetail(incidentId),
    isNull,
    reason:
        'a generation that has never read online has no memory to fall back on; '
        'whatever is on screen came off the disk',
  );
}

/// Unmounts the tree, so the next generation is not shadowed by a live
/// container over the old database handle.
Future<void> unmountDetail(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await settle(tester);
}

/// Waits for a state the screen reaches because the transport answers at once.
///
/// No sleeps: the transport is synchronous, so the state is observable as
/// content, and waiting on content is what keeps this deterministic on a loaded
/// CI box and a slow emulator alike.
Future<void> awaitDetailState(WidgetTester tester, Finder ready) async {
  await settle(tester);
  expect(
    ready,
    findsWidgets,
    reason: 'the detail must reach this state, not time out',
  );
}

// -- the finders the screen exposes -------------------------------------------

Finder get _acknowledge => find.widgetWithText(UptrackButton, 'Acknowledge');
Finder get _escalate => find.widgetWithText(UptrackButton, 'Escalate');
Finder get _snooze => find.widgetWithText(UptrackButton, 'Snooze 1 hour');
Finder get _updatesHeading => find.text('Updates');

/// The area a phone user can actually reach: the detail's own scroll viewport.
///
/// The `Scaffold` body, not the whole window — the app bar is chrome, and a
/// section scrolled into the app bar has not been reached.
Rect visibleArea(WidgetTester tester) => tester.getRect(
  find.descendant(
    of: find.byType(IncidentDetailScreen),
    matching: find.byType(Scrollable),
  ),
);

/// Scrolls the detail's own list until [target] has been built and is inside
/// the reachable area.
///
/// Scrolling with finders is what makes "the updates and the response controls
/// are reachable on a phone" a statement about a phone: growing the window until
/// everything fits would answer a different question.
Future<void> reveal(WidgetTester tester, Finder target) async {
  final Finder list = find.descendant(
    of: find.byType(IncidentDetailScreen),
    matching: find.byType(Scrollable),
  );
  expect(
    list,
    findsOneWidget,
    reason: 'the detail must stay one scroll view a phone can swipe',
  );
  await tester.dragUntilVisible(
    target,
    list,
    const Offset(0, -150),
    maxIteration: 60,
  );
  await settle(tester);
  // `dragUntilVisible` stops as soon as *any* part of the target is on screen,
  // which can leave its top edge under the app bar. `ensureVisible` scrolls the
  // last few pixels so the whole of it is in the reachable area, which is what
  // [expectReachable] then asserts.
  await tester.ensureVisible(target);
  await settle(tester);
}

/// Asserts [target] sits inside the reachable area, fully.
void expectReachable(WidgetTester tester, Finder target, String what) {
  final Rect area = visibleArea(tester);
  final Rect rect = tester.getRect(target);
  expect(
    area.contains(rect.topLeft) && area.contains(rect.bottomRight),
    isTrue,
    reason:
        '$what must be reachable on this phone without resizing the window: '
        '${rect.topLeft}→${rect.bottomRight} in $area, '
        '${describeViewport(tester)}',
  );
}

/// Height [text] needs to be shown in full, measured at the exact width it was
/// given — and proof that nothing was dropped to make it fit.
double fullTextHeight(WidgetTester tester, Finder text) {
  final BuildContext context = tester.element(text);
  final String label = tester.widget<Text>(text).data!;
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: label,
      style: DefaultTextStyle.of(context).style
          .merge(tester.widget<Text>(text).style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: tester.renderObject<RenderParagraph>(text).size.width);
  addTearDown(painter.dispose);
  expect(
    painter.didExceedMaxLines,
    isFalse,
    reason: '"$label" must be shown in full, with no line cap or ellipsis',
  );
  return painter.height;
}

/// Asserts a piece of copy is on screen complete, wrapping onto as many lines as
/// the width needs.
void expectShownInFull(WidgetTester tester, Finder text, String what) {
  expect(text, findsWidgets, reason: '$what must be on screen: $text');
  final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(text);
  expect(
    paragraph.size.height,
    greaterThanOrEqualTo(fullTextHeight(tester, text) - 0.5),
    reason: '$what must be shown in full at the real text scale',
  );
}

/// A disabled control, read on the node a screen reader would announce: it still
/// is a button, it still carries its incident-specific label, it announces that
/// it is not enabled, and it offers nothing to tap.
void expectDisabledControl(WidgetTester tester, String label) {
  final SemanticsNode node = tester.getSemantics(find.bySemanticsLabel(label));
  expect(node.label, label, reason: 'the node must carry its own label');
  expect(
    node.flagsCollection.isButton,
    isTrue,
    reason: '"$label" must still be announced as a button',
  );
  expect(
    node.flagsCollection.isEnabled,
    Tristate.isFalse,
    reason: '"$label" must announce that it is disabled',
  );
  expect(
    node.getSemanticsData().hasAction(SemanticsAction.tap),
    isFalse,
    reason: '"$label" must offer no tap while it is disabled',
  );
}

/// Asserts the three response controls are disabled, say why, and that tapping
/// them changed nothing on the server side.
Future<void> expectResponseQueueIsDead(
  WidgetTester tester,
  FakeTransport transport, {
  required String reason,
}) async {
  for (final Finder control in <Finder>[_acknowledge, _escalate, _snooze]) {
    expect(
      tester.widget<UptrackButton>(control).onPressed,
      isNull,
      reason:
          'an offline incident must offer no response action, and must not '
          'queue one for later either',
    );
  }
  expectDisabledControl(tester, kAcknowledgeLabel);
  expectDisabledControl(tester, kEscalateLabel);
  expectDisabledControl(tester, kSnoozeLabel);

  expectShownInFull(tester, find.text(reason), 'the reason a control is disabled');

  // Attempts, in both directions: a disabled control stays a control a user can
  // find, scroll to and press, and pressing it must produce no request at all.
  // Each is revealed first, because at 200% the three controls do not all fit on
  // one screen — tapping at a control's off-screen position would prove nothing
  // about the control, only about the tap.
  for (final Finder control in <Finder>[_acknowledge, _escalate, _snooze]) {
    await reveal(tester, control);
    expectReachable(tester, control, 'the disabled control');
    await tester.tap(control);
    await settle(tester);
  }

  expect(find.byType(Dialog), findsNothing, reason: 'no confirmation may open');
  expect(find.byType(SnackBar), findsNothing);
  expect(
    transport.mutations,
    isEmpty,
    reason:
        'no mutation may be sent or queued while offline: '
        '${transport.mutations}',
  );
  expect(
    transport.refused,
    isEmpty,
    reason:
        'nothing outside the allowlist may even be attempted: '
        '${transport.refused}',
  );
  expect(
    transport.requests,
    everyElement(startsWith('GET ')),
    reason: 'a disabled screen reads, it never writes: ${transport.requests}',
  );
}

// -- capture -------------------------------------------------------------------

/// Whether *this test* has already converted the Flutter surface to an image.
///
/// Test-scoped, and reset in tear-down, because that is the scope the platform
/// callback manager keeps it in: a second conversion inside one test asserts
/// (`Surface already converted to an image`) and leaves the revert asserting on
/// its way out too. Per test rather than per capture is what lets one case take
/// more than one screenshot.
bool _surfaceConverted = false;

/// Converts the surface once per test, before the first capture in it.
Future<void> ensureSurfaceConverted(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  if (_surfaceConverted) {
    return;
  }
  debugPrint('CAPTURE_STAGE $name converting ${describeViewport(tester)}');
  try {
    await binding
        .convertFlutterSurfaceToImage()
        .timeout(_captureStageTimeout);
  } on TimeoutException catch (error) {
    fail(
      'converting the Flutter surface to an image for $name never returned '
      'within ${_captureStageTimeout.inSeconds}s ($error): the device surface '
      'cannot be captured at ${describeViewport(tester)}',
    );
  }
  _surfaceConverted = true;
  addTearDown(() {
    _surfaceConverted = false;
  });
  debugPrint('CAPTURE_STAGE $name converted');
}

/// Awaits one capture stage under [_captureStageTimeout], and turns a stall into
/// a failure that names the stage and the path it was working on.
///
/// The filesystem calls in [capture] can stall exactly like the capture itself:
/// a device whose storage never answers would otherwise end the run as "did not
/// complete", which says nothing about what was on screen. Bounded, they name
/// the stage they stalled in instead.
Future<T> withinCaptureStage<T>(Future<T> stage, String name, String what) async {
  try {
    return await stage.timeout(_captureStageTimeout);
  } on TimeoutException catch (error) {
    fail(
      '$what for $name never returned within ${_captureStageTimeout.inSeconds}s '
      '($error): the app cache at ${Directory.systemTemp.path} did not answer, '
      'so the capture cannot be filed for the host to pull',
    );
  }
}

/// Writes a PNG into the app cache, so the host can pull it after the suite
/// exits.
///
/// Exactly one condition is skippable, and only outside Android: on the host the
/// integration binding's screenshot channel has no implementation, so it reports
/// a [MissingPluginException]. Every other failure — the conversion, the capture,
/// or the write — fails the run, and on Android even the missing-plugin case
/// fails, because a device run that captured nothing is not evidence.
///
/// Every stage prints before it starts and is bounded, so a stall names the
/// stage it stalled in instead of ending as "did not complete".
Future<void> capture(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  if (!kRunningOnAndroid) {
    // Host: the only skippable condition is the integration binding's missing
    // screenshot channel. `convertFlutterSurfaceToImage` is a no-op off-device,
    // so it is the `takeScreenshot` call that reports the missing plugin — and
    // that is still the one known condition. Any other failure fails the run.
    try {
      await ensureSurfaceConverted(tester, binding, name);
      await tester.pump();
      await binding.takeScreenshot(name);
    } on MissingPluginException catch (error) {
      debugPrint('SCREENSHOT_HOST_CHANNEL_UNAVAILABLE $name $error');
      return;
    }
    fail(
      'host run: the screenshot channel answered for $name, so this run should '
      'have captured instead of skipping',
    );
  }

  // Device run: no catch. Anything that goes wrong fails the run, and every
  // stage is bounded so a stall fails at the stage it stalled in.
  await ensureSurfaceConverted(tester, binding, name);

  debugPrint('CAPTURE_STAGE $name pumping ${describeViewport(tester)}');
  await tester.pump();

  debugPrint('CAPTURE_STAGE $name capturing');
  final List<int> bytes;
  try {
    bytes = await binding.takeScreenshot(name).timeout(_captureStageTimeout);
  } on TimeoutException catch (error) {
    fail(
      'capturing $name never returned within ${_captureStageTimeout.inSeconds}s '
      '($error): the driver asked for a frame this surface did not deliver at '
      '${describeViewport(tester)}',
    );
  }
  expect(
    bytes,
    isNotEmpty,
    reason: '$name must capture real pixels, not an empty buffer',
  );

  final Directory dir = Directory(
    '${Directory.systemTemp.path}/$_captureDirName',
  );
  debugPrint('CAPTURE_STAGE $name creating ${dir.path}');
  await withinCaptureStage(
    dir.create(recursive: true),
    name,
    'creating the capture directory',
  );
  final File file = File('${dir.path}/$name.png');
  debugPrint('CAPTURE_STAGE $name writing ${bytes.length} bytes');
  await withinCaptureStage(
    file.writeAsBytes(bytes, flush: true),
    name,
    'writing the capture',
  );
  expect(
    file.existsSync(),
    isTrue,
    reason: '$name must exist in the app cache for the host to pull it',
  );
  final int written = await withinCaptureStage(
    file.length(),
    name,
    'measuring the written capture',
  );
  expect(
    written,
    bytes.length,
    reason: '$name must be written whole at ${file.path}',
  );
  debugPrint('SCREENSHOT_SAVED $name ${bytes.length} ${file.path}');
}

/// Turns semantics on for this test and guarantees it goes back off.
///
/// The tear-down registration is what protects the *next* test: a body that threw
/// before it could close the handle still gets it closed, instead of leaking a
/// live semantics tree into whatever runs next.
SemanticsLease semanticsOn(WidgetTester tester) {
  final SemanticsLease lease = SemanticsLease._(tester.ensureSemantics());
  addTearDown(lease.dispose);
  return lease;
}

/// A semantics handle a test can close itself, without closing it twice.
///
/// Every test closes its lease at the end of its own body, while the tear-down
/// registered by [semanticsOn] closes it again for a body that threw first, so
/// disposing twice must be a no-op rather than a second call into the binding.
class SemanticsLease {
  SemanticsLease._(this._handle);

  final SemanticsHandle _handle;
  bool _disposed = false;

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _handle.dispose();
  }
}

/// The two persisted facts a case is about, read straight off the file.
///
/// Read back through a fresh [CacheRepository] rather than kept in memory: the
/// claim under test is what is *stored*, and a timestamp compared as
/// `DateTime.now()`-adjacent in-memory value would pass even if the write
/// dropped it.
typedef Stored = ({DateTime updatesSyncedAt, DateTime summarySyncedAt});

/// The stored sync times for [id]: the detail snapshot's own read time and the
/// summary row's write time. The two are independent facts and are returned
/// apart, because most of what these cases prove is that one moved and the other
/// did not.
Future<Stored> storedTimes(CacheRepository cache, String id) async {
  final CachedIncidentDetailSnapshot? snapshot = await cache.getIncidentDetail(
    id,
  );
  final CachedList<CachedIncident> cached = await cache.getIncidents();
  CachedIncident? row;
  for (final CachedIncident candidate in cached.data) {
    if (candidate.id == id) {
      row = candidate;
      break;
    }
  }
  if (snapshot == null || row == null) {
    fail('nothing is stored for $id: ${snapshot == null}, ${row == null}');
  }
  return (updatesSyncedAt: snapshot.syncedAt, summarySyncedAt: row.cachedAt);
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('the fake transport closes every door but two', () {
    testWidgets(
      'only the allowlisted reads are answered; mutations, auth and push are refused',
      (WidgetTester tester) async {
        final FakeTransport transport = FakeTransport();
        final CacheSession session = openSession(
          ownedTempDir(),
          transport,
        );
        final UptrackApi api = session.api;

        await expectLater(
          api.getIncident(kIncidentId),
          throwsA(isA<DioException>()),
          reason: 'a detail read was never allowlisted, so it cannot be served',
        );
        await expectLater(
          api.listIncidents(),
          throwsA(isA<DioException>()),
          reason: 'the list read was never allowlisted either',
        );
        // The endpoints this fixture must never be near.
        await expectLater(api.getMe(), throwsA(isA<DioException>()));
        await expectLater(
          api.acknowledgeIncident(kIncidentId),
          throwsA(isA<DioException>()),
        );
        await expectLater(
          api.registerPushDevice(platform: 'android', token: 'never-registered'),
          throwsA(isA<DioException>()),
          reason: 'an FCM token registration must never be attempted',
        );
        await expectLater(
          api.requestMagicLink(email: 'nobody@example.invalid'),
          throwsA(isA<DioException>()),
        );

        expect(transport.answered, isEmpty, reason: 'nothing was ever served');
        expect(transport.transportFailures, isEmpty);
        expect(transport.requests, hasLength(6));
        expect(
          transport.mutations,
          <String>[
            'POST ${incidentAcknowledgePath(kIncidentId)}',
            'POST $kPushDevicesPath',
            'POST $kMagicLinkPath',
          ],
          reason: 'every write this app knows is counted as a mutation',
        );
        expect(
          transport.refused,
          hasLength(6),
          reason: 'nothing outside the allowlist is silently dropped',
        );
        expect(
          transport.requests,
          contains('GET $kGetMePath'),
          reason: 'the auth read was attempted and refused, never served',
        );
        expect(transport.answered, isEmpty);
        expect(find.byType(IncidentDetailScreen), findsNothing);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });

  group('a saved detail read survives the app being closed', () {
    for (final (String name, Brightness brightness) in <(String, Brightness)>[
      ('light', Brightness.light),
      ('dark', Brightness.dark),
    ]) {
      testWidgets(
        '$name at 200%: the reopened screen keeps the update, its real sync time '
        'and a dead response queue',
        (WidgetTester tester) async {
          final SemanticsLease semantics = semanticsOn(tester);
          final Directory dir = ownedTempDir();

          // -- generation one: online, one successful detail read ----------
          final FakeTransport online = FakeTransport();
          online.allow(
            'GET',
            incidentDetailPath(kIncidentId),
            _detailEnvelope(
              kIncidentId,
              updates: <Object?>[_updateJson()],
            ),
          );
          final CacheSession first = openSession(dir, online);
          configureSurface(tester, brightness: brightness);

          await pumpDetail(
            tester,
            session: first,
            incidentId: kIncidentId,
            brightness: brightness,
          );
          await settle(tester);
          await awaitDetailState(tester, find.text(kMonitorName));

          // The online state: nothing is claimed to be cached, and the sync
          // stamp is the stored read time rather than a cached-read time.
          expect(find.text(kOfflineNotice), findsNothing);
          expect(find.text(kNoSavedUpdates), findsNothing);
          final Stored onlineStored = await storedTimes(
            first.cache,
            kIncidentId,
          );
          expect(
            find.text(
              '$kSummaryStampPrefix ${formatInstant(onlineStored.summarySyncedAt)}',
            ),
            findsOneWidget,
            reason: 'the online stamp is the instant the read succeeded',
          );
          expect(
            onlineStored.updatesSyncedAt,
            onlineStored.summarySyncedAt,
            reason:
                'one detail write stores the summary and the updates together, '
                'so their sync times are the same instant',
          );
          expect(
            await first.cache.lastSynced(kIncidentsCacheKey),
            isNull,
            reason: 'reading one incident is not a list sync',
          );
          debugPrint(
            'PERSISTED online $kIncidentId '
            'updates=${onlineStored.updatesSyncedAt.toIso8601String()} '
            'summary=${onlineStored.summarySyncedAt.toIso8601String()}',
          );

          // The update itself is below the fold at 200%, so reaching it is a
          // statement about this phone rather than about a taller window.
          await reveal(tester, find.text(kUpdateTitle));
          expectReachable(
            tester,
            find.text(kUpdateTitle),
            'the update the online read returned',
          );
          expect(find.text(kUpdateDescription), findsOneWidget);
          expect(find.text(kUpdateStatus), findsOneWidget);

          // -- the app is closed --------------------------------------------
          await unmountDetail(tester);
          await first.close();

          // -- generation two: the same file, a new repository and container -
          final FakeTransport offline = FakeTransport();
          offline.allow(
            'GET',
            incidentDetailPath(kIncidentId),
            <String, Object?>{'never': 'served'},
          );
          offline.goOffline('GET', incidentDetailPath(kIncidentId));
          final CacheSession second = openSession(dir, offline);

          // Read before the screen renders anything: this is what the file
          // holds, so "nothing changed" can be about the file and not about the
          // fallback that is about to read it.
          final Stored before = await storedTimes(second.cache, kIncidentId);
          expect(before.updatesSyncedAt, onlineStored.updatesSyncedAt);
          expect(before.summarySyncedAt, onlineStored.summarySyncedAt);

          await pumpDetail(
            tester,
            session: second,
            incidentId: kIncidentId,
            brightness: brightness,
          );
          expectSessionUnderTest(tester, second, kIncidentId);
          await awaitDetailState(tester, find.text(kOfflineNotice));

          expect(
            tester.takeException(),
            isNull,
            reason: 'no overflow, and no other layout exception, at 200%',
          );

          // The real inset is respected rather than absorbed by the screen.
          final double inset = screenTopInset(tester);
          expect(
            tester.getRect(find.byType(AppBar)).top,
            greaterThanOrEqualTo(inset - 0.5),
            reason: 'the app bar starts below the status bar it must respect',
          );

          // Offline is said in words and with an icon, not by color alone: color
          // is never the only signal that what is on screen is cached.
          expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
          expectShownInFull(
            tester,
            find.text(kOfflineNotice),
            'the offline notice',
          );

          // The summary sync stamp is the stored read time, spelled exactly as
          // the file holds it — not the moment the cached row was read back.
          final String summaryStamp =
              '$kSummaryStampPrefix ${formatInstant(before.summarySyncedAt)}';
          expectShownInFull(tester, find.text(summaryStamp), 'the sync stamp');
          expect(
            find.bySemanticsLabel(summaryStamp),
            findsOneWidget,
            reason: 'the stamp reaches the semantics tree as one sentence',
          );
          expect(
            find.textContaining(kUpdatesStampPrefix),
            findsNothing,
            reason:
                'one read wrote both, so repeating the same instant as a second '
                '"Updates last synced" would add nothing',
          );

          await capture(tester, binding, 'r4-offline-detail-$name-200');

          // The response queue is dead, visibly and in the semantics tree.
          await reveal(tester, _escalate);
          await expectResponseQueueIsDead(
            tester,
            offline,
            reason: kOfflineResponseReason,
          );

          // The saved update, exactly as the successful read returned it —
          // below the fold, so reached by scrolling like a reader would. The
          // heading and the row are revealed in turn rather than in one scroll:
          // bringing the row fully into view scrolls the heading past the top.
          await reveal(tester, _updatesHeading);
          expectReachable(tester, _updatesHeading, 'the updates heading');
          await reveal(tester, find.text(kUpdateTitle));
          expectReachable(tester, find.text(kUpdateTitle), 'the saved update');
          expect(find.text(kUpdateDescription), findsOneWidget);
          expect(find.text(kUpdateStatus), findsOneWidget);
          expect(
            find.bySemanticsLabel(
              RegExp('^Update ${RegExp.escape(kUpdateTitle)}'),
            ),
            findsOneWidget,
            reason: 'the update is announced as one row of its own',
          );

          await capture(
            tester,
            binding,
            'r4-offline-detail-$name-200-updates',
          );

          // -- nothing the screen did moved a stored timestamp ---------------
          final Stored after = await storedTimes(second.cache, kIncidentId);
          expect(
            after.updatesSyncedAt,
            before.updatesSyncedAt,
            reason:
                'a fallback read must never restamp the updates as freshly '
                'synced',
          );
          expect(
            after.summarySyncedAt,
            before.summarySyncedAt,
            reason: 'nor the summary',
          );
          expect(
            (await second.cache.getIncidentDetail(kIncidentId))!
                .updates
                .single
                .displayTitle,
            kUpdateTitle,
            reason: 'the saved payload is untouched, content included',
          );
          expect(
            await second.cache.lastSynced(kIncidentsCacheKey),
            isNull,
            reason: 'a failed read is not a list sync either',
          );
          debugPrint(
            'PERSISTED offline $kIncidentId '
            'updates=${after.updatesSyncedAt.toIso8601String()} '
            'summary=${after.summarySyncedAt.toIso8601String()}',
          );

          // -- the transport's whole account of the run ----------------------
          expect(
            offline.requests,
            <String>['GET ${incidentDetailPath(kIncidentId)}'],
            reason:
                'the reopened screen read the detail exactly once, and nothing '
                'else',
          );
          expect(
            offline.transportFailures,
            <String>['GET ${incidentDetailPath(kIncidentId)}'],
            reason: 'that read failed the way a device with no connection does',
          );
          expect(
            offline.answered,
            isEmpty,
            reason: 'nothing was served in this generation',
          );
          expect(offline.refused, isEmpty);
          expect(
            online.mutations,
            isEmpty,
            reason: 'the online read was a read too',
          );
          semantics.dispose();
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    }
  });

  group('a newer list read resolves the incident without a detail fetch', () {
    for (final (String name, Brightness brightness) in <(String, Brightness)>[
      ('light', Brightness.light),
      ('dark', Brightness.dark),
    ]) {
      testWidgets(
        '$name at 200%: the resolved summary appears with the older updates and '
        'their own sync time',
        (WidgetTester tester) async {
          final SemanticsLease semantics = semanticsOn(tester);
          final Directory dir = ownedTempDir();

          // -- generation one: the detail is read online ----------------------
          final FakeTransport online = FakeTransport();
          online.allow(
            'GET',
            incidentDetailPath(kIncidentId),
            _detailEnvelope(
              kIncidentId,
              updates: <Object?>[_updateJson()],
            ),
          );
          final CacheSession first = openSession(dir, online);
          configureSurface(tester, brightness: brightness);

          await pumpDetail(
            tester,
            session: first,
            incidentId: kIncidentId,
            brightness: brightness,
          );
          await awaitDetailState(tester, find.text(kMonitorName));
          await reveal(tester, find.text(kUpdateTitle));
          expect(
            find.text(kUpdateTitle),
            findsOneWidget,
            reason: 'the read that is about to be replaced really did save one',
          );
          final Stored afterDetailRead = await storedTimes(
            first.cache,
            kIncidentId,
          );

          await unmountDetail(tester);
          await first.close();

          // -- generation two: a list read resolves the incident -------------
          final FakeTransport relaunched = FakeTransport();
          relaunched.allow(
            'GET',
            _listPath,
            _listEnvelope(<Object?>[
              _incidentJson(
                kIncidentId,
                resolvedAt: '2026-10-04T21:09:00Z',
              ),
            ]),
          );
          relaunched.allow(
            'GET',
            incidentDetailPath(kIncidentId),
            <String, Object?>{'never': 'served'},
          );
          relaunched.goOffline('GET', incidentDetailPath(kIncidentId));
          final CacheSession second = openSession(dir, relaunched);

          // The list read is the newest summary, so it must be strictly newer
          // than the detail read it is compared against — in the file.
          await waitUntilStoredLater(afterDetailRead.summarySyncedAt);
          final IncidentsData list = await ApiIncidentsRepository(
            api: second.api,
            cache: second.cache,
          ).load();

          expect(list.offline, isFalse);
          expect(list.incidents.single.isOngoing, isFalse);
          expect(
            relaunched.answered,
            <String>['GET $_listPath'],
            reason:
                'a list read resolves an incident on its own; the detail was '
                'not needed and was not fetched: ${relaunched.requests}',
          );

          // The replacement preserved the independent detail snapshot exactly.
          final Stored afterListRead = await storedTimes(second.cache, kIncidentId);
          expect(
            afterListRead.updatesSyncedAt,
            afterDetailRead.updatesSyncedAt,
            reason:
                'a list replacement is not a detail read: it must not touch the '
                'updates or their sync time',
          );
          expect(afterListRead.summarySyncedAt.isAfter(afterListRead.updatesSyncedAt), isTrue);
          debugPrint(
            'PERSISTED resolved $kIncidentId '
            'updates=${afterListRead.updatesSyncedAt.toIso8601String()} '
            'summary=${afterListRead.summarySyncedAt.toIso8601String()}',
          );

          // -- now the detail read fails -------------------------------------
          await pumpDetail(
            tester,
            session: second,
            incidentId: kIncidentId,
            brightness: brightness,
          );
          expectSessionUnderTest(tester, second, kIncidentId);
          await awaitDetailState(tester, find.text(kOfflineNotice));
          expect(tester.takeException(), isNull, reason: 'no overflow at 200%');

          // Resolved, from the newer stored summary — memory cannot undo it.
          expect(find.text('Resolved'), findsWidgets);
          expect(
            find.bySemanticsLabel('Incident $kMonitorName, Resolved'),
            findsOneWidget,
            reason:
                'the header must announce Resolved: the newest summary wins, '
                'and this generation has no memory of the open incident',
          );
          expect(
            find.text('Resolved ${formatTimestamp('2026-10-04T21:09:00Z')}'),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(RegExp('^Incident $kMonitorName, Open')),
            findsNothing,
            reason: 'the pre-resolution state must not be resurrected',
          );

          // The summary's own freshness is at the top of the screen.
          final String summaryStamp =
              '$kSummaryStampPrefix ${formatInstant(afterListRead.summarySyncedAt)}';
          expectShownInFull(tester, find.text(summaryStamp), 'the sync stamp');
          await capture(tester, binding, 'r4-offline-resolved-$name-200');

          // A resolved incident offers no response action either, and the
          // offline reason is the one that applies.
          await reveal(tester, _escalate);
          await expectResponseQueueIsDead(
            tester,
            relaunched,
            reason: kOfflineResponseReason,
          );

          // The older saved updates, still there under the resolved summary,
          // with their own older sync time stated separately — the
          // section is below the fold, so it is reached by scrolling.
          await reveal(tester, _updatesHeading);
          expectReachable(tester, _updatesHeading, 'the updates heading');
          await reveal(tester, find.text(kUpdateTitle));
          expectReachable(tester, find.text(kUpdateTitle), 'the saved update');
          expect(find.text(kUpdateDescription), findsOneWidget);
          final String updatesStamp =
              '$kUpdatesStampPrefix ${formatInstant(afterListRead.updatesSyncedAt)}';
          expectShownInFull(tester, find.text(updatesStamp), 'the updates stamp');
          expect(
            updatesStamp,
            isNot(summaryStamp),
            reason:
                'the updates stamp exists precisely because the two stored times '
                'differ',
          );
          await capture(
            tester,
            binding,
            'r4-offline-resolved-$name-200-updates',
          );

          // The failed detail read changed nothing either.
          final Stored afterRender = await storedTimes(second.cache, kIncidentId);
          expect(afterRender.updatesSyncedAt, afterListRead.updatesSyncedAt);
          expect(afterRender.summarySyncedAt, afterListRead.summarySyncedAt);
          expect(relaunched.transportFailures, hasLength(1));
          expect(relaunched.mutations, isEmpty);
          expect(relaunched.refused, isEmpty);
          semantics.dispose();
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    }
  });

  group('a missing snapshot and a saved empty one stay two different facts', () {
    testWidgets(
      'one id reads "no updates yet", the other "no saved updates", from real '
      'stored state',
      (WidgetTester tester) async {
        final SemanticsLease semantics = semanticsOn(tester);
        final Directory dir = ownedTempDir();

        // -- generation one: a successful read that carried no updates ------
        final FakeTransport online = FakeTransport();
        online.allow(
          'GET',
          incidentDetailPath(kSavedEmptyId),
          _detailEnvelope(kSavedEmptyId, monitorName: kMonitorName),
        );
        final CacheSession first = openSession(dir, online);
        configureSurface(tester, brightness: Brightness.light);

        await pumpDetail(
          tester,
          session: first,
          incidentId: kSavedEmptyId,
          brightness: Brightness.light,
        );
        await awaitDetailState(tester, find.text(kMonitorName));
        await reveal(tester, find.text(kNoUpdatesSaved));
        expect(
          find.text(kNoUpdatesSaved),
          findsOneWidget,
          reason:
              'a successful read that carried none is a saved snapshot, so the '
              'screen may say there are none',
        );
        expect(
          find.text(kNoSavedUpdates),
          findsNothing,
          reason: 'the two states must not blur into one another',
        );
        expect(find.text(kOfflineNotice), findsNothing);
        final Stored emptyStored = await storedTimes(first.cache, kSavedEmptyId);
        debugPrint(
          'PERSISTED empty $kSavedEmptyId '
          'updates=${emptyStored.updatesSyncedAt.toIso8601String()}',
        );

        await unmountDetail(tester);
        await first.close();

        // -- generation two: a list read adds a row that was never detailed ---
        final FakeTransport relaunched = FakeTransport();
        relaunched.allow(
          'GET',
          _listPath,
          _listEnvelope(<Object?>[
            _incidentJson(kSavedEmptyId),
            _incidentJson(kSummaryOnlyId, monitorName: kOtherMonitorName),
          ]),
        );
        for (final String id in <String>[kSavedEmptyId, kSummaryOnlyId]) {
          relaunched.allow(
            'GET',
            incidentDetailPath(id),
            <String, Object?>{'never': 'served'},
          );
          relaunched.goOffline('GET', incidentDetailPath(id));
        }
        final CacheSession second = openSession(dir, relaunched);

        await waitUntilStoredLater(emptyStored.updatesSyncedAt);
        await ApiIncidentsRepository(api: second.api, cache: second.cache).load();

        expect(
          await second.cache.countIncidentDetails(),
          1,
          reason:
              'the list read wrote a summary row, not a detail snapshot: a list '
              'read says nothing about an incident\'s updates',
        );
        expect(await second.cache.getIncidentDetail(kSummaryOnlyId), isNull);
        final Stored afterList = await storedTimes(second.cache, kSavedEmptyId);

        // -- the id with the saved, genuinely empty snapshot -----------------
        await pumpDetail(
          tester,
          session: second,
          incidentId: kSavedEmptyId,
          brightness: Brightness.light,
        );
        expectSessionUnderTest(tester, second, kSavedEmptyId);
        await awaitDetailState(tester, find.text(kOtherMonitorNameOf(kSavedEmptyId)));
        expect(
          find.text(
            '$kSummaryStampPrefix ${formatInstant(afterList.summarySyncedAt)}',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        // Its real detail sync time is retained, and is now older than the
        // summary's, so the screen states it as its own stamp. The section is
        // below the fold, so it is reached by scrolling.
        await reveal(tester, _updatesHeading);
        expect(
          find.text(
            '$kUpdatesStampPrefix ${formatInstant(afterList.updatesSyncedAt)}',
          ),
          findsOneWidget,
          reason:
              'an empty snapshot still carries the instant it was actually read',
        );
        expect(
          find.text(kNoUpdatesSaved),
          findsOneWidget,
          reason: 'the saved snapshot really is empty, and really was read',
        );
        expect(
          find.text(kNoSavedUpdates),
          findsNothing,
          reason: 'the two states must not blur into one another',
        );
        expectReachable(tester, find.text(kNoUpdatesSaved), 'the empty state');

        // -- the id with no snapshot at all ----------------------------------
        await pumpDetail(
          tester,
          session: second,
          incidentId: kSummaryOnlyId,
          brightness: Brightness.light,
        );
        expectSessionUnderTest(tester, second, kSummaryOnlyId);
        await awaitDetailState(tester, find.text(kOtherMonitorName));
        // The notice is at the top of the screen and is asserted there: the
        // list is lazy, so scrolling to the updates section disposes it.
        expect(
          find.text(kOfflineNotice),
          findsOneWidget,
          reason: 'the summary row is served, so the screen still shows context',
        );
        expect(
          find.textContaining(kUpdatesStampPrefix),
          findsNothing,
          reason: 'there is no updates snapshot to put a time on',
        );
        // The updates section is below the fold at 200%, so the state is read
        // where a reader reaches it rather than assumed from the data.
        await reveal(tester, find.text(kNoSavedUpdates));
        expect(
          find.text(kNoSavedUpdates),
          findsOneWidget,
          reason:
              'nothing was ever saved for this incident, so the screen says the '
              'updates are not available offline rather than that there are none',
        );
        expect(
          find.text(kNoUpdatesSaved),
          findsNothing,
          reason:
              'with nothing saved the screen cannot claim there are no updates; '
              'it does not know',
        );
        expect(tester.takeException(), isNull);
        expectReachable(
          tester,
          find.text(kNoSavedUpdates),
          'the no-snapshot state',
        );

        expect(
          relaunched.mutations,
          isEmpty,
          reason: 'reading cached context changes nothing on the server',
        );
        expect(
          relaunched.answered,
          everyElement(equals('GET $_listPath')),
          reason: 'both detail reads failed; only the list read was served',
        );
        expect(relaunched.transportFailures, hasLength(2));
        expect(relaunched.refused, isEmpty);
        expect(online.mutations, isEmpty);
        semantics.dispose();
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}