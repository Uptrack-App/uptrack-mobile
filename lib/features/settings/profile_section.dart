import '../../design/uptrack_design.dart';

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
            data: (CurrentUserResponse me) => Column(
              children: <Widget>[
                _ProfileRow(label: 'Name', value: me.user.name),
                _ProfileRow(label: 'Email', value: me.user.email),
                _ProfileRow(label: 'Organization', value: me.organization.name),
                _ProfileRow(label: 'Plan', value: me.organization.plan),
              ],
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
    return Card(
      child: ListTile(
        title: Text(label, style: Theme.of(context).textTheme.bodySmall),
        subtitle: UptrackDataText(
          value,
          style: Theme.of(context).textTheme.bodyLarge,
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
