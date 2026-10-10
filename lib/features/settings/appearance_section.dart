import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/appearance.dart';

/// Settings appearance section: follow the system, or force light or dark.
/// The choice is kept on this device only.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Appearance appearance = ref.watch(appearanceProvider);
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Appearance', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: appearance,
            builder: (BuildContext context, Widget? _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    key: const ValueKey<String>('appearance'),
                    showSelectedIcon: false,
                    segments: const <ButtonSegment<ThemeMode>>[
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined),
                        label: Text('System'),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Light'),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: <ThemeMode>{appearance.mode},
                    onSelectionChanged: (Set<ThemeMode> picked) =>
                        appearance.setMode(picked.single),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  appearance.mode == ThemeMode.system
                      ? 'Follows your device setting.'
                      : 'Saved on this device.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
