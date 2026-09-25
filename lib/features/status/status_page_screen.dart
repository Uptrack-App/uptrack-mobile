import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/status_page.dart';
import '../auth/auth_controller.dart';

/// Query for the public status page lookup (slug + optional page password).
typedef StatusQuery = ({String slug, String password});

/// `GET /api/status/{slug}` keyed by slug + password; no auth required.
final statusPageProvider = FutureProvider.family<StatusPageData, StatusQuery>((
  Ref ref,
  StatusQuery query,
) async {
  return ref
      .read(uptrackApiProvider)
      .getStatusPage(
        query.slug,
        password: query.password.isEmpty ? null : query.password,
      );
});

String statusPageErrorMessage(Object err) {
  if (err is DioException) {
    final Object? data = err.response?.data;
    if (data is Map<String, Object?>) {
      final Object? serverError = data['error'];
      if (serverError is String && serverError.isNotEmpty) {
        return serverError;
      }
    }
    if (err.response?.statusCode == 404) {
      return 'No status page found for that slug.';
    }
    if (err.response?.statusCode == 401 || err.response?.statusCode == 403) {
      return 'This status page needs a password.';
    }
  }
  return 'Something went wrong. Check your connection and try again.';
}

/// Public status view: slug (+ optional password) lookup rendering the
/// page's overall status, uptime, monitors, and recent incidents.
class StatusPageScreen extends ConsumerStatefulWidget {
  const StatusPageScreen({super.key, this.initialSlug = ''});

  final String initialSlug;

  @override
  ConsumerState<StatusPageScreen> createState() => _StatusPageScreenState();
}

class _StatusPageScreenState extends ConsumerState<StatusPageScreen> {
  late final TextEditingController _slugController;
  late final TextEditingController _passwordController;
  StatusQuery? _query;

  @override
  void initState() {
    super.initState();
    _slugController = TextEditingController(text: widget.initialSlug);
    _passwordController = TextEditingController();
    if (widget.initialSlug.isNotEmpty) {
      _query = (slug: widget.initialSlug, password: '');
    }
  }

  @override
  void dispose() {
    _slugController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _lookup() {
    final String slug = _slugController.text.trim();
    if (slug.isEmpty) {
      return;
    }
    setState(() {
      _query = (slug: slug, password: _passwordController.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final StatusQuery? query = _query;
    final AsyncValue<StatusPageData>? page = query == null
        ? null
        : ref.watch(statusPageProvider(query));

    return Scaffold(
      appBar: AppBar(title: const Text('Status page')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _slugController,
            key: const ValueKey<String>('status-slug'),
            decoration: const InputDecoration(
              labelText: 'Page slug',
              hintText: 'e.g. acme',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _lookup(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            key: const ValueKey<String>('status-password'),
            decoration: const InputDecoration(
              labelText: 'Page password (if protected)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            obscureText: true,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _lookup(),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _lookup, child: const Text('View status')),
          const SizedBox(height: 16),
          if (page == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Enter a status page slug to view its status.'),
              ),
            )
          else
            Builder(
              builder: (BuildContext context) {
                final StatusQuery activeQuery = query!;
                return page.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (Object err, StackTrace _) => _StatusError(
                    message: statusPageErrorMessage(err),
                    onRetry: () =>
                        ref.invalidate(statusPageProvider(activeQuery)),
                  ),
                  data: (StatusPageData data) => _StatusBody(data: data),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _StatusError extends StatelessWidget {
  const _StatusError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: <Widget>[
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _StatusBody extends StatelessWidget {
  const _StatusBody({required this.data});

  final StatusPageData data;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(data.name, style: theme.textTheme.titleLarge)),
            Chip(
              label: Text(data.overallStatus),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (data.description != null && data.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(data.description!, style: theme.textTheme.bodyMedium),
          ),
        const SizedBox(height: 4),
        Text(
          'Uptime (30d): ${data.uptimePercentage.toStringAsFixed(2)}%',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Text('Monitors', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (data.monitors.isEmpty)
          const Text('No monitors on this page.')
        else
          for (final StatusPageMonitor monitor in data.monitors)
            Card(
              child: ListTile(
                title: Text(monitor.name),
                trailing: Chip(
                  label: Text(monitor.status),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        const SizedBox(height: 16),
        Text('Recent incidents', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (data.recentIncidents.isEmpty)
          const Text('No recent incidents.')
        else
          for (final StatusPageIncident incident in data.recentIncidents)
            Card(
              child: ListTile(
                title: Text(incident.monitorName ?? incident.id),
                subtitle: incident.startedAt == null
                    ? null
                    : Text('Started ${incident.startedAt}'),
                trailing: Chip(
                  label: Text(incident.status),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
      ],
    );
  }
}
