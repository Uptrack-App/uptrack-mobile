import '../../design/uptrack_design.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models/incident.dart';
import 'incidents_controller.dart';
import '../../util/date_format.dart';

/// Incident feed: ongoing/resolved rows with an All/Open/Needs
/// acknowledgement filter, with cache fallback when offline.
class IncidentsScreen extends ConsumerStatefulWidget {
  const IncidentsScreen({super.key, this.filter});

  /// Filter requested by a deep link (the dashboard's "view all" links).
  ///
  /// Null leaves the choice to the user: the screen starts on All and keeps
  /// whatever they pick until the link asks for something else.
  final IncidentStatusFilter? filter;

  @override
  ConsumerState<IncidentsScreen> createState() => _IncidentsScreenState();
}

class _IncidentsScreenState extends ConsumerState<IncidentsScreen> {
  late IncidentStatusFilter _filter = widget.filter ?? IncidentStatusFilter.all;

  @override
  void didUpdateWidget(covariant IncidentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only a *changed* link filter re-applies: a rebuild that keeps the same
    // value must not undo a filter the user picked themselves.
    if (widget.filter != null && widget.filter != oldWidget.filter) {
      setState(() => _filter = widget.filter!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<IncidentsData> incidents = ref.watch(incidentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Incidents')),
      body: Column(
        children: <Widget>[
          _IncidentFilterBar(
            selected: _filter,
            onSelected: (IncidentStatusFilter filter) =>
                setState(() => _filter = filter),
          ),
          Expanded(
            child: incidents.when(
              loading: () => const UptrackStateView(
                message: 'Loading incidents',
                loading: true,
              ),
              error: (Object err, StackTrace _) => _IncidentsError(
                message: incidentsErrorMessage(err),
                onRetry: () => ref.invalidate(incidentsProvider),
              ),
              data: (IncidentsData data) => _IncidentsBody(
                data: data,
                filter: _filter,
                onRefresh: () async {
                  ref.invalidate(incidentsProvider);
                  await ref.read(incidentsProvider.future);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Filter controls as wrapping chips.
///
/// A segmented control cannot shrink its three labels, so at a 200% text scale
/// ("Needs acknowledgement" especially) it overflowed the row. [Wrap] lets each
/// chip size to its label and flow onto its own line instead, and every chip is
/// separately capped at the width the bar actually has, so a long label wraps
/// rather than pushing past the screen edge.
class _IncidentFilterBar extends StatelessWidget {
  const _IncidentFilterBar({required this.selected, required this.onSelected});

  final IncidentStatusFilter selected;
  final ValueChanged<IncidentStatusFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final IncidentStatusFilter filter
                  in IncidentStatusFilter.values)
                _IncidentFilterChip(
                  key: ValueKey<String>('incident-filter-${filter.queryValue}'),
                  filter: filter,
                  selected: filter == selected,
                  // The cap is this chip's own, not the wrap's: the label gets
                  // the width the chip has left after the checkmark, so it has
                  // to be told the width the chip is allowed to occupy.
                  maxWidth: constraints.maxWidth,
                  onSelected: onSelected,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A selectable filter chip that can wrap its label onto more than one line.
///
/// [FilterChip] cannot do this. It lays its label out as a single line and
/// fades whatever does not fit, and it measures the chip's height from a label
/// laid out against the chip's *whole* width while laying the label out again
/// in what is left of it after the checkmark — a square as wide as the chip is
/// tall. At 200% text on a narrow phone "Needs acknowledgement" is therefore
/// silently cut off, with no overflow error to reveal it.
///
/// Here the label is a [Flexible] beside the checkmark inside a row capped at
/// [maxWidth], so it wraps onto as many lines as it needs, the chip grows to
/// fit, and the whole label stays readable and tappable.
class _IncidentFilterChip extends StatelessWidget {
  const _IncidentFilterChip({
    required this.filter,
    required this.selected,
    required this.maxWidth,
    required this.onSelected,
    super.key,
  });

  final IncidentStatusFilter filter;
  final bool selected;

  /// Width this chip may occupy, already reduced by the bar's own padding.
  final double maxWidth;

  final ValueChanged<IncidentStatusFilter> onSelected;

  /// Material's chip defaults, kept so the control still reads as the same
  /// chip it replaced: 8dp of padding around the label.
  static const EdgeInsets _padding = EdgeInsets.all(8);
  static const double _minHeight = 48;
  static const double _checkmarkSize = 18;
  static const double _labelGap = 8;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final ChipThemeData chips = theme.chipTheme;

    // The chip the theme already describes, reused rather than re-invented:
    // Material's own chips take their outline from `chipTheme.shape` and their
    // resting fill and label from `chipTheme`, so reading them here keeps this
    // control the same chip it replaced instead of a second design language.
    // Only the selected colours are explicit, because only that state has no
    // `ChipThemeData` slot to inherit from.
    final ShapeBorder shape = chips.shape ?? const StadiumBorder();
    final Color background = selected
        ? colors.secondaryContainer
        : (chips.backgroundColor ?? colors.surface);
    final Color foreground = selected
        ? colors.onSecondaryContainer
        : (chips.labelStyle?.color ?? colors.onSurface);
    final TextStyle? labelStyle =
        chips.labelStyle ?? theme.textTheme.labelLarge;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Semantics(
        // One node for the whole chip: the heading-free label is the control,
        // and the checkmark is decoration that `selected` already states.
        container: true,
        button: true,
        selected: selected,
        label: filter.label,
        onTap: () => onSelected(filter),
        child: ExcludeSemantics(
          child: Material(
            type: MaterialType.transparency,
            child: Ink(
              decoration: ShapeDecoration(color: background, shape: shape),
              child: InkWell(
                // The ink follows the same outline the fill does, so a pressed
                // chip is not clipped to a different shape than the resting one.
                customBorder: shape,
                onTap: () => onSelected(filter),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: _minHeight),
                  child: Padding(
                    padding: _padding,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (selected) ...<Widget>[
                          Icon(
                            Icons.check,
                            size: _checkmarkSize,
                            color: foreground,
                          ),
                          const SizedBox(width: _labelGap),
                        ],
                        Flexible(
                          child: Text(
                            filter.label,
                            style: labelStyle?.copyWith(color: foreground),
                            // Wraps onto as many lines as the chip's width
                            // needs: no line cap, and nothing faded or
                            // ellipsised away.
                            softWrap: true,
                            maxLines: null,
                            overflow: TextOverflow.visible,
                            textAlign: TextAlign.start,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IncidentsBody extends StatelessWidget {
  const _IncidentsBody({
    required this.data,
    required this.filter,
    required this.onRefresh,
  });

  final IncidentsData data;
  final IncidentStatusFilter filter;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final visible = filterIncidents(data.incidents, status: filter);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (data.offline)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: _OfflineBanner(),
            ),
          if (visible.isEmpty)
            UptrackStateView(
              message: incidentsEmptyMessage(
                filter,
                hasAny: data.incidents.isNotEmpty,
              ),
              actionLabel: 'Refresh',
              onAction: () {
                onRefresh();
              },
            ),
          for (final Incident incident in visible)
            _IncidentRow(incident: incident),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();
  @override
  Widget build(BuildContext context) => const UptrackNotice(
    message: 'Offline — showing cached data',
    kind: UptrackNoticeKind.offline,
  );
}

class _IncidentRow extends StatelessWidget {
  const _IncidentRow({required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context) {
    return UptrackDataRow(
      title: incident.displayName,
      semanticLabel:
          'Incident ${incident.displayName}, ${incident.isOngoing ? 'Open' : 'Resolved'}${incident.isAcknowledged ? ', acknowledged' : ''}',
      onTap: () => context.go('/incidents/${incident.id}'),
      details: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          UptrackLifecycleBadge(
            open: incident.isOngoing,
            acknowledged: incident.isAcknowledged,
          ),
          UptrackDataText(
            formatTimestamp(incident.insertedAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _IncidentsError extends StatelessWidget {
  const _IncidentsError({required this.message, required this.onRetry});

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
