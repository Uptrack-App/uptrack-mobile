import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/incident.dart';
import 'incidents_controller.dart';
import '../../theme/status_colors.dart';
import '../../util/date_format.dart';

/// Incident detail: header (monitor, status, timestamps), the acknowledge
/// action with an optimistic update (rolled back with a SnackBar on error),
/// and the posted updates list.
class IncidentDetailScreen extends ConsumerStatefulWidget {
  const IncidentDetailScreen({required this.incidentId, super.key});

  final String incidentId;

  @override
  ConsumerState<IncidentDetailScreen> createState() =>
      _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends ConsumerState<IncidentDetailScreen> {
  /// True while the optimistic acknowledge update is displayed.
  bool _optimisticAck = false;

  /// True while the acknowledge request is in flight.
  bool _acking = false;

  Future<void> _acknowledge() async {
    if (_acking) {
      return;
    }
    setState(() {
      _acking = true;
      _optimisticAck = true;
    });
    try {
      await ref
          .read(incidentDetailRepositoryProvider)
          .acknowledge(widget.incidentId);
      ref.invalidate(incidentDetailProvider(widget.incidentId));
    } catch (err) {
      // Roll back the optimistic update and surface the failure.
      if (!mounted) {
        return;
      }
      setState(() => _optimisticAck = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(acknowledgeErrorMessage(err))));
    } finally {
      if (mounted) {
        setState(() => _acking = false);
      } else {
        _acking = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<IncidentDetailData> detail = ref.watch(
      incidentDetailProvider(widget.incidentId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Incident')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
            acking: _acking,
            onAcknowledge: _acknowledge,
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
    required this.acking,
    required this.onAcknowledge,
    required this.onRefresh,
  });

  final IncidentDetailData data;
  final bool acking;
  final VoidCallback onAcknowledge;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Incident incident = data.incident;
    final bool canAcknowledge =
        incident.isOngoing && !incident.isAcknowledged && !data.offline;
    final String state = incident.isOngoing ? 'Open' : 'Resolved';
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
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.cloud_off_outlined),
                      SizedBox(width: 8),
                      Expanded(child: Text('Offline — showing cached data')),
                    ],
                  ),
                ),
              ),
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
          const SizedBox(height: 12),
          if (canAcknowledge)
            Semantics(
              label: 'Acknowledge incident ${incident.displayName}',
              child: FilledButton(
                onPressed: acking ? null : onAcknowledge,
                child: acking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Acknowledge'),
              ),
            ),
          const SizedBox(height: 16),
          Text('Updates', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (data.updates.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  data.offline
                      ? 'Updates unavailable offline.'
                      : 'No updates yet.',
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
