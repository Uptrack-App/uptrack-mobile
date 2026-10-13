import '../widgets/widget_store.dart';
import 'push_message.dart';
import 'push_service.dart';

/// Dart-side handling of FCM **data-only** messages (T056, Android).
///
/// The server sends FCM v1 payloads with a `notification` block (rendered by
/// the OS) plus a `data` block (`incident_id`, `monitor_name`, `severity`,
/// collapse key = `tag` = incident id — see `build_fcm_payload` in
/// `crates/api/src/push_fcm.rs`). Data-only payloads reach Dart over the
/// T027 `push/events` channel (`onForegroundMessage`) or this handler
/// directly; the handler refreshes the home widget (best-effort, via the
/// Drift cache + push merge in [WidgetRefresher]) and re-displays the alert
/// locally so repeat pushes for one incident collapse onto the live
/// notification ([PushMessage.notificationId] is stable per incident).
///
/// The native `UptrackDataMessageReceiver` mirrors the same collapse rules
/// (tag = incident id) for messages arriving while the engine is down.
class FcmDataHandler {
  FcmDataHandler({required this.notifier, required this.refresher});

  final LocalNotifier notifier;
  final WidgetRefresher refresher;

  /// Handles one FCM data payload; returns the parsed message, or null when
  /// the payload names no incident/monitor (nothing actionable).
  Future<PushMessage?> handle(Map<Object?, Object?>? data) async {
    final PushMessage? message = PushMessage.fromMap(data);
    if (message == null ||
        (message.incidentId == null && message.monitorId == null)) {
      return null;
    }
    await refresher.applyPush(message);
    // iOS `willPresent` already presented it with the server's interruption
    // level; a local copy would double the banner (plan 4.5).
    if (!message.presentedByOs) {
      await notifier.showForeground(message);
    }
    return message;
  }
}
