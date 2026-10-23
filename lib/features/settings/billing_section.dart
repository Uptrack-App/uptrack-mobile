import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'profile_section.dart';

import '../../api/models/billing_subscription.dart';
import '../../api/models/current_user.dart';
import '../../design/uptrack_design.dart';
import '../auth/auth_controller.dart';
import '../billing/app_store.dart';
import '../billing/apple_purchase_controller.dart';
import '../billing/plans_screen.dart';

/// `GET /api/billing/subscription` for the settings billing section. It
/// loads again for each session, so the Plans screen never gates D7 on the
/// billing of the account before a sign-out.
final FutureProvider<BillingSubscriptionInfo> settingsBillingProvider =
    FutureProvider<BillingSubscriptionInfo>((Ref ref) async {
      watchAuthSession(ref);
      return ref.read(uptrackApiProvider).getBillingSubscription();
    });

/// Opens Apple's "Manage Subscriptions" sheet. Shows a message when the
/// sheet cannot open.
Future<void> showAppleManageSubscriptions(
  BuildContext context,
  WidgetRef ref,
) async {
  final AppStoreClient? store = ref.read(appStoreClientProvider);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    if (store == null) throw StateError('no App Store');
    await store.showManageSubscriptions();
  } on Object {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open the App Store. Open the Settings app, tap your name, then tap Subscriptions.',
        ),
      ),
    );
  }
}

/// Settings billing section: plan + subscription state.
///
/// With In-App Purchase on ([appleIapEnabledProvider], iOS only) the section
/// follows the subscription provider (plan step 5.7, D7, D8):
/// * Apple: "Manage subscription" opens Apple's sheet; the owner can change
///   the plan on the Plans screen (the same subscription group).
/// * Paddle: "Your plan is managed on the web", with no link.
/// * No subscription: the owner opens the Plans screen; other members see
///   the plan read-only.
///
/// With it off (Android, and iOS builds without the define) the section is
/// read-only, with no purchase code path.
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
                    subtitle: Text(planLabel(info.plan)),
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
                if (ref.watch(appleIapEnabledProvider))
                  _AppleBilling(info: info),
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

class _AppleBilling extends ConsumerWidget {
  const _AppleBilling({required this.info});

  final BillingSubscriptionInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final CurrentUserResponse? me = ref.watch(settingsProfileProvider).value;
    final bool isOwner = me?.user.role == 'owner';
    final BillingSubscription? live = info.live;
    void openPlans() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext _) => const PlansScreen()),
    );

    if (live != null && !live.isApple) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Your plan is managed on the web.',
          key: const ValueKey<String>('billing-managed-web'),
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (live != null) ...<Widget>[
            Text(
              'Managed by the App Store.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            UptrackButton(
              key: const ValueKey<String>('billing-manage-apple'),
              label: 'Manage subscription',
              kind: UptrackButtonKind.secondary,
              icon: Icons.open_in_new,
              onPressed: () => showAppleManageSubscriptions(context, ref),
            ),
            if (isOwner) ...<Widget>[
              const SizedBox(height: 8),
              UptrackButton(
                key: const ValueKey<String>('billing-change-plan'),
                label: 'Change plan',
                kind: UptrackButtonKind.quiet,
                onPressed: openPlans,
              ),
            ],
          ] else if (isOwner)
            UptrackButton(
              key: const ValueKey<String>('billing-see-plans'),
              label: 'See plans',
              icon: Icons.workspace_premium_outlined,
              onPressed: openPlans,
            )
          else if (me != null)
            Text(
              'Only the organization owner can buy a plan.',
              style: theme.textTheme.bodySmall,
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
