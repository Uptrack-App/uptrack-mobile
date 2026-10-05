import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Method-channel contract between the native hosts (Swift APNs registration
/// lands in T028; Android FCM likewise) and the Dart push layer.
///
/// The native side *calls into* Dart on [events]; Dart *queries* the native
/// side on [token]. No Swift/Kotlin code is written here — these constants
/// are the interface T028 will implement against.
abstract final class PushChannels {
  /// Swift/Kotlin → Dart: token events, foreground messages, tap callbacks.
  static const String events = 'app.uptrack.mobile/push/events';

  /// Dart → Swift/Kotlin: current-token queries and cold-start state.
  static const String token = 'app.uptrack.mobile/push/token';

  /// The default [MethodChannel]s backing [PushService].
  static MethodChannel eventsChannel() =>
      const MethodChannel(PushChannels.events);

  /// The default [MethodChannel]s backing [PushService].
  static MethodChannel tokenChannel() =>
      const MethodChannel(PushChannels.token);
}

/// Method names on [PushChannels.events] (native → Dart).
abstract final class PushEventMethods {
  /// Fresh APNs/FCM token: `{token, platform, environment?}`.
  static const String onPushToken = 'onPushToken';

  /// Rotated APNs/FCM token: `{token}` (platform/environment unchanged).
  static const String onTokenRefresh = 'onTokenRefresh';

  /// Alert payload while the app is foregrounded:
  /// `{title?, body?, incident_id?, monitor_id?, severity?, collapse_key?}`.
  static const String onForegroundMessage = 'onForegroundMessage';

  /// User tapped a notification (background state):
  /// `{incident_id?, monitor_id?}`.
  static const String onNotificationTap = 'onNotificationTap';

  /// User tapped a lock-screen triage action (any app state):
  /// `{action, incident_id?, monitor_id?}` where `action` is one of
  /// `acknowledge`/`escalate`/`snooze` (or the native `UPTRACK_ACK`,
  /// `UPTRACK_ESCALATE`, `UPTRACK_SNOOZE` ids the T028 hosts send).
  static const String onNotificationAction = 'onNotificationAction';

  /// ActivityKit push-to-start token (iOS 17.2+, T055):
  /// `{token, kind?, incident_id?, expires_in_seconds?}` where `kind`
  /// defaults to `push_to_start`. The native host sends no `incident_id`
  /// (the token bootstraps remotely-started activities before any incident
  /// exists); Dart registers immediately when scoped, otherwise parks the
  /// token until the next incident push arrives.
  static const String onLiveActivityToken = 'onLiveActivityToken';
}

/// Method names on [PushChannels.token] (Dart → native).
abstract final class PushTokenMethods {
  /// Returns the current push token (`{token, platform, environment?}`),
  /// or null when push is unavailable/denied.
  static const String getToken = 'getToken';

  /// Notification that cold-started the app (`{incident_id?, monitor_id?}`),
  /// or null for a normal launch.
  static const String getInitialNotification = 'getInitialNotification';
}

/// Android notification **channel** ids (R3).
///
/// One channel per severity so the *user* — not the app — owns how loud an
/// alert is from the second notification onward. Android ignores importance
/// changes on a channel that already exists and never lets an app lower a
/// channel below what the user picked, so a single shared channel (the
/// pre-R3 `uptrack_alerts` / `incidents` pair) can only ever offer the first
/// importance the app happened to pick. Four separate ids are the only way to
/// offer high/default/low *without ever mutating a setting a user owns*.
///
/// The ids are shared byte-for-byte with `UptrackNotificationChannels.kt`
/// (same package); `test/push/r3_notification_contract_test.dart` fails on
/// any drift between the two.
abstract final class PushChannelIds {
  /// P1 — high importance.
  static const String p1 = 'uptrack_p1';

  /// P2 — default importance.
  static const String p2 = 'uptrack_p2';

  /// P3 — low importance.
  static const String p3 = 'uptrack_p3';

  /// Fallback for `info` **and** for every unknown/absent/unparseable
  /// severity.
  ///
  /// Deliberately the pre-existing, server-advertised channel
  /// (`INCIDENTS_CHANNEL_ID` in `crates/api/src/push_fcm.rs`) so an FCM
  /// `notification`-block alert for an unrecognised severity still lands on a
  /// channel the app already publishes, and so that channel's importance stays
  /// whatever the user already chose for it (Android ignores a change there
  /// anyway, and deleting the channel would discard their setting).
  static const String fallback = 'incidents';

  /// Every id this app publishes, in declaration order. Channel lifecycle
  /// (create-if-missing, never delete) iterates this list.
  static const List<String> all = <String>[p1, p2, p3, fallback];
}

/// How loud one channel is allowed to be *at creation time*.
///
/// Deliberately not `flutter_local_notifications`' `Importance`: the renderer
/// maps this enum onto the plugin's enum, and the contract test maps it onto
/// the `NotificationManager.IMPORTANCE_*` constants in Kotlin — so this file
/// keeps no Android-specific import and stays iOS-compatible.
enum PushChannelImportance { high, standard, low }

/// One immutable per-severity channel definition, shared Dart ↔ native.
@immutable
class PushChannelSpec {
  const PushChannelSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.importance,
  });

  /// A [PushChannelIds] value.
  final String id;

  /// User-visible channel name (Android Settings → app notifications).
  final String name;

  /// User-visible channel description.
  final String description;

  /// Importance requested **only when the channel does not exist yet**.
  /// An existing channel keeps whatever the user set (immutable).
  final PushChannelImportance importance;

  @override
  String toString() => 'PushChannelSpec($id, ${importance.name})';
}

/// Deterministic severity → channel mapping (R3), shared Dart ↔ native.
///
/// This is the whole of the per-severity contract: one pure function of the
/// raw `severity` string, identical in the Dart foreground renderer and in the
/// Kotlin background receiver. There is no second opinion anywhere.
abstract final class PushSeverityChannels {
  /// Severities that map to their own channel. `info` is a real server
  /// severity but is deliberately *not* here: it shares the fallback channel.
  static const Set<String> mappedSeverities = <String>{'p1', 'p2', 'p3'};

  /// Every per-severity channel definition, keyed by its [PushChannelIds] id.
  ///
  /// `uptrack_alerts` (the pre-R3 Dart channel) is intentionally **not**
  /// republished: it may already carry a user-owned importance, and dropping
  /// it would silently discard their choice. It is left in place, unused.
  static const Map<String, PushChannelSpec> specs = <String, PushChannelSpec>{
    PushChannelIds.p1: PushChannelSpec(
      id: PushChannelIds.p1,
      name: 'P1 critical alerts',
      description: 'Critical incidents. Importance set by you in Settings.',
      importance: PushChannelImportance.high,
    ),
    PushChannelIds.p2: PushChannelSpec(
      id: PushChannelIds.p2,
      name: 'P2 major alerts',
      description: 'Major incidents. Importance set by you in Settings.',
      importance: PushChannelImportance.standard,
    ),
    PushChannelIds.p3: PushChannelSpec(
      id: PushChannelIds.p3,
      name: 'P3 minor alerts',
      description: 'Minor incidents. Importance set by you in Settings.',
      importance: PushChannelImportance.low,
    ),
    PushChannelIds.fallback: PushChannelSpec(
      id: PushChannelIds.fallback,
      name: 'Incident alerts',
      description: 'Incident and monitor alerts from Uptrack.',
      importance: PushChannelImportance.standard,
    ),
  };

  /// Normalised severity string, or null when this build maps no channel for
  /// it.
  ///
  /// Trimmed and lower-cased so `' P1 '` and `'p1'` cannot disagree between
  /// Dart and Kotlin. Anything outside [mappedSeverities] (including `info`,
  /// `p4`, an empty string, or a non-string payload value) normalises to null
  /// — which is the *fallback* channel, never an error and never a crash.
  static String? normalize(Object? severity) {
    if (severity is! String) {
      return null;
    }
    final String trimmed = severity.trim().toLowerCase();
    return mappedSeverities.contains(trimmed) ? trimmed : null;
  }

  /// Channel id for a raw `severity`; deterministic, never throws.
  static String idFor(String? severity) {
    return switch (normalize(severity)) {
      'p1' => PushChannelIds.p1,
      'p2' => PushChannelIds.p2,
      'p3' => PushChannelIds.p3,
      // `info`, unknown, empty, missing — all one fallback channel.
      _ => PushChannelIds.fallback,
    };
  }

  /// Full channel definition for a raw `severity`.
  static PushChannelSpec specFor(String? severity) => specs[idFor(severity)]!;

  /// True when [severity] maps to its own channel (false = fallback bucket).
  static bool isMapped(String? severity) => normalize(severity) != null;
}

/// Which entity a notification — or an action on it — targets.
///
/// Incident wins over monitor, exactly like `PushMessage.routeLocation`: a
/// payload naming both is an incident alert, so Ack/Escalate apply and Snooze
/// resolves its monitor server-side (see `PushActionHandler`).
enum PushTargetKind {
  incident,
  monitor;

  /// Stable lowercase name used in the intent data URI on both sides.
  String get wire => name;
}

/// PendingIntent identity + minimal payload contract (R3).
///
/// Android decides that two `PendingIntent`s are the *same* intent from the
/// request code plus the intent's filter components (action, data, type,
/// categories, component) — **extras are not part of identity**. So one shared
/// action carrying per-incident extras would make every incident's Ack button
/// fire whichever incident happened to create the intent first. Every intent
/// here therefore carries a distinct `action` *and* a distinct `data` URI that
/// spells out its own identity; the request code is derived from that same
/// identity string only to spread the ints, and is never the identity itself.
abstract final class PushIntentIdentity {
  /// `android.intent.action.MAIN` — the body-tap action, unchanged from
  /// pre-R3 so a body tap still looks like a launcher launch to the OS.
  static const String tapAction = 'android.intent.action.MAIN';

  /// Per-action `Intent` actions. Distinct actions are what keep an action
  /// tap from ever being mistaken for a body tap.
  static const String acknowledgeAction = 'app.uptrack.mobile.UPTRACK_ACK';
  static const String escalateAction = 'app.uptrack.mobile.UPTRACK_ESCALATE';
  static const String snoozeAction = 'app.uptrack.mobile.UPTRACK_SNOOZE';

  /// Payload values for the `action` field. These are the ids the backend
  /// already advertises under the `UPTRACK_INCIDENT` category and the ids
  /// `PushAction.parse` already accepts, so nothing new has to be learned.
  static const String acknowledge = 'UPTRACK_ACK';
  static const String escalate = 'UPTRACK_ESCALATE';
  static const String snooze = 'UPTRACK_SNOOZE';

  /// Every action id, in presentation order.
  static const List<String> actionIds = <String>[acknowledge, escalate, snooze];

  /// Scheme of every notification data URI (`uptrack://push/...`).
  static const String dataScheme = 'uptrack';

  /// Extra keys for an action intent — all namespaced under `uptrack_` so
  /// they can never collide with the body-tap extras (`incident_id` /
  /// `monitor_id`) that `MainActivity` turns into a tap.
  static const String extraAction = 'uptrack_action';
  static const String extraTargetKind = 'uptrack_target_kind';
  static const String extraTargetId = 'uptrack_target_id';

  /// Longest id accepted in an intent. Longer ids are rejected outright rather
  /// than truncated, so an oversized payload can never become a *different*
  /// incident than the server meant.
  static const int maxIdLength = 64;

  /// Canonical action id for an action intent's action, or null when
  /// [intentAction] is the body-tap action or is unknown.
  static String? actionForIntentAction(String? intentAction) {
    return switch (intentAction) {
      acknowledgeAction => acknowledge,
      escalateAction => escalate,
      snoozeAction => snooze,
      _ => null,
    };
  }

  /// `Intent` action for a payload action id, or null when unknown.
  static String? intentActionForAction(String? action) {
    return switch (action) {
      acknowledge || 'acknowledge' => acknowledgeAction,
      escalate || 'escalate' => escalateAction,
      snooze || 'snooze' => snoozeAction,
      _ => null,
    };
  }

  /// Ids travel in a data URI and in extras, so accept only the conservative
  /// server id alphabet (`[A-Za-z0-9._-]`, at most [maxIdLength] chars) and
  /// reject anything else. Rejecting rather than stripping keeps a malformed
  /// payload from being *laundered* into a valid-looking but different target.
  static String? sanitizeId(String? raw) {
    if (raw == null) {
      return null;
    }
    final String trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.length > maxIdLength) {
      return null;
    }
    for (final int unit in trimmed.codeUnits) {
      final bool allowed =
          (unit >= 0x30 && unit <= 0x39) || // 0-9
          (unit >= 0x41 && unit <= 0x5A) || // A-Z
          (unit >= 0x61 && unit <= 0x7A) || // a-z
          unit == 0x2D || // -
          unit == 0x5F || // _
          unit == 0x2E; // .
      if (!allowed) {
        return null;
      }
    }
    return trimmed;
  }

  /// Body-tap data URI — unique per incident (or monitor) and distinct from
  /// every action URI. Null when the payload names no usable target.
  static String? tapData(String? incidentId, String? monitorId) {
    final String? incident = sanitizeId(incidentId);
    if (incident != null) {
      return '$dataScheme://push/tap/${PushTargetKind.incident.wire}/$incident';
    }
    final String? monitor = sanitizeId(monitorId);
    if (monitor != null) {
      return '$dataScheme://push/tap/${PushTargetKind.monitor.wire}/$monitor';
    }
    return null;
  }

  /// Action data URI — unique per action **and** target. Null when the target
  /// id is unusable.
  static String? actionData(
    String action,
    PushTargetKind kind,
    String? targetId,
  ) {
    final String? safeTarget = sanitizeId(targetId);
    if (safeTarget == null) {
      return null;
    }
    return '$dataScheme://push/action/${kind.wire}/$action/$safeTarget';
  }

  /// Canonical identity string behind an intent: the readable form of the
  /// action + data pair that the request code is derived from.
  static String identity(String intentAction, String? data) =>
      '$intentAction|$data';

  /// Stable, non-negative request code derived from an [identity] string.
  ///
  /// The same formula runs on the Kotlin side, so the same ASCII identity
  /// lands on the same int there — but correctness does not depend on it:
  /// identity is the action + data URI, per the note above.
  static int requestCode(String identity) => identity.hashCode & 0x7fffffff;

  /// Minimal action extras: action id, target kind, target id. Never a title,
  /// a body, a token, or anything else the alert carried — an intent is
  /// readable by anything that can read the notification, so it carries ids
  /// only.
  static Map<String, String> actionExtras({
    required String action,
    required PushTargetKind kind,
    required String? targetId,
  }) {
    final String? safeTarget = sanitizeId(targetId);
    return <String, String>{
      extraAction: action,
      extraTargetKind: kind.wire,
      extraTargetId: ?safeTarget,
    };
  }
}
