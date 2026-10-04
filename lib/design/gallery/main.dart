import 'package:flutter/material.dart';

import '../uptrack_design.dart';

/// Offline developer entrypoint. No API, auth, cache, push or production route.
void main() => runApp(const UptrackGallery());

class UptrackGallery extends StatefulWidget {
  const UptrackGallery({super.key});
  @override
  State<UptrackGallery> createState() => _UptrackGalleryState();
}

class _UptrackGalleryState extends State<UptrackGallery> {
  ThemeMode mode = ThemeMode.light;
  bool largeText = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Uptrack design gallery',
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: mode,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(largeText ? 2 : 1)),
      child: child!,
    ),
    home: Scaffold(
      appBar: AppBar(
        title: const Text('Design gallery'),
        actions: [
          IconButton(
            tooltip: 'Toggle 200% text',
            onPressed: () => setState(() => largeText = !largeText),
            icon: const Icon(Icons.text_fields),
          ),
          IconButton(
            tooltip: 'Toggle light and dark',
            onPressed: () => setState(
              () => mode = mode == ThemeMode.light
                  ? ThemeMode.dark
                  : ThemeMode.light,
            ),
            icon: const Icon(Icons.brightness_6_outlined),
          ),
        ],
      ),
      body: const UptrackContent(
        child: SingleChildScrollView(child: GalleryExamples()),
      ),
    ),
  );
}

class GalleryExamples extends StatefulWidget {
  const GalleryExamples({super.key});
  @override
  State<GalleryExamples> createState() => _GalleryExamplesState();
}

class _GalleryExamplesState extends State<GalleryExamples> {
  bool enabled = true;
  String selected = 'Open';
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const UptrackSection(
        title: 'Brand and type',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UptrackBrand(),
            Text('Monitoring without guesswork.'),
            UptrackDataText('99.95% · 120 ms · eu-central'),
          ],
        ),
      ),
      UptrackSection(
        title: 'Actions',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            UptrackButton(label: 'Save preferences', onPressed: () {}),
            UptrackButton(
              label: 'View monitors',
              kind: UptrackButtonKind.secondary,
              onPressed: () {},
            ),
            UptrackButton(
              label: 'Learn more',
              kind: UptrackButtonKind.quiet,
              onPressed: () {},
            ),
            UptrackButton(
              label: 'Revoke device',
              kind: UptrackButtonKind.destructive,
              onPressed: () {},
            ),
            const UptrackButton(
              label: 'Saving preferences',
              busy: true,
              onPressed: null,
            ),
            const UptrackButton(label: 'Unavailable offline', onPressed: null),
            UptrackButton(
              label: 'A long action label that must wrap on a compact phone',
              onPressed: () {},
            ),
          ],
        ),
      ),
      UptrackSection(
        title: 'Fields and choices',
        child: Column(
          children: [
            const TextField(
              decoration: InputDecoration(
                labelText: 'Email',
                helperText: 'A persistent label',
              ),
              keyboardType: TextInputType.emailAddress,
              autofillHints: [AutofillHints.email],
            ),
            const SizedBox(height: 12),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Monitor name',
                errorText: 'Enter a name before saving',
              ),
            ),
            const SizedBox(height: 12),
            const TextField(
              enabled: false,
              decoration: InputDecoration(labelText: 'Read-only sample'),
            ),
            SwitchListTile(
              title: const Text('Mobile push notifications'),
              value: enabled,
              onChanged: (value) => setState(() => enabled = value),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final label in ['All', 'Open'])
                  ChoiceChip(
                    label: Text(label),
                    selected: selected == label,
                    onSelected: (_) => setState(() => selected = label),
                  ),
              ],
            ),
          ],
        ),
      ),
      const UptrackSection(
        title: 'Health and lifecycle',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            UptrackStatusBadge(status: 'up'),
            UptrackStatusBadge(status: 'down'),
            UptrackStatusBadge(status: 'degraded'),
            UptrackStatusBadge(status: 'paused'),
            UptrackStatusBadge(status: 'unknown'),
            UptrackStatusBadge(status: 'visual_regression'),
            UptrackStatusBadge(status: 'partial_outage'),
            UptrackLifecycleBadge(open: true),
            UptrackLifecycleBadge(open: false),
            UptrackLifecycleBadge(open: true, acknowledged: true),
          ],
        ),
      ),
      const UptrackSection(
        title: 'Metrics',
        child: Column(
          children: [
            UptrackMetricTile(
              label: 'Average uptime',
              value: '99.95%',
              detail: 'Last 7 days',
            ),
            UptrackMetricTile(
              label: 'Response time',
              value: null,
              detail: 'Not measured yet',
            ),
          ],
        ),
      ),
      UptrackSection(
        title: 'Feedback and recovery',
        child: Column(
          children: [
            const UptrackNotice(
              message: 'Offline — showing cached data',
              kind: UptrackNoticeKind.offline,
            ),
            UptrackNotice(
              message: 'Could not save preferences. Your changes are retained.',
              kind: UptrackNoticeKind.error,
              actionLabel: 'Retry',
              onAction: () {},
            ),
            const UptrackNotice(
              message: 'Demo · sample data',
              kind: UptrackNoticeKind.sample,
            ),
            const UptrackNotice(message: 'Preferences saved.'),
            const UptrackStateView(message: 'Loading monitors', loading: true),
            const UptrackStateView(message: 'No monitors yet.'),
            UptrackStateView(
              message: 'No monitors match your search.',
              actionLabel: 'Clear filter',
              onAction: () {},
            ),
            UptrackStateView(
              message: 'No cached data is available offline.',
              actionLabel: 'Retry',
              onAction: () {},
            ),
          ],
        ),
      ),
      UptrackSection(
        title: 'Rows',
        child: Column(
          children: [
            UptrackDataRow(
              title: 'Public API with a long service name',
              details: const UptrackStatusBadge(status: 'down'),
              onTap: () {},
            ),
            UptrackDataRow(
              title: 'Checkout incident',
              details: const UptrackLifecycleBadge(
                open: true,
                acknowledged: true,
              ),
              onTap: () {},
            ),
          ],
        ),
      ),
      UptrackSection(
        title: 'Measured evidence',
        child: UptrackResponseChart(
          period: 'Last hour',
          summary: 'p50 120 ms · p95 140 ms',
          points: [
            UptrackChartPoint(
              time: DateTime.utc(2026, 10, 4, 10),
              milliseconds: 120,
            ),
            UptrackChartPoint(
              time: DateTime.utc(2026, 10, 4, 11),
              milliseconds: 140,
            ),
          ],
        ),
      ),
      UptrackSection(
        title: 'Native confirmation',
        child: UptrackButton(
          label: 'Preview confirmation',
          kind: UptrackButtonKind.secondary,
          onPressed: () => showUptrackConfirmation(
            context,
            title: 'Revoke sample device?',
            message: 'This is an offline gallery example.',
            confirmLabel: 'Revoke device',
            destructive: true,
          ),
        ),
      ),
    ],
  );
}
