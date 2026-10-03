import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/device_token.dart';
import '../auth/auth_controller.dart';
import 'billing_section.dart';
import 'danger_zone_section.dart';
import 'device_tokens_controller.dart';
import 'notification_prefs_section.dart';
import 'profile_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        key: const ValueKey<String>('settings-list'),
        children: const <Widget>[
          ProfileSection(),
          NotificationPrefsSection(),
          BillingSection(),
          _DevicesSection(),
          DangerZoneSection(),
        ],
      ),
    );
  }
}

/// Settings section listing `GET /api/auth/device-tokens` with per-device
/// revoke. Covers loading / empty / error states.
class _DevicesSection extends ConsumerWidget {
  const _DevicesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DeviceTokensState state = ref.watch(deviceTokensControllerProvider);
    final String? currentDeviceId = ref.watch(
      authControllerProvider.select((AuthState s) => s.deviceTokenId),
    );
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Devices', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Each signed-in device holds its own token. Revoking one signs that device out.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (state.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (state.errorMessage != null && state.devices.isEmpty)
            _DevicesError(
              message: state.errorMessage!,
              onRetry: () =>
                  ref.read(deviceTokensControllerProvider.notifier).load(),
            )
          else if (state.devices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No devices signed in.')),
            )
          else
            for (final DeviceToken device in state.devices)
              _DeviceRow(
                device: device,
                isCurrent: device.id == currentDeviceId,
                isRevoking: state.revokingIds.contains(device.id),
                onRevoke: () => _revoke(context, ref, device.id),
              ),
        ],
      ),
    );
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref, String id) async {
    final bool ok = await ref
        .read(deviceTokensControllerProvider.notifier)
        .revoke(id);
    if (!ok && context.mounted) {
      final String message =
          ref.read(deviceTokensControllerProvider).errorMessage ??
          'Could not revoke that device.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _DevicesError extends StatelessWidget {
  const _DevicesError({required this.message, required this.onRetry});

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
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.isCurrent,
    required this.isRevoking,
    required this.onRevoke,
  });

  final DeviceToken device;
  final bool isCurrent;
  final bool isRevoking;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final String label = isCurrent
        ? 'Device ${device.displayName}, signed in ${device.createdAt}, '
              'this device'
        : 'Device ${device.displayName}, signed in ${device.createdAt}';
    return Semantics(
      label: label,
      container: true,
      explicitChildNodes: true,
      child: Card(
        child: ListTile(
          title: Row(
            children: <Widget>[
              Expanded(child: Text(device.displayName)),
              if (isCurrent)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Chip(
                    label: Text('This device'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          subtitle: Text('Signed in ${device.createdAt}'),
          trailing: isRevoking
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  key: ValueKey<String>('revoke-${device.id}'),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Revoke ${device.displayName}',
                  onPressed: onRevoke,
                ),
        ),
      ),
    );
  }
}
