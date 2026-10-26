import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/billing_subscription.dart';
import '../../api/models/current_user.dart';
import '../../design/uptrack_design.dart';
import '../settings/billing_section.dart' show settingsBillingProvider;
import '../settings/profile_section.dart' show settingsProfileProvider;
import 'app_store.dart';
import 'apple_plans.dart';
import 'apple_purchase_controller.dart';

/// The text that guideline 3.1.2 asks for next to an auto-renewable
/// subscription.
const String kSubscriptionTerms =
    'Plans are auto-renewable subscriptions. Payment is charged to your Apple '
    'ID when you confirm the purchase. A subscription renews automatically at '
    'the price shown unless you cancel it at least 24 hours before the end of '
    'the current period. Your Apple ID is charged for the renewal in the 24 '
    'hours before the period ends. Manage or cancel the subscription in your '
    'App Store account settings.';

/// Settings → Billing → Plans (plan step 5.5). Each paid plan shows its name,
/// the period, the App Store price, what it includes, the Terms of Use and
/// Privacy Policy links, and Restore Purchases. Only the owner buys (D8); an
/// organization that pays on the web cannot buy here (D7).
class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  BillingPeriod _period = BillingPeriod.monthly;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ApplePurchaseState purchase = ref.watch(
      applePurchaseControllerProvider,
    );
    final AsyncValue<Map<String, StoreProduct>> products = ref.watch(
      appleProductsProvider,
    );
    final CurrentUserResponse? me = ref.watch(settingsProfileProvider).value;
    final BillingSubscriptionInfo? billing = ref
        .watch(settingsBillingProvider)
        .value;
    final BillingSubscription? live = billing?.live;
    final bool isOwner = me?.user.role == 'owner';
    final bool paysOnWeb = live != null && !live.isApple;
    final bool canBuy = isOwner && !paysOnWeb && me != null && billing != null;
    final String currentPlan = billing?.plan ?? me?.organization.plan ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Plans')),
      body: UptrackContent(
        maxWidth: 680,
        child: ListView(
          key: const ValueKey<String>('plans-list'),
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (purchase.notice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: UptrackNotice(
                  key: const ValueKey<String>('purchase-notice'),
                  message: purchase.notice!.message,
                  kind: purchase.notice!.kind == PurchaseNoticeKind.error
                      ? UptrackNoticeKind.error
                      : UptrackNoticeKind.info,
                  actionLabel: 'Dismiss',
                  onAction: () => ref
                      .read(applePurchaseControllerProvider.notifier)
                      .clearNotice(),
                ),
              ),
            if (paysOnWeb)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: UptrackNotice(
                  message: 'Your plan is managed on the web.',
                ),
              )
            else if (me != null && !isOwner)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: UptrackNotice(
                  message:
                      'Only the organization owner can buy or change the plan.',
                ),
              ),
            if (products.hasError)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: UptrackNotice(
                  message: 'Could not load the prices from the App Store. Check your connection and try again.',
                  kind: UptrackNoticeKind.error,
                  actionLabel: 'Try again',
                  onAction: () => ref.invalidate(appleProductsProvider),
                ),
              ),
            Center(
              child: SegmentedButton<BillingPeriod>(
                key: const ValueKey<String>('plans-period'),
                segments: const <ButtonSegment<BillingPeriod>>[
                  ButtonSegment<BillingPeriod>(
                    value: BillingPeriod.monthly,
                    label: Text('Monthly'),
                  ),
                  ButtonSegment<BillingPeriod>(
                    value: BillingPeriod.yearly,
                    label: Text('Yearly'),
                  ),
                ],
                selected: <BillingPeriod>{_period},
                onSelectionChanged: (Set<BillingPeriod> s) =>
                    setState(() => _period = s.first),
              ),
            ),
            const SizedBox(height: 12),
            for (final PlanFacts plan in kPaidPlans)
              _PlanCard(
                facts: plan,
                product: appleProductFor(plan.plan, _period),
                storeProduct: products
                    .value?[appleProductFor(plan.plan, _period).productId],
                loadingPrice: products.isLoading,
                // A grant-only org already has the grant's plan, so buying
                // it would charge for nothing; a higher plan stays on sale
                // (OpenSpec 136 D13).
                isCurrent:
                    (live != null &&
                        live.isApple &&
                        live.appleProductId ==
                            appleProductFor(plan.plan, _period).productId) ||
                    (live == null &&
                        billing?.grant != null &&
                        currentPlan == plan.plan),
                isCurrentPlan: currentPlan == plan.plan,
                hasAppleSubscription: live != null && live.isApple,
                canBuy: canBuy,
                busy:
                    purchase.busyProductId ==
                    appleProductFor(plan.plan, _period).productId,
                anyBusy: purchase.busy,
                onBuy: (String productId) => ref
                    .read(applePurchaseControllerProvider.notifier)
                    .buy(productId),
              ),
            const SizedBox(height: 8),
            Text(kSubscriptionTerms, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                TextButton(
                  key: const ValueKey<String>('terms-of-use'),
                  onPressed: () => _open(kTermsOfUseUrl),
                  child: const Text('Terms of Use'),
                ),
                TextButton(
                  key: const ValueKey<String>('privacy-policy'),
                  onPressed: () => _open(kPrivacyPolicyUrl),
                  child: const Text('Privacy Policy'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            UptrackButton(
              key: const ValueKey<String>('restore-purchases'),
              label: 'Restore Purchases',
              kind: UptrackButtonKind.secondary,
              busy: purchase.restoring,
              onPressed: purchase.busy
                  ? null
                  : () => ref
                        .read(applePurchaseControllerProvider.notifier)
                        .restore(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(Uri url) async {
    final AppStoreClient? store = ref.read(appStoreClientProvider);
    try {
      await store?.openUrl(url);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.facts,
    required this.product,
    required this.storeProduct,
    required this.loadingPrice,
    required this.isCurrent,
    required this.isCurrentPlan,
    required this.hasAppleSubscription,
    required this.canBuy,
    required this.busy,
    required this.anyBusy,
    required this.onBuy,
  });

  final PlanFacts facts;
  final AppleProduct product;
  final StoreProduct? storeProduct;
  final bool loadingPrice;

  /// The org's Apple subscription is this product.
  final bool isCurrent;

  /// The org has this plan now (any provider, any period).
  final bool isCurrentPlan;
  final bool hasAppleSubscription;
  final bool canBuy;
  final bool busy;
  final bool anyBusy;
  final ValueChanged<String> onBuy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String period = product.period == BillingPeriod.monthly
        ? '1 month'
        : '1 year';
    final String per = product.period == BillingPeriod.monthly
        ? 'month'
        : 'year';
    final StoreProduct? sp = storeProduct;
    final String priceText = sp != null
        ? '${sp.displayPrice} / $per'
        : loadingPrice
        ? 'Loading the App Store price…'
        : 'Not available in the App Store right now.';
    final String label = isCurrent
        ? 'Current plan'
        : hasAppleSubscription
        ? 'Switch to ${facts.name}'
        : 'Subscribe to ${facts.name}';

    return Card(
      key: ValueKey<String>('plan-${facts.plan}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(facts.name, style: theme.textTheme.titleLarge),
                ),
                if (isCurrentPlan)
                  const Chip(
                    label: Text('Your plan'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(facts.description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
              priceText,
              key: ValueKey<String>('price-${product.productId}'),
              style: theme.textTheme.titleMedium,
            ),
            Text(
              'Auto-renewing subscription. Period: $period.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final PlanFeature f in facts.features)
              Semantics(
                label: f.included
                    ? 'Included: ${f.name}'
                    : 'Not included: ${f.name}',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        f.included ? Icons.check : Icons.remove,
                        size: 18,
                        color: f.included
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f.included ? f.name : 'Not included: ${f.name}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            UptrackButton(
              key: ValueKey<String>('buy-${product.productId}'),
              label: label,
              busy: busy,
              onPressed: canBuy && sp != null && !isCurrent && !anyBusy
                  ? () => onBuy(product.productId)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
