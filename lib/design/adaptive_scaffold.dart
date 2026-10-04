import 'package:flutter/material.dart';

/// Presentation only. Route selection, tab restoration and auth stay caller-owned.
class UptrackAdaptiveScaffold extends StatelessWidget {
  const UptrackAdaptiveScaffold({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;
  static const labels = ['Dashboard', 'Monitors', 'Incidents', 'Settings'];
  static const icons = [
    Icons.dashboard_outlined,
    Icons.monitor_heart_outlined,
    Icons.warning_amber_outlined,
    Icons.settings_outlined,
  ];
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 600 || constraints.maxHeight < 480) {
        return Scaffold(
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: [
              for (var i = 0; i < labels.length; i++)
                NavigationDestination(
                  key: ValueKey('destination-$i'),
                  icon: Icon(icons[i]),
                  label: labels[i],
                ),
            ],
          ),
        );
      }
      final extended =
          constraints.maxWidth >= 840 &&
          MediaQuery.textScalerOf(context).scale(14) <= 21;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: selectedIndex,
                extended: extended,
                labelType: extended
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                onDestinationSelected: onDestinationSelected,
                destinations: [
                  for (var i = 0; i < labels.length; i++)
                    NavigationRailDestination(
                      icon: Icon(icons[i]),
                      label: Text(labels[i]),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: child),
            ],
          ),
        ),
      );
    },
  );
}
