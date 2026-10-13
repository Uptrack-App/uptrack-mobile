/// Device acceptance fixture for the response dashboard and the custom filter
/// chip (R2), driven on a real Android demo build.
///
/// This is the ONE entry point for that acceptance run. It deliberately pumps
/// the real [UptrackDemoApp] — the production router, the production screens,
/// and the production [DemoAdapter] — instead of re-pumping screens against
/// stand-in repositories, so what is captured on the device is the app a beta
/// tester would actually see.
///
/// Overridden here, and nothing else:
/// * the sample adapter, so every request the journey makes is observable;
/// * platform brightness and text scale, so light/dark at 200% are fixtures
///   rather than a second copy of the theme;
/// * the demo container's push service, with a service that is *unavailable*: if
///   any part of the demo journey ever tried to initialize push, it fails loudly
///   here instead of quietly registering an FCM token.
///
/// The push override is passed into [UptrackDemoApp.pushService] rather than an
/// outer `ProviderScope`: the demo builds its own container, so an override
/// outside it would be an unreachable spy that asserted nothing. The container
/// is read back from the rendered tree and checked for identity, so what is
/// asserted is the boundary the demo actually resolves.
///
/// NOT overridden: `main()`, the router, and auth state. The demo signs in as
/// itself, exactly as it does in the shipping build.
///
/// Every viewport is a real phone (390×844). Sections below the fold are
/// reached by scrolling with test finders, never by making the window tall
/// enough to hold the whole page: a 2400dp viewport cannot tell a beta tester
/// whether the queue is reachable on a phone.
///
/// Two modes:
/// * host (`flutter test`): the journey, layout and semantics assertions run;
///   the capture is skipped for exactly one known reason — the integration
///   binding's screenshot channel has no host implementation, so it reports a
///   `MissingPluginException`.
/// * device (`flutter test integration_test/demo_response_device_test.dart -d
///   `emulator-5554` `--no-enable-impeller` `--no-uninstall`): the same
///   assertions, then PNGs are written under `Directory.systemTemp`, which on
///   Android is the app's **code cache**
///   (`/data/user/0/app.uptrack.mobile/code_cache`), not its `cache` directory —
///   so they land in `code_cache/uptrack_screenshots/NAME.png` and the host
///   pulls them with
///   `adb exec-out run-as app.uptrack.mobile cat
///   code_cache/uptrack_screenshots/NAME.png`. The `SCREENSHOT_SAVED` line
///   each capture prints carries the absolute path the run actually wrote, and
///   that path is the one to pull. `--no-uninstall` is what makes the evidence
///   collectable at all; `--no-enable-impeller` selects the Skia/OpenGL path
///   explicitly rather than relying on the default (Impeller is not the
///   Android default here, and the emulator's software Vulkan stack stalls on
///   it). Nothing about the capture is best-effort there: a failed capture,
///   conversion or write fails the run.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Tristate;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uptrack_mobile/design/components.dart' show UptrackButton;
import 'package:uptrack_mobile/features/auth/auth_controller.dart'
    show dioProvider;
import 'package:uptrack_mobile/features/auth/demo_session.dart';
import 'package:uptrack_mobile/features/dashboard/dashboard_screen.dart';
import 'package:uptrack_mobile/features/incidents/incident_detail_screen.dart';
import 'package:uptrack_mobile/features/incidents/incidents_controller.dart'
    show IncidentStatusFilter;
import 'package:uptrack_mobile/features/incidents/incidents_screen.dart';
import 'package:uptrack_mobile/push/push_providers.dart';
import 'package:uptrack_mobile/push/push_service.dart';

/// The unacknowledged open incident the journey responds to, the older
/// unacknowledged open incident behind it, and the acknowledged one that starts
/// in the acknowledged section.
const String kResponder = 'Public API';
const String kOlderOutstanding = 'Marketing website';
const String kAlreadyAcknowledged = 'Checkout service';

/// The acknowledge control's own semantics label on that incident: the label
/// sits on the actionable node, so this is what a screen reader announces.
const String kAcknowledgeLabel = 'Acknowledge incident $kResponder';

/// A section key on the dashboard; see `_IncidentSection`'s key in
/// `dashboard_screen.dart`.
const ValueKey<String> kNeedsAckSection = ValueKey<String>(
  'dashboard-needs-acknowledgement',
);
const ValueKey<String> kAcknowledgedSection = ValueKey<String>(
  'dashboard-acknowledged-open',
);

/// The bottom-navigation destination keys, from `UptrackAdaptiveScaffold`
/// (`ValueKey('destination-$i')` over `['Dashboard', 'Monitors', 'Incidents',
/// 'Settings']`). A 390dp-wide window is below the 600dp rail threshold, so
/// these are in the bottom bar every phone capture includes.
const ValueKey<String> kDashboardDestination = ValueKey<String>(
  'destination-0',
);
const ValueKey<String> kIncidentsDestination = ValueKey<String>(
  'destination-2',
);

/// The real phone viewport used for every run: the size of the device this
/// acceptance evidence is about.
const Size kPhoneViewport = Size(390, 844);

/// True only on the Android device this acceptance run targets.
///
/// Read from the real runtime, not [defaultTargetPlatform]: a Flutter host test
/// reports Android as its target platform (that is how `TargetPlatformVariant`
/// works), so `defaultTargetPlatform` would make this host run claim it had a
/// screenshot channel and turn the one legitimate skip into a failure. On a real
/// Android run this is `true`, and on Android nothing is skipped.
final bool kRunningOnAndroid = Platform.isAndroid;

Finder _chip(IncidentStatusFilter filter) =>
    find.byKey(ValueKey<String>('incident-filter-${filter.queryValue}'));

Finder _label(IncidentStatusFilter filter) =>
    find.descendant(of: _chip(filter), matching: find.text(filter.label));

/// Every request the demo journey makes, in order.
///
/// The demo's adapter is the only thing in the app that can talk to the
/// network, so recording it is what lets the fixture *prove* the rendered demo
/// never left the sample workspace instead of merely claiming it.
class RecordingDemoAdapter extends DemoAdapter {
  final List<String> requests = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add('${options.method} ${options.path}');
    return super.fetch(options, requestStream, cancelFuture);
  }
}

/// A push service that is unavailable, and says so if it is ever used.
///
/// Initializing push is what registers an FCM token (`POST
/// /api/push/devices`). The demo journey must never do that, so this throws
/// rather than swallowing the attempt: a regression fails the run instead of
/// registering a token on a beta tester's device.
class UnavailablePushService extends PushService {
  UnavailablePushService()
    : super(
        registerToken:
            ({
              required String platform,
              required String token,
              String? environment,
            }) async => throw StateError(
              'The demo journey must never register a push token '
              '(POST /api/push/devices).',
            ),
        onNavigate: (String location) {},
      );

  int initializeCalls = 0;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    throw StateError(
      'The demo journey must never initialize push: no FCM token, no remote '
      'API registration.',
    );
  }
}

/// Everything one pumped demo app needs to be observed.
class DemoRun {
  DemoRun({required this.adapter, required this.push});

  final RecordingDemoAdapter adapter;
  final UnavailablePushService push;
}

/// Pumps the real demo app with only the fixture seams described above.
///
/// The push service goes in through [UptrackDemoApp.pushService] because the
/// demo owns its provider container; an outer `ProviderScope` override would sit
/// in a container the app never reads.
///
/// Brightness and text scale are set on the platform dispatcher, which is what
/// `ThemeMode.system` and `MediaQuery` actually read: overriding them any
/// closer to the widget would have meant rebuilding the app's own theme and
/// `MaterialApp`, which is the thing under test. The viewport is a real phone
/// and is not parameterised: no run may grow the window to dodge a scroll.
Future<DemoRun> pumpDemo(
  WidgetTester tester, {
  required String initialLocation,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  PushService? pushService,
  VoidCallback? onExit,
}) async {
  final RecordingDemoAdapter adapter = RecordingDemoAdapter();
  final UnavailablePushService push = UnavailablePushService();

  // A host run has no real surface to inherit, so it is given the phone this
  // acceptance evidence is about. A device run is NOT: it keeps the surface the
  // OS reports — physical size, device pixel ratio and insets — because the
  // capture comes from that surface. Overriding it would leave the reported
  // insets describing a window that is not the one being captured (a real status
  // bar measured against a forced DPR 1 surface), which is not a viewport the
  // device can capture a frame from.
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

  await tester.pumpWidget(
    UptrackDemoApp(
      onExit: onExit ?? () {},
      initialLocation: initialLocation,
      adapter: adapter,
      pushService: pushService ?? push,
    ),
  );
  return DemoRun(adapter: adapter, push: push);
}

/// The viewport in logical pixels, whatever the surface actually is.
///
/// On the host that is the 390×844 phone this fixture declares; on the device it
/// is the device's own logical size. Every layout assertion below is expressed
/// against this rather than a hardcoded phone, so the same assertion means the
/// same thing on both surfaces.
Size logicalViewport(WidgetTester tester) =>
    tester.view.physicalSize / tester.view.devicePixelRatio;

/// The viewport facts a capture is evidence about: logical size, device pixel
/// ratio and the insets the OS reports.
///
/// Recorded with every run and every capture, because a screenshot is only
/// interpretable next to the metrics it was taken at.
String describeViewport(WidgetTester tester) {
  final double dpr = tester.view.devicePixelRatio;
  final Size logical = logicalViewport(tester);
  // `view.padding` is in physical pixels; the surface's own ratio is what
  // turns it back into the logical inset the layout sees.
  final EdgeInsets inset = EdgeInsets.fromLTRB(
    tester.view.padding.left / dpr,
    tester.view.padding.top / dpr,
    tester.view.padding.right / dpr,
    tester.view.padding.bottom / dpr,
  );
  return 'logical=${logical.width.toStringAsFixed(1)}x'
      '${logical.height.toStringAsFixed(1)} '
      'dpr=${dpr.toStringAsFixed(3)} '
      'physical=${tester.view.physicalSize.width.toStringAsFixed(0)}x'
      '${tester.view.physicalSize.height.toStringAsFixed(0)} '
      'insetTop=${inset.top.toStringAsFixed(1)} '
      'insetBottom=${inset.bottom.toStringAsFixed(1)} '
      'insetLeft=${inset.left.toStringAsFixed(1)} '
      'insetRight=${inset.right.toStringAsFixed(1)}';
}

/// A device run must be a phone-sized surface, at its own metrics.
///
/// This is the guard against the run quietly becoming something else: no tablet,
/// no desktop window, no host-sized fake surface. The numbers are the acceptance
/// evidence's subject, so they are asserted rather than assumed.
///
/// The device pixel ratio is asserted too, because it is the mistake that
/// silently produces a plausible-looking run: overriding the ratio to 1 while
/// leaving the view padding the OS reports leaves those insets measured against
/// a surface that is not the one on the glass, so a real status bar turns into
/// an implausible slab of banner padding.
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
        'a phone-width surface, not a tablet or a window: ${describeViewport(tester)}',
  );
  expect(
    logical.height,
    inInclusiveRange(640, 1000),
    reason: 'a phone-height surface: ${describeViewport(tester)}',
  );
}

/// The demo's own provider container, read from inside the rendered tree.
///
/// This is the container that resolves providers for every demo screen, so a
/// service read here is the one the journey would really use — unlike a spy
/// parked on an outer scope.
ProviderContainer demoContainer(
  WidgetTester tester,
) => ProviderScope.containerOf(
  // The demo banner is inside the demo's own MaterialApp in every demo route,
  // which makes it a stable anchor inside that container.
  tester.element(find.widgetWithText(TextButton, 'Exit demo')),
);

/// The one copy every cache fallback shares. A demo screen showing it is showing
/// what it saved, not what the sample workspace answered, and its response
/// actions are disabled because it believes it is offline.
const String kOfflineCopy = 'Offline — showing cached data';

/// Waits until [condition] holds, in real time.
///
/// No fixed sleep: [condition] is re-checked after every settle, so the run costs
/// only what the work actually took, on a loaded CI box and a slow emulator
/// alike. A wait that runs out reports [state] — a stall has to name the state it
/// stalled in, or the failure is a guess.
Future<void> awaitCondition(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
  String Function()? state,
  Duration slice = const Duration(milliseconds: 50),
  // 10s of real time per wait. Generous because an Android emulator doing the
  // demo's first Drift write and refetch is far slower than the host, and it is
  // a ceiling rather than a cost: a wait that succeeds returns immediately, and a
  // wait that runs out fails with the state it ran out on.
  int slices = 200,
}) async {
  for (int i = 0; i < slices; i++) {
    await tester.pumpAndSettle();
    if (condition()) {
      return;
    }
    await tester.pump(slice);
  }
  fail(
    'timed out after ${slices * slice.inMilliseconds}ms waiting for '
    '$description${state == null ? '' : '; last seen: ${state()}'}',
  );
}

/// Waits for the screen to reach its own loaded state: [loaded] is on screen
/// *and* no cache fallback is standing in for the sample workspace.
///
/// The demo answers through a real Dio adapter and caches into a real Drift
/// database, and under this live binding neither lands inside a bare
/// `pumpAndSettle` — the first frame after a route change is the cached one,
/// flagged offline with every response action disabled. Waiting on content alone
/// would pass on that frame, which is how a journey can reach a detail screen,
/// find no pressable Acknowledge, and still look loaded. So the wait is on the
/// state this acceptance run is actually about.
Future<void> awaitLoaded(WidgetTester tester, Finder loaded) async {
  final Finder offline = find.text(kOfflineCopy);
  await awaitCondition(
    tester,
    () => loaded.evaluate().isNotEmpty && offline.evaluate().isEmpty,
    description: 'the demo screen to load from the sample workspace',
    state: () =>
        'loaded=${loaded.evaluate().length} '
        'offlineBanners=${offline.evaluate().length} '
        'buttons=${tester.widgetList<UptrackButton>(find.byType(UptrackButton)).map((UptrackButton b) => '${b.label}=${b.onPressed != null}').toList()} '
        'texts=${tester.widgetList<Text>(find.byType(Text)).where((Text t) => t.data != null).map((Text t) => t.data).toList()}',
  );
  expect(
    loaded,
    findsWidgets,
    reason: 'the demo screen must reach its loaded state, not time out',
  );
  expect(
    find.text(kOfflineCopy),
    findsNothing,
    reason:
        'a demo screen must show what the sample workspace answered, not the '
        'cache it has not written yet',
  );
}

/// Scrolls the dashboard's own list until [section] has been built.
///
/// The dashboard is one scroll view whose sections are built lazily, so on a
/// 844dp phone the acknowledged section starts below the fold. Scrolling to it
/// is what makes asserting it a statement about a phone, not about a window
/// tall enough to hold everything at once.
///
/// [toward] is which way the section lies: `AxisDirection.down` when it is below
/// the current position (the usual case), `AxisDirection.up` to reach a section
/// that has already been scrolled past — a lazily built section above the
/// viewport cannot be reached by scrolling further down.
Future<void> revealSection(
  WidgetTester tester,
  ValueKey<String> section, {
  AxisDirection toward = AxisDirection.down,
}) async {
  final Finder list = find.descendant(
    of: find.byType(DashboardScreen),
    matching: find.byType(Scrollable),
  );
  expect(
    list,
    findsOneWidget,
    reason: 'the dashboard must stay one scroll view a phone can swipe',
  );
  // A negative dy swipes up and reveals what is below; a positive dy swipes back
  // down the list.
  await tester.dragUntilVisible(
    find.byKey(section),
    list,
    toward == AxisDirection.down ? const Offset(0, -200) : const Offset(0, 200),
  );
  await tester.pumpAndSettle();
}

/// Height a piece of text needs to be shown **in full**, measured at the exact
/// width it was given.
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
  // Nothing may be dropped: no line cap, no ellipsis.
  expect(
    painter.didExceedMaxLines,
    isFalse,
    reason: '"$label" must be shown in full, with no line cap',
  );
  return painter.height;
}

/// The top inset the banner's own `SafeArea` consumed, read where it still
/// exists.
///
/// It is read *above* the banner's `SafeArea`, never at the banner text:
/// `SafeArea` applies the inset as padding **and removes it from the
/// `MediaQuery` of the subtree it wraps**, so at the text there is nothing left
/// to read. A fixture that reads it there measures zero, leaves the whole status
/// bar counted as banner height, and then fails a correct banner for being
/// taller than the screen it is sitting on.
///
/// Read from the `MediaQuery` the `SafeArea` itself resolved, and cross-checked
/// against the inset the OS reports on the view ([FlutterView.padding] in
/// physical pixels, divided by the surface's own device pixel ratio) — so a run
/// that zeroed a real inset, or divided a real one by a device pixel ratio it
/// chose itself, fails here instead of quietly measuring a window that is not
/// the one being captured.
double bannerTopInset(WidgetTester tester) {
  final Finder message = find.text('Demo · sample data');
  // `find.ancestor` yields outermost first, so the nearest `SafeArea` above the
  // banner text is the banner's own.
  final BuildContext above = tester.element(
    find.ancestor(of: message, matching: find.byType(SafeArea)).last,
  );
  final double consumed = MediaQuery.paddingOf(above).top;
  final double reported =
      tester.view.padding.top / tester.view.devicePixelRatio;
  expect(
    consumed,
    closeTo(reported, 1),
    reason:
        "the inset the banner's SafeArea consumed must be the one the OS "
        'reports, not one this run invented: '
        '${describeViewport(tester)}',
  );
  return consumed;
}

/// The banner's own geometry, read from the render tree that was laid out.
///
/// [content] is the banner minus the status-bar inset its `SafeArea` consumed
/// ([bannerTopInset]): the height that belongs to the banner's own text and
/// action. The material rect is the status bar *plus* the banner, and a device
/// status bar is a real inset rather than a banner bug, so it is measured
/// separately and asserted to be respected ([topInset]).
typedef BannerBounds = ({
  Rect banner,
  Rect content,
  Rect message,
  Rect action,
  double topInset,
  bool stacked,
});

BannerBounds bannerBounds(WidgetTester tester) {
  final Finder message = find.text('Demo · sample data');
  final Rect banner = tester.getRect(
    find.ancestor(of: message, matching: find.byType(Material)),
  );
  // The banner sits above the demo app's own padding override, so this is the
  // inset it actually consumed — read above the `SafeArea` that consumed it.
  final double topInset = bannerTopInset(tester);
  final Rect messageRect = tester.getRect(message);
  final Rect actionRect = tester.getRect(
    find.widgetWithText(TextButton, 'Exit demo'),
  );
  return (
    banner: banner,
    content: Rect.fromLTRB(
      banner.left,
      banner.top + topInset,
      banner.right,
      banner.bottom,
    ),
    message: messageRect,
    action: actionRect,
    topInset: topInset,
    // Which layout was actually laid out: the text above the action, or beside
    // it. Decided from the rendered rects, never assumed from the text scale.
    stacked: messageRect.bottom <= actionRect.top + 0.5,
  );
}

/// Height the banner text needs at the width it was given, and the height it
/// would need on a single line.
///
/// Two different questions: the first is "is the complete text shown", the
/// second is "was it squeezed into a wrapping column" — which is the defect the
/// stacked layout exists to prevent, and which a rendered height alone cannot
/// distinguish from a deliberately wrapped paragraph.
({double shown, double oneLine}) bannerTextHeight(WidgetTester tester) {
  final Finder text = find.text('Demo · sample data');
  final BuildContext context = tester.element(text);
  final String label = tester.widget<Text>(text).data!;
  final TextStyle style = DefaultTextStyle.of(context).style
      .merge(tester.widget<Text>(text).style);
  final double width = tester.renderObject<RenderParagraph>(text).size.width;

  TextPainter painterFor({int? maxLines}) => TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: maxLines,
  )..layout(maxWidth: width);

  final TextPainter shown = painterFor();
  final TextPainter oneLine = painterFor(maxLines: 1);
  addTearDown(shown.dispose);
  addTearDown(oneLine.dispose);
  // Nothing may be dropped: no line cap, no ellipsis.
  expect(
    shown.didExceedMaxLines,
    isFalse,
    reason: '"$label" must be shown in full, with no line cap or ellipsis',
  );
  return (shown: shown.height, oneLine: oneLine.height);
}

/// Asserts the demo banner is still a banner: its own content at the top, with
/// the screen it announces underneath it, and a working way out of it.
///
/// This is the layout the acceptance evidence is about. At 200% the exit action
/// used to claim the row, squeezing the explanation into a sliver that wrapped
/// over most of the viewport — the queue and the filters below it became
/// unreachable. Every bound here is read from the laid-out render objects,
/// because "no overflow was reported" says nothing about how much room is left.
///
/// The height bound is derived from the text rather than from a fixed fraction:
/// a banner is as tall as its text plus its action. That catches a squeezed
/// explanation (which wraps into many lines and blows the bound) without
/// failing a legitimately taller font on a device whose type differs from the
/// host test font.
void expectBannerUsable(WidgetTester tester) {
  final BannerBounds bounds = bannerBounds(tester);
  final Size viewport = logicalViewport(tester);
  final ({double shown, double oneLine}) text = bannerTextHeight(tester);

  // The legitimate status bar is protected, and the geometry proves it: measured
  // from the banner's own top edge, the content starts a full inset lower. The
  // inset is a real one here or none at all — it is never zeroed to make a
  // bound easier to meet.
  expect(
    bounds.message.top,
    greaterThanOrEqualTo(bounds.banner.top + bounds.topInset - 0.5),
    reason:
        'the banner text must start a status bar inset below the banner top '
        '(inset ${bounds.topInset}px): banner ${bounds.banner}, '
        'text ${bounds.message}, ${describeViewport(tester)}',
  );
  expect(
    bounds.action.top,
    greaterThanOrEqualTo(bounds.banner.top + bounds.topInset - 0.5),
    reason:
        'the exit action must start a status bar inset below the banner top',
  );
  if (bounds.topInset > 0) {
    expect(
      bounds.banner.top,
      lessThanOrEqualTo(0.5),
      reason:
          'a surface with a status bar starts the banner at the very top edge, '
          'inset included: ${describeViewport(tester)}',
    );
    expect(
      bounds.content.top,
      closeTo(bounds.banner.top + bounds.topInset, 0.5),
      reason: 'the consumed inset is excluded from the banner content height',
    );
  }

  // Complete text, at the real text scale, with nothing dropped.
  expect(
    bounds.message.height,
    greaterThanOrEqualTo(text.shown - 0.5),
    reason: 'the banner text must be shown in full at the real text scale',
  );

  // The banner is as tall as its text plus its action — no more. Derived from
  // the text itself, so a wider device font is measured rather than guessed.
  final double allowed =
      text.shown + bounds.action.height + 24 + (bounds.stacked ? 8 : 0);
  expect(
    bounds.content.height,
    lessThanOrEqualTo(allowed),
    reason:
        'the banner is text plus its action, not more: ${bounds.content.height}px '
        'of content (status bar ${bounds.topInset}px excluded) against '
        '${allowed.toStringAsFixed(1)}px; text ${bounds.message}, '
        'action ${bounds.action}, ${describeViewport(tester)}',
  );
  // And the sanity bound it must never cross: the banner is not the screen.
  expect(
    bounds.content.height,
    lessThan(viewport.height * 0.4),
    reason: 'the banner must leave the screen its own room',
  );

  if (bounds.stacked) {
    // Stacked: the text takes the full width, the action trails below it.
    expect(
      bounds.message.bottom,
      lessThanOrEqualTo(bounds.action.top + 0.5),
      reason: 'the text sits above the action',
    );
    expect(
      bounds.message.width,
      closeTo(bounds.content.width - 32, 1),
      reason: 'the text takes the full width instead of a sliver of a column',
    );
    expect(
      bounds.action.right,
      closeTo(bounds.banner.right - 16, 1),
      reason: 'the stacked action stays trailing-aligned',
    );
  } else {
    // One row, because it fitted: the text keeps its own line rather than
    // wrapping into the sliver the stacked layout exists to avoid.
    expect(
      bounds.message.height,
      lessThanOrEqualTo(text.oneLine + 0.5),
      reason:
          'a row is only taken when the text fits on one line; it took '
          '${bounds.message.height}px against ${text.oneLine}px for one line',
    );
    expect(
      bounds.message.right,
      lessThanOrEqualTo(bounds.action.left + 1),
      reason: 'the text and the action share the row side by side',
    );
    expect(
      bounds.message.left,
      closeTo(16, 1),
      reason: 'the text starts at the banner\'s own padding',
    );
    expect(
      bounds.action.right,
      closeTo(bounds.banner.right - 16, 1),
      reason: 'the action ends at the banner\'s own padding',
    );
  }

  // Both layouts: a separate, named, 48dp exit action, fully on screen.
  expect(
    bounds.action.height,
    greaterThanOrEqualTo(48),
    reason: 'the exit action must keep a 48dp target',
  );
  expect(
    viewport.contains(bounds.action.topLeft) &&
        viewport.contains(bounds.action.bottomRight),
    isTrue,
    reason:
        'the exit action must be on screen without scrolling: ${bounds.action} '
        'in ${describeViewport(tester)}',
  );

  // Whatever the banner took, the routed screen below it still has room to
  // reach its own controls.
  expect(
    viewport.height - bounds.banner.bottom,
    greaterThan(viewport.height * 0.6),
    reason:
        'the banner must leave the screen its own room; it left '
        '${viewport.height - bounds.banner.bottom}px',
  );
}

/// Turns semantics on for this test and guarantees it goes back off.
///
/// The tear-down registration is what protects the *next* test: a body that threw
/// before it could close the handle still gets the handle closed, instead of
/// leaking a live semantics tree into whatever runs next.
SemanticsLease semanticsOn(WidgetTester tester) {
  final SemanticsLease lease = SemanticsLease._(tester.ensureSemantics());
  addTearDown(lease.dispose);
  return lease;
}

/// A semantics handle a test can close itself, without closing it twice.
///
/// Every test here closes its lease at the end of its own body (so the tree is
/// off before anything else in that test reads the rendered widgets), while the
/// tear-down registered by [semanticsOn] closes it again for the body that threw
/// first. Disposing twice must therefore be a no-op rather than a second call
/// into the binding: the assertion this supports is about semantics being on,
/// not about how many times it was switched off.
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

/// Asserts every filter chip is fully legible, on its own target, and
/// independent of the others, before anything is captured.
///
/// Read from the [RenderParagraph] the chip actually laid out, because a chip
/// that quietly truncates or ellipsises its label raises no overflow error and
/// reports no exceeded line budget.
void expectChipsUsable(WidgetTester tester) {
  for (final IncidentStatusFilter filter in IncidentStatusFilter.values) {
    final Finder text = _label(filter);
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      text,
    );
    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(fullTextHeight(tester, text) - 0.5),
      reason: 'the ${filter.label} chip must show all of its label',
    );
    expect(
      tester.renderObject<RenderBox>(_chip(filter)).size.height,
      greaterThanOrEqualTo(48),
      reason: '${filter.label} must keep a 48dp target at 200%',
    );
  }
}

/// The chips occupy more than one row: the filters wrap rather than being
/// squeezed onto a single line that cannot hold them.
void expectChipsWrap(WidgetTester tester) {
  final Set<double> rows = <double>{
    for (final IncidentStatusFilter filter in IncidentStatusFilter.values)
      tester.getTopLeft(_chip(filter)).dy,
  };
  expect(
    rows.length,
    greaterThan(1),
    reason: 'the filters must wrap onto more than one row at 200%',
  );
}

/// Selected state, read from the semantics tree by label: the promise under
/// test is the one the user experiences ("this control is the selected one"),
/// not the widget that implements it.
bool chipReadsAsSelected(WidgetTester tester, IncidentStatusFilter filter) =>
    tester
        .getSemantics(find.bySemanticsLabel(filter.label))
        .flagsCollection
        .isSelected ==
    Tristate.isTrue;

/// Asserts a node is a button a tap can actually reach, on the node the user
/// operates rather than on some wrapper that repeats the label.
void expectTappableNode(WidgetTester tester, String label) {
  final SemanticsNode node = tester.getSemantics(find.bySemanticsLabel(label));
  expect(node.label, label, reason: 'the node must carry its own label');
  expect(
    node.flagsCollection.isButton,
    isTrue,
    reason: '"$label" must be announced as a button',
  );
  expect(
    node.getSemanticsData().hasAction(SemanticsAction.tap),
    isTrue,
    reason: '"$label" must be reachable by a tap',
  );
}

/// Asserts a section heading is announced as a heading and offers nothing to
/// tap.
///
/// A section heading is not a control: it must not claim a tap, and it must not
/// swallow the rows below it into one node. The heading may legitimately share
/// its node with the section's own explanation — a heading and what it is
/// heading are read together — so the node is found by the heading it starts
/// with rather than by an exact whole-label match.
void expectPlainHeading(WidgetTester tester, String heading) {
  final Iterable<SemanticsNode> headings = find.semantics
      .byLabel(RegExp('^${RegExp.escape(heading)}'))
      .evaluate();
  expect(
    headings,
    hasLength(1),
    reason: 'exactly one node announces the "$heading" heading',
  );
  final SemanticsNode node = headings.single;
  expect(node.label, startsWith(heading));
  expect(
    node.flagsCollection.isHeader,
    isTrue,
    reason: '"$heading" must be announced as a heading',
  );
  expect(
    node.getSemanticsData().hasAction(SemanticsAction.tap),
    isFalse,
    reason: '"$heading" is a heading, not a control',
  );
  expect(
    node.flagsCollection.isButton,
    isFalse,
    reason: '"$heading" must not claim a button role',
  );
}

/// Asserts explanatory copy is announced as itself: plain text, with no tap and
/// no button role.
///
/// A section's hint may legitimately share a node with the heading it explains
/// — a heading and its explanation are read together — so this asserts what must
/// hold *wherever* the copy lands instead of demanding a node of its own: the
/// copy is on screen in full, and the node announcing it is not a control. What
/// it never tolerates is the copy joining an incident row's tap label, because
/// [expectTappableNode] matches those labels exactly.
void expectNonActionableCopy(WidgetTester tester, String text) {
  expect(
    find.text(text),
    findsWidgets,
    reason: 'the section must still explain itself: "$text"',
  );

  // A node whose label *ends* with the copy: on its own, or appended to the
  // heading it explains. `evaluate()` is what returns the matching nodes —
  // `allCandidates` hands back the whole tree, matched or not.
  final Iterable<SemanticsNode> announcing = find.semantics
      .byLabel(RegExp('${RegExp.escape(text)}\$'))
      .evaluate();
  expect(
    announcing,
    isNotEmpty,
    reason:
        'the copy must reach the semantics tree, as itself or with its '
        'heading',
  );

  for (final SemanticsNode node in announcing) {
    expect(
      node.flagsCollection.isButton,
      isFalse,
      reason: '"${node.label}" is explanation, not a control',
    );
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
      reason: '"${node.label}" must not offer a tap',
    );
  }
}

/// Whether *this test* has already converted the Flutter surface to an image.
///
/// Test-scoped, and reset in tear-down, because that is exactly the scope the
/// platform callback manager keeps it in: `convertFlutterSurfaceToImage` sets
/// the flag and registers the revert as a tear-down, so a second conversion
/// inside the same test asserts (`Surface already converted to an image`) and
/// leaves the revert asserting on its way out too. Clearing it per test rather
/// than per capture is what lets one journey take several screenshots.
bool _surfaceConverted = false;

/// How long each capture stage may take before the run calls it a failure.
///
/// The capture is a platform round trip that asks the driver side to schedule a
/// frame and hand back a bitmap. Left unbounded, a surface that never delivers
/// that frame hangs the whole run: the journey stops mid-way, no PNG is written,
/// and the log says only that a test "did not complete". Bounded, the same stall
/// is a named failure that says which stage stopped and what the surface looked
/// like when it did.
const Duration _captureStageTimeout = Duration(seconds: 60);

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
    await binding.convertFlutterSurfaceToImage().timeout(_captureStageTimeout);
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

/// Writes a PNG into the app cache, the same plumbing the store-screenshot
/// fixture uses.
///
/// Exactly one condition is skippable, and only outside Android: on the host the
/// integration binding's screenshot channel has no implementation, so the
/// conversion reports a [MissingPluginException]. Every other failure — the
/// conversion, the capture, the conversion of the captured frame, or the write —
/// fails the run, and on Android even the missing-plugin case fails, because a
/// device run that captured nothing is not evidence.
///
/// Every stage prints before it starts and is bounded, so a run that stalls
/// names the stage it stalled in instead of ending as "did not complete".
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

  // Device run: no catch. Anything that goes wrong here fails the run, and every
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

  debugPrint('CAPTURE_STAGE $name writing ${bytes.length} bytes');
  final Directory dir = Directory(
    '${Directory.systemTemp.path}/uptrack_screenshots',
  );
  await dir.create(recursive: true);
  final File file = File('${dir.path}/$name.png');
  await file.writeAsBytes(bytes, flush: true);
  expect(
    file.existsSync(),
    isTrue,
    reason: '$name must exist in the app cache for the host to pull it',
  );
  expect(
    await file.length(),
    bytes.length,
    reason: '$name must be written whole',
  );
  debugPrint(
    'SCREENSHOT_SAVED $name ${bytes.length} ${file.path} '
    '${describeViewport(tester)}',
  );
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('demo container boundary', () {
    testWidgets('the demo resolves the observed push service and no live api', (
      WidgetTester tester,
    ) async {
      final DemoRun run = await pumpDemo(tester, initialLocation: '/');
      await awaitLoaded(tester, find.byKey(kNeedsAckSection));
      await revealSection(tester, kNeedsAckSection);

      final ProviderContainer container = demoContainer(tester);
      expect(
        container.read(pushServiceProvider),
        same(run.push),
        reason:
            'the spy must be the service this container resolves; an override '
            'that the demo never reads would assert nothing',
      );
      // The initializer/registration boundary: initializing push is what
      // registers an FCM token, and the demo must never cross it.
      expect(
        run.push.initializeCalls,
        0,
        reason: 'the demo journey must never initialize push',
      );
      expect(
        run.push.isInitialized,
        isFalse,
        reason: 'the push service the demo resolved must stay uninitialized',
      );
      expect(
        run.adapter.requests.where((String r) => r.contains('push')),
        isEmpty,
        reason: 'no push registration may be attempted in the demo',
      );
      // Requests are bound to the sample adapter: no live fallback anywhere.
      expect(
        container.read(dioProvider).httpClientAdapter,
        same(run.adapter),
        reason: 'the demo container must serve every request from the sample',
      );
      expect(
        run.adapter.requests,
        isNotEmpty,
        reason: 'a loaded dashboard must have read the sample workspace',
      );
      expect(run.adapter.requests, everyElement(startsWith('GET ')));
    }, timeout: const Timeout(Duration(minutes: 5)));

    testWidgets(
      'the production demo entry point keeps the default push service',
      (WidgetTester tester) async {
        await tester.pumpWidget(DemoSessionScreen(onExit: () {}));
        await awaitLoaded(tester, find.byKey(kNeedsAckSection));

        expect(
          tester
              .widget<UptrackDemoApp>(find.byType(UptrackDemoApp))
              .pushService,
          isNull,
          reason: 'the shipping demo must not need the fixture seam at all',
        );
        final PushService service = demoContainer(tester)
            .read(pushServiceProvider);
        expect(
          service,
          isNot(isA<UnavailablePushService>()),
          reason:
              'the seam is for tests only; production keeps its own provider',
        );
        expect(
          service.isInitialized,
          isFalse,
          reason: 'a demo session must not initialize push either',
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });

  group('demo banner on a phone', () {
    for (final (String name, Brightness brightness) in <(String, Brightness)>[
      ('light', Brightness.light),
      ('dark', Brightness.dark),
    ]) {
      testWidgets(
        '$name at 200% keeps its full text, its way out, and the screen below',
        (WidgetTester tester) async {
          final SemanticsLease semantics = semanticsOn(tester);
          int exits = 0;
          final DemoRun run = await pumpDemo(
            tester,
            initialLocation: '/incidents?filter=needs-acknowledgement',
            brightness: brightness,
            textScale: 2,
            onExit: () => exits += 1,
          );
          await awaitLoaded(
            tester,
            _chip(IncidentStatusFilter.needsAcknowledgement),
          );
          expect(tester.takeException(), isNull, reason: 'no overflow at 200%');

          expectBannerUsable(tester);

          // The copy and the action are two nodes, not one merged banner blob.
          expectTappableNode(tester, 'Exit demo');
          expectNonActionableCopy(tester, 'Demo · sample data');

          // The filters the banner announces are on the same phone screen,
          // inside the banner's reach, not pushed off the bottom of it.
          final Finder selected = _chip(
            IncidentStatusFilter.needsAcknowledgement,
          );
          final Rect selectedRect = tester.getRect(selected);
          final BannerBounds banner = bannerBounds(tester);
          expect(
            logicalViewport(tester).contains(selectedRect.topLeft),
            isTrue,
            reason:
                'the selected filter must stay visible below the banner '
                '(banner bottom ${banner.banner.bottom}, chip at '
                '$selectedRect, ${describeViewport(tester)})',
          );

          await capture(tester, binding, 'demo-r2-banner-$name-200');

          // And the way out still works at this text scale.
          await tester.tap(find.widgetWithText(TextButton, 'Exit demo'));
          await tester.pump();
          expect(
            exits,
            1,
            reason: 'the exit action must still leave the demo session',
          );
          expect(run.push.initializeCalls, 0);
          semantics.dispose();
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    }

    testWidgets('normal text keeps the banner to a single text line', (
      WidgetTester tester,
    ) async {
      await pumpDemo(tester, initialLocation: '/');
      await awaitLoaded(tester, find.byKey(kNeedsAckSection));

      expect(tester.takeException(), isNull);
      expectBannerUsable(tester);
      expect(
        bannerBounds(tester).content.height,
        lessThanOrEqualTo(96),
        reason:
            'at normal text the banner is one line plus its action, with the '
            'status bar it is not allowed to swallow excluded',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('demo response journey', () {
    testWidgets('dashboard → detail → acknowledge → return moves the incident out of the '
        'response queue', (WidgetTester tester) async {
      final SemanticsLease semantics = semanticsOn(tester);
      final DemoRun run = await pumpDemo(tester, initialLocation: '/');
      // Loaded state is the queue section itself: it exists only once the
      // dashboard holds the sample workspace's data, not merely once the route
      // is on screen.
      await awaitLoaded(tester, find.byKey(kNeedsAckSection));

      final Finder needsAck = find.byKey(kNeedsAckSection);
      final Finder acknowledged = find.byKey(kAcknowledgedSection);

      // -- the attention queue, as it starts ------------------------------
      await revealSection(tester, kNeedsAckSection);
      expect(
        find.descendant(of: needsAck, matching: find.text(kResponder)),
        findsOneWidget,
        reason: 'the demo starts with an unacknowledged open incident',
      );
      expect(
        find.descendant(of: needsAck, matching: find.text(kOlderOutstanding)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: needsAck,
          matching: find.text(kAlreadyAcknowledged),
        ),
        findsNothing,
        reason: 'an incident with an acknowledgement is not waiting on anyone',
      );
      await capture(tester, binding, 'demo-r2-dashboard-queue-before');

      // -- dashboard → detail ---------------------------------------------
      final Finder row = find.descendant(
        of: needsAck,
        matching: find.text(kResponder),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      // The detail's loaded state is its Response section, reached with the
      // sample workspace's answer rather than the cache it starts from.
      await awaitLoaded(
        tester,
        find.widgetWithText(UptrackButton, 'Acknowledge'),
      );
      expect(find.byType(IncidentDetailScreen), findsOneWidget);
      expect(find.text(kResponder), findsWidgets);
      final Finder acknowledge = find.widgetWithText(
        UptrackButton,
        'Acknowledge',
      );
      expect(
        tester.widget<UptrackButton>(acknowledge).onPressed,
        isNotNull,
        reason: 'an unacknowledged incident must offer the action',
      );
      await tester.ensureVisible(acknowledge);
      await tester.pumpAndSettle();
      await capture(tester, binding, 'demo-r2-detail-before-ack');

      // -- detail → acknowledge -------------------------------------------
      await tester.tap(acknowledge);
      // The mutation is a real request the sample workspace answers and then
      // caches, so the recorded answer is awaited rather than assumed: the
      // control is disabled when the answer arrives, not when the tap returns.
      await awaitCondition(
        tester,
        () =>
            acknowledge.evaluate().isNotEmpty &&
            tester.widget<UptrackButton>(acknowledge).onPressed == null,
        description: 'the sample workspace to record the acknowledgement',
        state: () =>
            'requests=${run.adapter.requests} '
            'buttons=${tester.widgetList<UptrackButton>(find.byType(UptrackButton)).map((UptrackButton b) => '${b.label}=${b.onPressed != null}').toList()}',
      );

      // The control stays on screen, disabled: the acknowledgement is
      // recorded state, not a control that disappears and takes its
      // explanation with it.
      expect(
        acknowledge,
        findsOneWidget,
        reason: 'the disabled action must stay visible with its reason',
      );
      expect(
        tester.widget<UptrackButton>(acknowledge).onPressed,
        isNull,
        reason:
            'the action must be disabled once the incident is acknowledged, '
            'rather than left pressable a second time',
      );
      expect(
        find.widgetWithText(Chip, 'Acknowledged'),
        findsOneWidget,
        reason: 'the header must report the status that was recorded',
      );
      expect(
        find.text('Acknowledged. Escalation is paused.'),
        findsOneWidget,
        reason: 'the outcome must be reported from the server-shaped answer',
      );
      expect(
        find.text('Escalation is a no-op once an incident is acknowledged.'),
        findsOneWidget,
        reason: 'a disabled control states why it is disabled',
      );
      // The same three facts in the accessible tree, on the actionable node.
      final SemanticsNode ackNode = tester.getSemantics(
        find.bySemanticsLabel(kAcknowledgeLabel),
      );
      expect(ackNode.flagsCollection.isButton, isTrue);
      expect(ackNode.flagsCollection.isEnabled, Tristate.isFalse);
      expect(
        ackNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      expect(
        find.bySemanticsLabel('Incident $kResponder, Open, acknowledged'),
        findsOneWidget,
        reason: 'the recorded status must reach the header semantics node',
      );
      expect(
        run.adapter.requests,
        contains(endsWith('/acknowledge')),
        reason: 'the acknowledgement must be answered by the sample workspace',
      );
      await capture(tester, binding, 'demo-r2-detail-after-ack');

      // -- detail → back ----------------------------------------------------
      // The dashboard row navigates with `go` into the incidents branch, so
      // Back lands on that branch's feed. Asserting the feed is the honest
      // description of the real route; the dashboard is reached again through
      // the navigation a user would use.
      await tester.tap(find.byType(BackButton));
      await awaitLoaded(tester, _chip(IncidentStatusFilter.all));
      expect(
        find.byKey(kNeedsAckSection),
        findsNothing,
        reason: 'back must not pretend the dashboard was restored',
      );
      expect(find.text('Incidents'), findsWidgets);
      expect(_chip(IncidentStatusFilter.all), findsOneWidget);
      await capture(tester, binding, 'demo-r2-feed-after-return');

      // -- feed → dashboard, through the real navigation -------------------
      await tester.tap(find.byKey(kDashboardDestination));
      await awaitLoaded(tester, find.byKey(kNeedsAckSection));
      await revealSection(tester, kNeedsAckSection);
      expect(
        find.descendant(of: needsAck, matching: find.text(kResponder)),
        findsNothing,
        reason: 'an acknowledged incident must leave the response queue',
      );
      await revealSection(tester, kAcknowledgedSection);
      expect(
        find.descendant(of: acknowledged, matching: find.text(kResponder)),
        findsOneWidget,
        reason: 'it must appear in the acknowledged open section instead',
      );
      expect(
        find.descendant(
          of: acknowledged,
          matching: find.text(kAlreadyAcknowledged),
        ),
        findsOneWidget,
        reason: 'the acknowledged section keeps the incident already on record',
      );
      // The dashboard builds its sections lazily, so the needs-acknowledgement
      // section has to be scrolled back into view before it can be asserted on
      // again — after acknowledging one incident it must still hold the other.
      await revealSection(tester, kNeedsAckSection, toward: AxisDirection.up);
      expect(
        find.descendant(of: needsAck, matching: find.text(kOlderOutstanding)),
        findsOneWidget,
        reason: 'acknowledging one incident must not touch the others',
      );
      await capture(tester, binding, 'demo-r2-dashboard-queue-after');

      // -- the sample workspace answered all of it --------------------------
      expect(run.push.initializeCalls, 0);
      expect(
        run.adapter.requests.where((String r) => r.contains('push')),
        isEmpty,
      );
      expect(
        run.adapter.requests,
        everyElement(anyOf(startsWith('GET '), endsWith('/acknowledge'))),
        reason:
            'the journey only reads the sample workspace and acknowledges one '
            'incident: requests were ${run.adapter.requests}',
      );
      semantics.dispose();
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('dashboard section semantics', () {
    testWidgets('a one-row section announces one tappable incident node', (
      WidgetTester tester,
    ) async {
      final SemanticsLease semantics = semanticsOn(tester);
      await pumpDemo(tester, initialLocation: '/');
      await awaitLoaded(tester, find.byKey(kNeedsAckSection));

      final Finder section = find.byKey(kAcknowledgedSection);
      await revealSection(tester, kAcknowledgedSection);

      // Singular heading wording, announced as a heading and as nothing else.
      expectPlainHeading(tester, 'Acknowledged open incidents, 1 incident');
      expectNonActionableCopy(
        tester,
        'Still open. The acknowledgement is on record, and does not assign '
        'anyone.',
      );
      // Exactly one node per row: the row is its own target, carrying its own
      // label and no part of the section's copy.
      expect(
        find.descendant(
          of: section,
          matching: find.bySemanticsLabel(RegExp('^Incident ')),
        ),
        findsOneWidget,
      );
      expectTappableNode(
        tester,
        'Incident $kAlreadyAcknowledged, status Open, acknowledged',
      );
      semantics.dispose();
    }, timeout: const Timeout(Duration(minutes: 5)));

    testWidgets('a multi-row section gives every incident its own tap node', (
      WidgetTester tester,
    ) async {
      final SemanticsLease semantics = semanticsOn(tester);
      await pumpDemo(tester, initialLocation: '/');
      await awaitLoaded(tester, find.byKey(kNeedsAckSection));

      final Finder section = find.byKey(kNeedsAckSection);
      await revealSection(tester, kNeedsAckSection);

      expectPlainHeading(tester, 'Needs acknowledgement, 2 incidents');
      expectNonActionableCopy(
        tester,
        'Open, not yet acknowledged, oldest first.',
      );
      // Two rows, two nodes: neither row's label may absorb the other row, the
      // heading, or the hint.
      expect(
        find.descendant(
          of: section,
          matching: find.bySemanticsLabel(RegExp('^Incident ')),
        ),
        findsNWidgets(2),
        reason: 'each incident row needs its own node',
      );
      expectTappableNode(tester, 'Incident $kResponder, status Open');
      expectTappableNode(tester, 'Incident $kOlderOutstanding, status Open');
      semantics.dispose();
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('filter chips rendered on a phone', () {
    for (final (String name, Brightness brightness) in <(String, Brightness)>[
      ('light', Brightness.light),
      ('dark', Brightness.dark),
    ]) {
      testWidgets('$name at 200% with Needs acknowledgement selected', (
        WidgetTester tester,
      ) async {
        final SemanticsLease semantics = semanticsOn(tester);
        final DemoRun run = await pumpDemo(
          tester,
          // The deep link the dashboard's own "view all" link uses, so the
          // capture is the route a user reaches, not a private one.
          initialLocation: '/incidents?filter=needs-acknowledgement',
          brightness: brightness,
          textScale: 2,
        );
        await awaitLoaded(
          tester,
          _chip(IncidentStatusFilter.needsAcknowledgement),
        );

        expect(tester.takeException(), isNull, reason: 'no overflow at 200%');
        expect(find.byType(IncidentsScreen), findsOneWidget);

        // The capture is a phone screen: the navigation is on it, next to the
        // filters, and reachable.
        expect(find.byKey(kDashboardDestination), findsOneWidget);
        expect(find.byKey(kIncidentsDestination), findsOneWidget);

        // The selected state is the one being captured.
        expect(
          chipReadsAsSelected(
            tester,
            IncidentStatusFilter.needsAcknowledgement,
          ),
          isTrue,
        );
        expect(chipReadsAsSelected(tester, IncidentStatusFilter.all), isFalse);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Needs acknowledgement'))
              .flagsCollection
              .isButton,
          isTrue,
          reason: 'the selected chip is still a button, not just a label',
        );

        // Every label in full, every target 48dp, the row wrapping.
        expectChipsUsable(tester);
        expectChipsWrap(tester);

        // Each chip is tapped on its own, in both directions, and each tap
        // moves the selection: the chips are independent controls, not one
        // segmented row that moves as a unit.
        await tester.tap(_chip(IncidentStatusFilter.open));
        await tester.pumpAndSettle();
        expect(chipReadsAsSelected(tester, IncidentStatusFilter.open), isTrue);
        expect(
          chipReadsAsSelected(
            tester,
            IncidentStatusFilter.needsAcknowledgement,
          ),
          isFalse,
        );
        await tester.tap(_chip(IncidentStatusFilter.needsAcknowledgement));
        await tester.pumpAndSettle();
        expect(
          chipReadsAsSelected(
            tester,
            IncidentStatusFilter.needsAcknowledgement,
          ),
          isTrue,
        );
        expectChipsUsable(tester);

        await capture(tester, binding, 'demo-r2-chips-$name-200-needs-ack');
        expect(run.push.initializeCalls, 0);
        semantics.dispose();
      }, timeout: const Timeout(Duration(minutes: 5)));
    }
  });
}
