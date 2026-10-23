/// The paid plans that the iOS app sells with In-App Purchase (plan D6 in
/// `uptrack-spec/docs/app-review/uptrack-ios-1.0.0-resubmit-plan.md`).
///
/// The product IDs must match App Store Connect and the server's product to
/// plan map. Prices are NEVER written here: the Plans screen shows the price
/// that the App Store returns for the user's storefront.
library;

/// The renewal period of an auto-renewable subscription.
enum BillingPeriod { monthly, yearly }

/// One App Store product: an auto-renewable subscription in the "Uptrack"
/// subscription group.
class AppleProduct {
  const AppleProduct({
    required this.productId,
    required this.plan,
    required this.period,
  });

  final String productId;

  /// The server plan name: `pro`, `team` or `business`.
  final String plan;
  final BillingPeriod period;
}

const List<AppleProduct> kAppleProducts = <AppleProduct>[
  AppleProduct(
    productId: 'app.uptrack.mobile.pro.monthly',
    plan: 'pro',
    period: BillingPeriod.monthly,
  ),
  AppleProduct(
    productId: 'app.uptrack.mobile.pro.yearly',
    plan: 'pro',
    period: BillingPeriod.yearly,
  ),
  AppleProduct(
    productId: 'app.uptrack.mobile.team.monthly',
    plan: 'team',
    period: BillingPeriod.monthly,
  ),
  AppleProduct(
    productId: 'app.uptrack.mobile.team.yearly',
    plan: 'team',
    period: BillingPeriod.yearly,
  ),
  AppleProduct(
    productId: 'app.uptrack.mobile.business.monthly',
    plan: 'business',
    period: BillingPeriod.monthly,
  ),
  AppleProduct(
    productId: 'app.uptrack.mobile.business.yearly',
    plan: 'business',
    period: BillingPeriod.yearly,
  ),
];

/// All product IDs, for the App Store product query.
final Set<String> kAppleProductIds = <String>{
  for (final AppleProduct p in kAppleProducts) p.productId,
};

AppleProduct? appleProductById(String? productId) {
  for (final AppleProduct p in kAppleProducts) {
    if (p.productId == productId) return p;
  }
  return null;
}

AppleProduct appleProductFor(String plan, BillingPeriod period) =>
    kAppleProducts.firstWhere(
      (AppleProduct p) => p.plan == plan && p.period == period,
    );

/// One line of "what the plan includes".
class PlanFeature {
  const PlanFeature(this.name, {this.included = true});

  final String name;
  final bool included;
}

/// What a plan includes. The same facts as `tiers` in
/// `uptrack-web/src/lib/plans.ts` (with `MONITOR_EDGE_LIVE = true` in
/// `src/lib/check-locations.ts`). When the web changes, change this too.
class PlanFacts {
  const PlanFacts({
    required this.plan,
    required this.name,
    required this.description,
    required this.features,
  });

  final String plan;
  final String name;
  final String description;
  final List<PlanFeature> features;
}

const List<PlanFacts> kPaidPlans = <PlanFacts>[
  PlanFacts(
    plan: 'pro',
    name: 'Pro',
    description: 'For serious monitoring on a budget.',
    features: <PlanFeature>[
      PlanFeature('50 monitors — all at 30s'),
      PlanFeature('12 check locations (you pick)'),
      PlanFeature('Email, Slack, Discord, Telegram, webhook alerts'),
      PlanFeature('5 status pages'),
      PlanFeature('3 team members'),
      PlanFeature('2 years history'),
      PlanFeature('Keyword monitoring'),
      PlanFeature('Custom domain', included: false),
    ],
  ),
  PlanFacts(
    plan: 'team',
    name: 'Team',
    description: 'For teams that run critical infrastructure.',
    features: <PlanFeature>[
      PlanFeature('200 monitors — all at 30s'),
      PlanFeature('All 22 check locations'),
      PlanFeature('Unlimited alert channels'),
      PlanFeature('Unlimited status pages'),
      PlanFeature('5 team members'),
      PlanFeature('2 years history'),
      PlanFeature('Escalation policies'),
      PlanFeature('Custom domain + theming'),
      PlanFeature('SSO / Whitelabel', included: false),
    ],
  ),
  PlanFacts(
    plan: 'business',
    name: 'Business',
    description: 'For organizations that need it all.',
    features: <PlanFeature>[
      PlanFeature('1,000 monitors — all at 30s'),
      PlanFeature('All 22 check locations'),
      PlanFeature('Unlimited alert channels'),
      PlanFeature('Unlimited status pages'),
      PlanFeature('15 team members'),
      PlanFeature('5 years history'),
      PlanFeature('Priority support'),
      PlanFeature('Whitelabel + custom sender'),
      PlanFeature('SSO / SAML'),
    ],
  ),
];

/// Guideline 3.1.2: the Terms of Use (EULA) and the Privacy Policy, linked
/// from the purchase screen. Both pages exist on uptrack-web `main`
/// (`src/routes/_site/terms.tsx`, `src/routes/_site/privacy.tsx`).
final Uri kTermsOfUseUrl = Uri.parse('https://uptrack.app/terms');
final Uri kPrivacyPolicyUrl = Uri.parse('https://uptrack.app/privacy');
