/// Read-only billing models for `GET /api/billing/subscription`.
///
/// Shape mirror: `SubscriptionResponse` / `SubscriptionOut` in
/// `openapi-v2.json`. Display-only: plan upgrades/downgrades happen on the
/// web (region-gated link, no IAP code anywhere in the app).
class BillingSubscriptionInfo {
  const BillingSubscriptionInfo({required this.plan, this.subscription});

  factory BillingSubscriptionInfo.fromJson(Map<String, Object?> json) {
    final Object? raw = json['data'];
    return BillingSubscriptionInfo(
      plan: json['plan']! as String,
      subscription: raw is Map<String, Object?>
          ? BillingSubscription.fromJson(raw)
          : null,
    );
  }

  final String plan;
  final BillingSubscription? subscription;
}

class BillingSubscription {
  const BillingSubscription({
    required this.id,
    required this.plan,
    required this.status,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.cancelledAt,
  });

  factory BillingSubscription.fromJson(Map<String, Object?> json) {
    return BillingSubscription(
      id: json['id']! as String,
      plan: json['plan']! as String,
      status: json['status']! as String,
      currentPeriodStart: json['current_period_start'] as String?,
      currentPeriodEnd: json['current_period_end'] as String?,
      cancelledAt: json['cancelled_at'] as String?,
    );
  }

  final String id;
  final String plan;
  final String status;
  final String? currentPeriodStart;
  final String? currentPeriodEnd;
  final String? cancelledAt;
}

/// Native purchase steering stays off until runtime storefront eligibility,
/// store-program enrollment and its reporting obligations are implemented.
/// A compile-time switch cannot establish any of those requirements.
const bool kBillingExternalLinkEnabled = false;

/// Web billing portal URL shown as read-only text (never opened from an
/// in-app purchase flow — there is none).
const String kBillingPortalUrl = 'https://uptrack.app/billing';
