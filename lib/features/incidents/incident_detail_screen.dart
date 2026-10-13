import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/incident.dart';
import 'incident_response.dart';
import 'incidents_controller.dart';
import '../../design/uptrack_design.dart';
import '../../util/date_format.dart';

/// Incident detail: header (monitor, status, timestamps), the Response
/// section (acknowledge, escalate, snooze this user's alerts) and the posted
/// updates list.
///
/// Every response mutation goes through [_run]: one action at a time
/// (serialized through [_busy]), never offline, never on a resolved incident,
/// and never optimistically for escalate or snooze — only the acknowledge
/// shows an optimistic state, and only while its request is in flight.
class IncidentDetailScreen extends ConsumerStatefulWidget {
  const IncidentDetailScreen({required this.incidentId, super.key});

  final String incidentId;

  @override
  ConsumerState<IncidentDetailScreen> createState() =>
      _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends ConsumerState<IncidentDetailScreen> {
  /// The response mutation currently in flight, or null when idle. One slot
  /// for all three actions is what serializes them: a second tap while busy
  /// is ignored rather than sent concurrently.
  IncidentResponseAction? _busy;

  /// The last completed response action, shown until the next one starts.
  IncidentResponseOutcome? _outcome;

  /// Incremented whenever [widget.incidentId] changes, so a request started
  /// for the previous incident can never report into the new one.
  int _generation = 0;

  @override
  void didUpdateWidget(IncidentDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.incidentId != widget.incidentId) {
      _generation++;
      // Local response state belongs to the incident that produced it.
      _busy = null;
      _outcome = null;
    }
  }

  /// True while the optimistic acknowledge update should be displayed.
  ///
  /// Derived from [_busy] rather than latched, so the optimistic state can
  /// never outlive the request that produced it: success falls back to the
  /// server's answer (and the refetch below), failure falls back to the last
  /// known state.
  bool get _optimisticAck => _busy == IncidentResponseAction.acknowledge;

  Future<void> _acknowledge() async {
    // Identity is captured up front: the mutation below must address the
    // incident the user tapped, even if the route is replaced mid-flight.
    final ResponseTarget target = ResponseTarget(
      incidentId: widget.incidentId,
      monitorId: '',
      generation: _generation,
    );
    await _run(
      IncidentResponseAction.acknowledge,
      target,
      (ResponseTarget t) async => interpretAcknowledge(
        await ref
            .read(incidentDetailRepositoryProvider)
            .acknowledge(t.incidentId),
      ),
    );
  }

  Future<void> _escalate() async {
    final ResponseTarget target = ResponseTarget(
      incidentId: widget.incidentId,
      monitorId: '',
      generation: _generation,
    );
    final bool confirmed = await showUptrackConfirmation(
      context,
      title: IncidentEscalateConfirmation.title,
      message: IncidentEscalateConfirmation.message,
      confirmLabel: IncidentEscalateConfirmation.confirmLabel,
    );
    // Checked immediately after the await: the dialog may have outlived the
    // screen, and no provider may be read after dispose.
    if (!confirmed || !mounted) {
      return;
    }
    final String? refusal = _recheck(target).escalateRefusal;
    if (refusal != null) {
      _refuse(refusal);
      return;
    }
    await _run(
      IncidentResponseAction.escalate,
      target,
      (ResponseTarget t) async => interpretEscalate(
        await ref.read(incidentDetailRepositoryProvider).escalate(t.incidentId),
      ),
    );
  }

  Future<void> _snooze(String monitorId) async {
    final ResponseTarget target = ResponseTarget(
      incidentId: widget.incidentId,
      monitorId: monitorId,
      generation: _generation,
    );
    final bool confirmed = await showUptrackConfirmation(
      context,
      title: IncidentSnoozeConfirmation.title,
      message: IncidentSnoozeConfirmation.message,
      confirmLabel: IncidentSnoozeConfirmation.confirmLabel,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final String? refusal = _recheck(target).snoozeRefusal;
    if (refusal != null) {
      _refuse(refusal);
      return;
    }
    await _run(
      IncidentResponseAction.snooze,
      target,
      (ResponseTarget t) async => interpretSnooze(
        await ref.read(incidentDetailRepositoryProvider).snooze(t.monitorId),
      ),
    );
  }

  /// Whether [target] still matches the screen's current target.
  bool _isCurrent(ResponseTarget target) =>
      target.generation == _generation &&
      target.incidentId == widget.incidentId;

  /// Latest eligibility for [target], re-read from the provider so a dialog
  /// that was open across an acknowledgement, resolution or offline fallback
  /// cannot send a request that cannot apply.
  ResponseEligibility _recheck(ResponseTarget target) {
    if (!_isCurrent(target)) {
      return ResponseEligibility.from(null);
    }
    return ResponseEligibility.from(
      ref.read(incidentDetailProvider(target.incidentId)).asData?.value,
    );
  }

  /// Reports a request that was refused before it was sent.
  void _refuse(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs one response mutation against [target]: marks it busy, applies the
  /// server's answer, then refreshes every surface that shows the incident.
  Future<void> _run(
    IncidentResponseAction action,
    ResponseTarget target,
    Future<IncidentResponseOutcome> Function(ResponseTarget target) mutation,
  ) async {
    if (_busy != null || !_isCurrent(target)) {
      // Another mutation owns the single response slot, or the screen has
      // moved to a different incident.
      return;
    }
    setState(() {
      _busy = action;
      _outcome = null;
    });
    try {
      final IncidentResponseOutcome outcome = await mutation(target);
      if (!mounted || !_isCurrent(target)) {
        // A late result for a replaced incident is dropped rather than shown.
        return;
      }
      setState(() {
        _busy = null;
        _outcome = outcome;
      });
      // The detail, feed and dashboard all show acknowledgement; a stale
      // copy anywhere would contradict what the user just did.
      invalidateIncidentSurfaces(ref, target.incidentId);
    } catch (err) {
      if (!mounted || !_isCurrent(target)) {
        return;
      }
      setState(() => _busy = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_errorMessage(err, action))));
    }
  }

  String _errorMessage(Object err, IncidentResponseAction action) =>
      switch (action) {
        IncidentResponseAction.acknowledge => acknowledgeErrorMessage(err),
        IncidentResponseAction.escalate => escalateErrorMessage(err),
        IncidentResponseAction.snooze => snoozeErrorMessage(err),
      };

  @override
  Widget build(BuildContext context) {
    final AsyncValue<IncidentDetailData> detail = ref.watch(
      incidentDetailProvider(widget.incidentId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Incident')),
      body: detail.when(
        loading: () =>
            const UptrackStateView(message: 'Loading incident', loading: true),
        error: (Object err, StackTrace _) => _DetailError(
          message: incidentsErrorMessage(err),
          onRetry: () =>
              ref.invalidate(incidentDetailProvider(widget.incidentId)),
        ),
        data: (IncidentDetailData data) {
          final IncidentDetailData effective = _optimisticAck
              ? optimisticAcknowledge(data)
              : data;
          return _DetailBody(
            data: effective,
            busy: _busy,
            outcome: _outcome,
            onAcknowledge: _acknowledge,
            onEscalate: _escalate,
            // The tap carries the monitor the screen is showing, so the
            // snooze cannot be redirected to another monitor afterwards.
            onSnooze: (String monitorId) => _snooze(monitorId),
            onRefresh: () async {
              ref.invalidate(incidentDetailProvider(widget.incidentId));
              await ref.read(incidentDetailProvider(widget.incidentId).future);
            },
          );
        },
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.data,
    required this.busy,
    required this.outcome,
    required this.onAcknowledge,
    required this.onEscalate,
    required this.onSnooze,
    required this.onRefresh,
  });

  final IncidentDetailData data;
  final IncidentResponseAction? busy;
  final IncidentResponseOutcome? outcome;
  final VoidCallback onAcknowledge;
  final VoidCallback onEscalate;
  final void Function(String monitorId) onSnooze;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Incident incident = data.incident;
    final bool stateAllowsResponse = incident.isOngoing;
    final String state = stateAllowsResponse ? 'Open' : 'Resolved';
    final String headerLabel = incident.isAcknowledged
        ? 'Incident ${incident.displayName}, $state, acknowledged'
        : 'Incident ${incident.displayName}, $state';

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (data.offline)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: UptrackNotice(
                message: 'Offline — showing cached data',
                kind: UptrackNoticeKind.offline,
              ),
            ),
          // Always stated, online or offline: the reader has to know how old
          // what they are looking at is. Sourced from the stored sync time of
          // the write that produced the summary, so a cached fallback does not
          // restate it as fresh.
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: UptrackSyncStamp(syncedAt: data.summarySyncedAt),
          ),
          Semantics(
            label: headerLabel,
            header: true,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      incident.displayName,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: <Widget>[
                        Chip(
                          label: Text(incident.isOngoing ? 'Open' : 'Resolved'),
                          visualDensity: VisualDensity.compact,
                        ),
                        if (incident.isAcknowledged)
                          const Chip(
                            label: Text('Acknowledged'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Started ${formatTimestamp(incident.startedAt ?? incident.insertedAt)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (incident.resolvedAt != null)
                      Text(
                        'Resolved ${formatTimestamp(incident.resolvedAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    if (incident.acknowledgedAt != null)
                      Text(
                        'Acknowledged ${formatTimestamp(incident.acknowledgedAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ResponseSection(
            incident: incident,
            offline: data.offline,
            busy: busy,
            outcome: outcome,
            onAcknowledge: onAcknowledge,
            onEscalate: onEscalate,
            onSnooze: onSnooze,
          ),
          const SizedBox(height: 16),
          Text('Updates', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          // The updates carry their own sync time whenever it differs from the
          // summary's (a saved snapshot read at a different moment than the
          // list refresh that supplied the summary), so the reader can tell
          // which of the two is older. A matching time adds nothing, so it is
          // not repeated.
          if (data.updatesSyncedAt != null &&
              data.updatesSyncedAt != data.summarySyncedAt)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: UptrackSyncStamp(
                syncedAt: data.updatesSyncedAt,
                prefix: 'Updates last synced',
              ),
            ),
          if (data.updates.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                // Two different facts, kept apart. A saved snapshot that was
                // genuinely empty means "the server told us there are none";
                // no snapshot at all means we do not know, and claiming "no
                // updates yet" there would report an absence we never observed.
                child: Text(
                  data.hasSavedSnapshot
                      ? 'No updates yet.'
                      : 'No saved updates for offline viewing.',
                ),
              ),
            )
          else
            for (final IncidentUpdate update in data.updates)
              _UpdateRow(update: update),
        ],
      ),
    );
  }
}

/// The Response section: acknowledge (primary) plus the two scoped secondary
/// actions. Availability is derived from the incident and the connection, and
/// every disabled control carries the reason it is disabled.
class _ResponseSection extends StatelessWidget {
  const _ResponseSection({
    required this.incident,
    required this.offline,
    required this.busy,
    required this.outcome,
    required this.onAcknowledge,
    required this.onEscalate,
    required this.onSnooze,
  });

  final Incident incident;
  final bool offline;
  final IncidentResponseAction? busy;
  final IncidentResponseOutcome? outcome;
  final VoidCallback onAcknowledge;
  final VoidCallback onEscalate;
  final void Function(String monitorId) onSnooze;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // A resolved incident has nothing left to respond to in this increment;
    // offline cannot reach the server at all.
    final bool enabled = incident.isOngoing && !offline;
    final bool canAcknowledge = enabled && !incident.isAcknowledged;
    // Escalating an acknowledged incident is a documented server no-op, so
    // the control is disabled rather than sending a request that cannot do
    // anything.
    final bool canEscalate = enabled && !incident.isAcknowledged;
    final bool canSnooze = enabled;
    final String reason = responseUnavailableReason(
      offline: offline,
      resolved: !incident.isOngoing,
      acknowledged: incident.isAcknowledged,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Response', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          // The incident-specific label rides on the button's own text node, so
          // a screen reader announces it together with the button's role, tap
          // action and enabled state. A label-only wrapper would drop all three.
          child: UptrackButton(
            label: 'Acknowledge',
            semanticLabel: 'Acknowledge incident ${incident.displayName}',
            kind: UptrackButtonKind.primary,
            busy: busy == IncidentResponseAction.acknowledge,
            onPressed: canAcknowledge && busy == null ? onAcknowledge : null,
          ),
        ),
        const SizedBox(height: 8),
        // Wrap so the secondary actions reflow instead of overflowing on a
        // narrow screen or at large text sizes.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            UptrackButton(
              label: 'Escalate',
              semanticLabel: 'Escalate incident ${incident.displayName}',
              icon: Icons.campaign_outlined,
              kind: UptrackButtonKind.secondary,
              busy: busy == IncidentResponseAction.escalate,
              onPressed: canEscalate && busy == null ? onEscalate : null,
            ),
            UptrackButton(
              label: 'Snooze 1 hour',
              semanticLabel:
                  'Snooze your mobile alerts for 1 hour on '
                  '${incident.displayName}',
              icon: Icons.notifications_paused_outlined,
              kind: UptrackButtonKind.secondary,
              busy: busy == IncidentResponseAction.snooze,
              onPressed: canSnooze && busy == null
                  ? () => onSnooze(incident.monitorId)
                  : null,
            ),
          ],
        ),
        if (reason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(reason, style: theme.textTheme.bodySmall),
          ),
        if (outcome != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              container: true,
              liveRegion: true,
              child: UptrackNotice(message: outcome!.message),
            ),
          ),
      ],
    );
  }
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({required this.update});

  final IncidentUpdate update;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      label: 'Update ${update.displayTitle}, ${statusLabel(update.status)}',
      child: Card(
        child: ListTile(
          title: Text(update.displayTitle),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                statusLabel(update.status),
                style: theme.textTheme.bodySmall,
              ),
              if (update.postedAt != null)
                Text(
                  formatTimestamp(update.postedAt),
                  style: theme.textTheme.bodySmall,
                ),
              if (update.description != null && update.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(update.description!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return UptrackStateView(
      message: message,
      actionLabel: 'Retry',
      onAction: onRetry,
    );
  }
}
