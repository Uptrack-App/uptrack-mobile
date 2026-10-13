import 'dart:async';

/// Refreshes the two "live" surfaces outside the app — the home-screen
/// widget and the incident Live Activities — after the incident cache
/// changes or the app returns to the foreground.
///
/// Before this, the widget only refreshed on a foreground push, so a sync in
/// the app (or a resolve seen in the feed) did not reach the home screen
/// until the next push.
///
/// Runs never overlap: a trigger during a run schedules exactly one more run.
/// Failures are swallowed; these surfaces are best-effort.
class LiveSurfaceSync {
  LiveSurfaceSync({
    required this.refreshWidget,
    required this.reconcileActivities,
  });

  final Future<void> Function() refreshWidget;
  final Future<void> Function() reconcileActivities;

  Future<void>? _running;
  bool _again = false;
  StreamSubscription<void>? _subscription;

  /// Runs once now, or once more after the current run.
  Future<void> run() {
    final Future<void>? running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final Future<void> next = _loop();
    _running = next;
    return next;
  }

  Future<void> _loop() async {
    try {
      do {
        _again = false;
        await _guard(refreshWidget);
        await _guard(reconcileActivities);
      } while (_again);
    } finally {
      _running = null;
    }
  }

  /// Runs on every event of [trigger] until [dispose].
  void attach(Stream<void> trigger) {
    unawaited(_subscription?.cancel());
    _subscription = trigger.listen((_) => unawaited(run()));
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  static Future<void> _guard(Future<void> Function() call) async {
    try {
      await call();
    } on Object {
      // Best-effort.
    }
  }
}
