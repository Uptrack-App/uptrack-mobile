import '../../api/uptrack_api.dart';
import 'incidents_controller.dart';
import '../../util/date_format.dart';

/// The response actions available on an open incident.
///
/// The enum is also the serialization key: only one response mutation may be
/// in flight at a time, so a screen keeps a single [IncidentResponseAction?]
/// "busy" slot rather than one flag per button.
enum IncidentResponseAction {
  acknowledge,
  escalate,
  snooze;

  /// Short verb for buttons, SnackBars and busy labels.
  String get label => switch (this) {
    IncidentResponseAction.acknowledge => 'acknowledge',
    IncidentResponseAction.escalate => 'escalate',
    IncidentResponseAction.snooze => 'snooze',
  };

  /// Retryable failure copy. Every action can simply be tried again; none of
  /// them changes server state locally, so a retry is always safe.
  String get failureMessage => switch (this) {
    IncidentResponseAction.acknowledge =>
      'Could not acknowledge this incident. Try again.',
    IncidentResponseAction.escalate =>
      'Could not escalate this incident. Try again.',
    IncidentResponseAction.snooze => 'Could not snooze your alerts. Try again.',
  };
}

/// The identity a response action is aimed at, captured before any dialog or
/// request so a target change mid-flight cannot redirect it.
class ResponseTarget {
  const ResponseTarget({
    required this.incidentId,
    required this.monitorId,
    required this.generation,
  });

  final String incidentId;

  /// Monitor the snooze action addresses; empty for incident-only actions.
  final String monitorId;

  /// Bumped whenever the screen's incident target changes. Results carrying a
  /// stale generation are dropped instead of shown for the wrong incident.
  final int generation;
}

/// A completed response action, described exactly as the server answered it.
///
/// There is deliberately no "success" case that is not backed by a server
/// answer: escalate can come back as an idempotent no-op, and this type
/// keeps that distinguishable from a request that published something.
sealed class IncidentResponseOutcome {
  const IncidentResponseOutcome();

  /// The action this outcome belongs to.
  IncidentResponseAction get action;

  /// Truthful user-facing copy. Never claims a notification was delivered.
  String get message;
}

/// The incident is acknowledged; escalation is paused and an update posted.
final class IncidentAcknowledged extends IncidentResponseOutcome {
  const IncidentAcknowledged();

  @override
  IncidentResponseAction get action => IncidentResponseAction.acknowledge;

  @override
  String get message => 'Acknowledged. Escalation is paused.';
}

/// The incident *is* acknowledged on the server, but this device could not save
/// the result offline (R4).
///
/// A distinct outcome rather than a failure message: the mutation succeeded, so
/// telling the user to retry would invite a second acknowledgement for an
/// incident that is already acknowledged. It also cannot promise offline
/// context — nothing was written, so a relaunch or an offline open will not
/// show this incident's updates.
final class IncidentAcknowledgedNotSaved extends IncidentResponseOutcome {
  const IncidentAcknowledgedNotSaved();

  @override
  IncidentResponseAction get action => IncidentResponseAction.acknowledge;

  @override
  String get message =>
      'Acknowledged. Escalation is paused. This device could not save the '
      'update offline, so it may not be here without a connection.';
}

/// The acknowledge call succeeded but the server still reports the incident
/// as unacknowledged (it resolved in the meantime, for example). Reported as
/// a no-op instead of a local acknowledgement that never happened.
final class IncidentAcknowledgedNoop extends IncidentResponseOutcome {
  const IncidentAcknowledgedNoop();

  @override
  IncidentResponseAction get action => IncidentResponseAction.acknowledge;

  @override
  String get message =>
      'The incident is no longer open, so it was not acknowledged.';
}

/// The escalation request was accepted and the server published [stepsFired]
/// channel alerts.
///
/// The copy reports what the server counted and nothing more: a published
/// channel event is not proof that a person or a channel received it.
final class IncidentEscalated extends IncidentResponseOutcome {
  const IncidentEscalated(this.stepsFired);

  /// Channel events the server says it published for this call.
  final int stepsFired;

  @override
  IncidentResponseAction get action => IncidentResponseAction.escalate;

  @override
  String get message => stepsFired == 1
      ? 'Escalation sent. 1 alert published.'
      : 'Escalation sent. $stepsFired alerts published.';
}

/// The server treated escalation as a no-op (`escalated: false` or
/// `steps_fired: 0`) — the incident may already be acknowledged or resolved.
/// Nothing was published, and the copy states only that: it does not claim to
/// know why, and never implies a policy is exhausted.
final class IncidentEscalationNoop extends IncidentResponseOutcome {
  const IncidentEscalationNoop();

  @override
  IncidentResponseAction get action => IncidentResponseAction.escalate;

  @override
  String get message => 'No escalation was sent.';
}

/// This user's mobile push alerts for the monitor are suppressed until
/// [snoozedUntil].
///
/// The backend silences every `mobile_push` alert for this user on this
/// monitor for the hour — recovery updates included. Other people are
/// unaffected, and nothing is resolved.
final class IncidentSnoozed extends IncidentResponseOutcome {
  const IncidentSnoozed(this.snoozedUntil);

  /// Raw ISO 8601 instant returned by the API.
  final String snoozedUntil;

  @override
  IncidentResponseAction get action => IncidentResponseAction.snooze;

  /// Local, human-readable expiry; falls back to the raw value when it does
  /// not parse, so the user is never shown an empty expiry.
  String get formattedExpiry => formatTimestamp(snoozedUntil);

  @override
  String get message =>
      'Your mobile alerts for this monitor are paused until '
      '$formattedExpiry, including recovery updates. Other people are not '
      'affected, and the incident is not resolved.';
}

/// Interprets an acknowledge response: the refreshed incident is the only
/// evidence of acknowledgement, never the local tap.
///
/// A confirmed acknowledgement that could not be persisted gets its own
/// outcome, so a storage failure after the server accepted the action is never
/// reported as a failed mutation ([IncidentAcknowledgedNotSaved]).
IncidentResponseOutcome interpretAcknowledge(IncidentDetailData data) {
  if (!data.incident.isAcknowledged) {
    return const IncidentAcknowledgedNoop();
  }
  if (!data.savedOffline) {
    return const IncidentAcknowledgedNotSaved();
  }
  return const IncidentAcknowledged();
}

/// Interprets an escalate response. `escalated: false` and `steps_fired: 0`
/// are both no-ops, and neither may be reported as a dispatched escalation.
IncidentResponseOutcome interpretEscalate(EscalateResult result) =>
    result.escalated && result.stepsFired > 0
    ? IncidentEscalated(result.stepsFired)
    : const IncidentEscalationNoop();

/// Interprets a snooze response.
IncidentResponseOutcome interpretSnooze(SnoozeResult result) =>
    IncidentSnoozed(result.snoozedUntil);

/// Confirmation copy for escalation.
///
/// The scope is stated before the request because escalation is the one
/// response action that reaches other people.
abstract final class IncidentEscalateConfirmation {
  static const String title = 'Escalate this incident?';

  static const String message =
      'Escalation runs the monitor’s remaining configured policy steps right '
      'now — for example paging the on-call contact. It does not resolve the '
      'incident.';

  static const String confirmLabel = 'Escalate now';
}

/// Confirmation copy for the one-hour snooze, including what it does not do.
///
/// The backend suppresses every `mobile_push` alert for this user on this
/// monitor, recovery updates included, so the copy says exactly that.
abstract final class IncidentSnoozeConfirmation {
  static const String title = 'Pause your alerts for 1 hour?';

  static const String message =
      'This silences your own mobile push alerts for this monitor for one '
      'hour, including recovery updates. It does not stop team alerts, and it '
      'does not resolve the incident.';

  static const String confirmLabel = 'Pause for 1 hour';
}

/// Copy for a request that was refused before it was sent because the
/// incident changed while the confirmation was open.
const String responseChangedMessage =
    'This incident changed while the confirmation was open. Nothing was '
    'sent — reopen the incident and try again.';

/// Eligibility for a response action, evaluated against the latest known
/// detail.
///
/// Re-checked after every confirmation dialog: the incident may have been
/// acknowledged, resolved, or fallen back to cache while the dialog was up,
/// and a request that cannot apply must not be sent.
class ResponseEligibility {
  const ResponseEligibility({
    required this.available,
    required this.offline,
    required this.resolved,
    required this.acknowledged,
  });

  /// Latest detail for the incident, or null when it could not be read at
  /// all (in which case nothing is available to act on).
  factory ResponseEligibility.from(IncidentDetailData? data) => data == null
      ? const ResponseEligibility(
          available: false,
          offline: true,
          resolved: true,
          acknowledged: false,
        )
      : ResponseEligibility(
          available: true,
          offline: data.offline,
          resolved: !data.incident.isOngoing,
          acknowledged: data.incident.isAcknowledged,
        );

  /// Whether the detail itself could be read.
  final bool available;

  /// Detail came from the offline cache, so no mutation can be sent.
  final bool offline;
  final bool resolved;
  final bool acknowledged;

  /// Escalation is a documented server no-op once acknowledged, so it is not
  /// offered then.
  bool get canEscalate => available && !offline && !resolved && !acknowledged;

  /// Snoozing one's own alerts is independent of acknowledgement.
  bool get canSnooze => available && !offline && !resolved;

  /// Why escalation was refused after the confirmation, or null when it may
  /// still be sent. Same contract for [snoozeRefusal].
  String? get escalateRefusal => canEscalate ? null : responseChangedMessage;

  String? get snoozeRefusal => canSnooze ? null : responseChangedMessage;
}

/// Rationale shown when a response action is unavailable, so a disabled
/// control is never a silent dead end.
String responseUnavailableReason({
  required bool offline,
  required bool resolved,
  required bool acknowledged,
}) {
  if (offline) {
    return 'Response actions need a connection.';
  }
  if (resolved) {
    return 'This incident is resolved. Nothing left to respond to.';
  }
  if (acknowledged) {
    return 'Escalation is a no-op once an incident is acknowledged.';
  }
  return '';
}
