import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/current_user.dart';
import '../auth/auth_controller.dart';

/// `GET /api/auth/me` for the settings profile section.
final FutureProvider<CurrentUserResponse> settingsProfileProvider =
    FutureProvider<CurrentUserResponse>((Ref ref) async {
      return ref.read(uptrackApiProvider).getMe();
    });

/// Settings profile section: signed-in user + org + plan (read-only).
class ProfileSection extends ConsumerWidget {
  const ProfileSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CurrentUserResponse> profile = ref.watch(
      settingsProfileProvider,
    );
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Profile', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          profile.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (Object err, StackTrace _) => _ProfileError(
              onRetry: () => ref.invalidate(settingsProfileProvider),
            ),
            data: (CurrentUserResponse me) => Card(
              child: Column(
                children: <Widget>[
                  _ProfileRow(label: 'Name', value: me.user.name),
                  const Divider(height: 1),
                  _ProfileRow(label: 'Email', value: me.user.email),
                  const Divider(height: 1),
                  _ProfileRow(
                    label: 'Organization',
                    value: me.organization.name,
                  ),
                  const Divider(height: 1),
                  _ProfileRow(
                    label: 'Plan',
                    value: planLabel(me.organization.plan),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: <Widget>[
            const Text(
              'Could not load your profile. Check your connection and try again.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// Display name for a plan id: `pro` → `Pro`.
String planLabel(String plan) =>
    plan.isEmpty ? plan : plan[0].toUpperCase() + plan.substring(1);
