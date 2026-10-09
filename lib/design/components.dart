import 'package:flutter/material.dart';

import '../theme/status_colors.dart';
import '../theme/tokens.dart';
import '../util/date_format.dart';

enum UptrackButtonKind { primary, secondary, quiet, destructive }

/// Caller owns requests/validation. Busy retains task identity and blocks taps.
class UptrackButton extends StatelessWidget {
  const UptrackButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.kind = UptrackButtonKind.primary,
    this.icon,
    this.semanticLabel,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final UptrackButtonKind kind;
  final IconData? icon;

  /// Optional incident-specific label announced instead of [label].
  ///
  /// Applied to the label text *inside* the native button, so the announcement
  /// lands on the actionable node itself (role, tap and enabled state
  /// included) rather than on a wrapper that only repeats the label.
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final callback = busy ? null : onPressed;
    // The busy announcement lives *inside* the native button, so it is carried
    // by the actionable node itself — together with its label, button flag and
    // tap action. A wrapper outside the button would be announced on its own,
    // without any of them.
    final Widget content = Semantics(
      liveRegion: busy,
      value: busy ? 'In progress' : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ] else if (icon != null) ...[
            Icon(icon, size: 20),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              semanticsLabel: semanticLabel,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
    final button = switch (kind) {
      UptrackButtonKind.secondary => OutlinedButton(
        onPressed: callback,
        child: content,
      ),
      UptrackButtonKind.quiet => TextButton(
        onPressed: callback,
        child: content,
      ),
      UptrackButtonKind.destructive => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.error,
          foregroundColor: theme.colorScheme.onError,
        ),
        onPressed: callback,
        child: content,
      ),
      UptrackButtonKind.primary => FilledButton(
        onPressed: callback,
        child: content,
      ),
    };
    return button;
  }
}

class UptrackDataText extends StatelessWidget {
  const UptrackDataText(
    this.data, {
    super.key,
    this.style,
    this.semanticLabel,
    this.textAlign,
  });
  final String data;
  final TextStyle? style;
  final String? semanticLabel;
  final TextAlign? textAlign;
  @override
  Widget build(BuildContext context) => Text(
    data,
    semanticsLabel: semanticLabel,
    textAlign: textAlign,
    // Numbers use the sans font with tabular, lining figures (as Claude does),
    // so columns of figures line up. Code-like text uses [UptrackCodeText].
    style: (style ?? Theme.of(context).textTheme.bodyMedium)!.copyWith(
      fontFeatures: const [
        FontFeature.tabularFigures(),
        FontFeature.liningFigures(),
      ],
    ),
  );
}

/// Code-like data (URLs, hostnames, ids) in the mono font.
class UptrackCodeText extends StatelessWidget {
  const UptrackCodeText(this.data, {super.key, this.style, this.textAlign});
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  @override
  Widget build(BuildContext context) => Text(
    data,
    textAlign: textAlign,
    style: (style ?? Theme.of(context).textTheme.bodyMedium)!.copyWith(
      fontFamily: UptrackTypography.monoFamily,
    ),
  );
}

class UptrackStatusBadge extends StatelessWidget {
  const UptrackStatusBadge({super.key, required this.status});
  final String? status;
  @override
  Widget build(BuildContext context) {
    final look = UptrackStatusColors.of(context).forStatus(status);
    return _Badge(
      label:
          const {
            'up',
            'operational',
            'down',
            'degraded',
            'visual_regression',
            'partial_outage',
            'paused',
            'disabled',
            'pending',
          }.contains(status)
          ? statusLabel(status)
          : look.label,
      icon: look.icon,
      foreground: look.color,
      background: look.soft,
    );
  }
}

class UptrackLifecycleBadge extends StatelessWidget {
  const UptrackLifecycleBadge({
    super.key,
    required this.open,
    this.acknowledged = false,
  });
  final bool open;
  final bool acknowledged;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Badge(
      label:
          '${open ? 'Open' : 'Resolved'}${acknowledged ? ' · Acknowledged' : ''}',
      icon: open ? Icons.pending_outlined : Icons.check_circle_outline,
      foreground: scheme.onSurface,
      background: scheme.surfaceContainerHigh,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
  });
  final String label;
  final IconData icon;
  final Color foreground, background;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    excludeSemantics: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(UptrackRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

enum UptrackNoticeKind { info, error, offline, sample }

class UptrackNotice extends StatelessWidget {
  const UptrackNotice({
    super.key,
    required this.message,
    this.kind = UptrackNoticeKind.info,
    this.actionLabel,
    this.onAction,
  });
  final String message;
  final UptrackNoticeKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (kind) {
      UptrackNoticeKind.error => Icons.error_outline,
      UptrackNoticeKind.offline => Icons.cloud_off_outlined,
      UptrackNoticeKind.sample => Icons.explore_outlined,
      UptrackNoticeKind.info => Icons.info_outline,
    };
    return Semantics(
      container: true,
      liveRegion: kind == UptrackNoticeKind.error,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      icon,
                      color: kind == UptrackNoticeKind.error
                          ? scheme.error
                          : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(message)),
                ],
              ),
              if (onAction != null && actionLabel != null)
                UptrackButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  kind: UptrackButtonKind.quiet,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quiet secondary text naming when a snapshot was actually last synced (R4).
///
/// Two rules it exists to enforce:
///
/// * the timestamp is the *stored* sync time of the write that produced the
///   data, never the moment a cached row was read back, so a fallback read
///   cannot make stale content look freshly synced;
/// * an unknown time is stated ("Last sync time unavailable.") rather than
///   silently omitted, so an absent timestamp is not mistaken for a fresh one.
///
/// [prefix] distinguishes two snapshots on one screen (an incident's summary
/// and its updates), and both are rendered with the same styling so neither
/// reads as more authoritative than the other. Not a live region: an unchanged
/// timestamp must not be re-announced on every rebuild — transitions and errors
/// go through [UptrackNotice], which is where the live-region semantics live.
class UptrackSyncStamp extends StatelessWidget {
  const UptrackSyncStamp({
    super.key,
    required this.syncedAt,
    this.prefix = 'Last synced',
  });

  /// The stored sync instant of the snapshot being described, or null when
  /// nothing has ever synced.
  final DateTime? syncedAt;

  /// Noun phrase this timestamp describes, e.g. `Updates last synced`.
  final String prefix;

  /// Copy used when no sync time is known. A missing timestamp is a fact worth
  /// stating: it is the difference between "we know this is an hour old" and
  /// "we do not know how old this is".
  static const String unknownMessage = 'Last sync time unavailable.';

  String get message =>
      syncedAt == null ? unknownMessage : '$prefix ${formatInstant(syncedAt!)}';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      // Reads as one sentence, and stays out of the live region so an
      // unchanged stamp is not announced on every rebuild.
      label: message,
      excludeSemantics: true,
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        // Wraps onto as many lines as the width needs: no single-line
        // truncation, so the timestamp stays readable at 200% text.
        softWrap: true,
        maxLines: null,
        overflow: TextOverflow.visible,
      ),
    );
  }
}

class UptrackStateView extends StatelessWidget {
  const UptrackStateView({
    super.key,
    required this.message,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });
  final String message;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: CircularProgressIndicator(),
            ),
          Text(message, textAlign: TextAlign.center),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 12),
            UptrackButton(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    ),
  );
}

class UptrackMetricTile extends StatelessWidget {
  const UptrackMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.semanticLabel,
  });
  final String? semanticLabel;
  final String label;
  final String? value;
  final String? detail;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label:
        semanticLabel ??
        '$label: ${value ?? 'Not available'}${detail == null ? '' : ', $detail'}',
    excludeSemantics: true,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            UptrackDataText(
              value ?? '—',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (detail != null)
              Text(detail!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}

class UptrackContent extends StatelessWidget {
  const UptrackContent({super.key, required this.child, this.maxWidth = 960});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

class UptrackSection extends StatelessWidget {
  const UptrackSection({super.key, required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

/// Native modal semantics/focus/back behavior, with a safe initial action.
Future<bool> showUptrackConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          UptrackButton(
            label: confirmLabel,
            kind: destructive
                ? UptrackButtonKind.destructive
                : UptrackButtonKind.primary,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    ) ??
    false;

/// Presentation contract for monitor and incident rows; caller owns route/data.
class UptrackDataRow extends StatelessWidget {
  const UptrackDataRow({
    super.key,
    required this.title,
    required this.details,
    this.onTap,
    this.semanticLabel,
  });
  final String? semanticLabel;
  final String title;
  final Widget details;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    // A row is one focusable target, so it needs its own node: without a
    // container here the row's label merges into whatever ancestor node exists
    // (the section heading on the dashboard, for instance) and a screen reader
    // announces the heading again on every row instead of one linkable row.
    container: true,
    label: semanticLabel,
    excludeSemantics: semanticLabel != null,
    button: onTap != null,
    onTap: onTap,
    child: Card(
      child: ListTile(
        minTileHeight: 64,
        title: Text(title),
        subtitle: details,
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    ),
  );
}
