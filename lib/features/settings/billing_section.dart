import '../../design/uptrack_design.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/billing_subscription.dart';
import '../auth/auth_controller.dart';

/// `GET /api/billing/subscription` for the settings billing section.
final FutureProvider<BillingSubscriptionInfo> settingsBillingProvider =
    FutureProvider<BillingSubscriptionInfo>((Ref ref) async {
      return ref.read(uptrackApiProvider).getBillingSubscription();
    });

/// Settings billing section: read-only plan + subscription state plus the
/// region-gated web management link (plain text — no IAP code anywhere).
class BillingSection extends ConsumerWidget {
  const BillingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<BillingSubscriptionInfo> billing = ref.watch(
      settingsBillingProvider,
    );
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Billing', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Your current plan and subscription status.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          billing.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (Object err, StackTrace _) => _BillingError(
              onRetry: () => ref.invalidate(settingsBillingProvider),
            ),
            data: (BillingSubscriptionInfo info) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Card(
                  child: ListTile(
                    title: const Text('Current plan'),
                    subtitle: UptrackDataText(info.plan),
                  ),
                ),
                if (info.subscription != null)
                  Card(
                    child: ListTile(
                      title: Text('Subscription ${info.subscription!.status}'),
                      subtitle: info.subscription!.currentPeriodEnd == null
                          ? null
                          : Text(
                              'Renews ${info.subscription!.currentPeriodEnd}',
                            ),
                    ),
                  )
                else
                  const Card(
                    child: ListTile(
                      title: Text('Subscription'),
                      subtitle: Text('No active subscription.'),
                    ),
                  ),
                if (kBillingExternalLinkEnabled)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Manage billing on the web: $kBillingPortalUrl',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingError extends StatelessWidget {
  const _BillingError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: <Widget>[
            const Text(
              'Could not load billing info. Check your connection and try again.',
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
