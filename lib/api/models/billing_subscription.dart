import 'package:intl/intl.dart';

/// Billing models for `GET /api/billing/subscription` (and the same body from
/// `POST /api/billing/apple/transactions`).
///
/// Shape mirror: `SubscriptionResponse` / `SubscriptionOut` in
/// `openapi-v2.json`, plus `provider` and `apple_product_id` (API contract in
/// `uptrack-spec/docs/app-review/uptrack-ios-1.0.0-resubmit-plan.md`), and
/// `grant` (OpenSpec 136).
class BillingSubscriptionInfo {
  const BillingSubscriptionInfo({
    required this.plan,
    this.subscription,
    this.grant,
  });

  factory BillingSubscriptionInfo.fromJson(Map<String, Object?> json) {
    final Object? raw = json['data'];
    final Object? rawGrant = json['grant'];
    return BillingSubscriptionInfo(
      plan: json['plan']! as String,
      subscription: raw is Map<String, Object?>
          ? BillingSubscription.fromJson(raw)
          : null,
      // A server before OpenSpec 136 sends no `grant`.
      grant: rawGrant is Map<String, Object?>
          ? BillingGrant.fromJson(rawGrant)
          : null,
    );
  }

  final String plan;
  final BillingSubscription? subscription;

  /// The live nonprofit grant (free Pro), or null. [subscription] stays the
  /// paid subscription.
  final BillingGrant? grant;
}

/// A live nonprofit grant: `GrantOut` in `openapi-v2.json` (OpenSpec 136).
class BillingGrant {
  const BillingGrant({
    required this.endsAt,
    required this.source,
    required this.domain,
  });

  factory BillingGrant.fromJson(Map<String, Object?> json) {
    return BillingGrant(
      endsAt: json['ends_at']! as String,
      source: json['source']! as String,
      domain: json['domain']! as String,
    );
  }

  final String endsAt;

  /// `tld`, `curated`, `uk_charity_commission`, `acnc`, `manual` or `admin`.
  final String source;
  final String domain;
}

/// The Current plan line for an org with a live grant, worded as on the web
/// (`uptrack-web` `src/lib/nonprofit.ts` `sponsoredUntil`): "Sponsored for
/// nonprofits until October 24, 2027." The date is the UTC day, as on the web.
String sponsoredUntil(String endsAt) {
  final DateTime? parsed = DateTime.tryParse(endsAt);
  final String day = parsed == null
      ? endsAt
      : DateFormat('MMMM d, y').format(parsed.toUtc());
  return 'Sponsored for nonprofits until $day.';
}

class BillingSubscription {
  const BillingSubscription({
    required this.id,
    required this.plan,
    required this.status,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.cancelledAt,
    this.provider = kProviderPaddle,
    this.appleProductId,
  });

  factory BillingSubscription.fromJson(Map<String, Object?> json) {
    return BillingSubscription(
      id: json['id']! as String,
      plan: json['plan']! as String,
      status: json['status']! as String,
      currentPeriodStart: json['current_period_start'] as String?,
      currentPeriodEnd: json['current_period_end'] as String?,
      cancelledAt: json['cancelled_at'] as String?,
      // A server without the field has only Paddle subscriptions.
      provider: json['provider'] as String? ?? kProviderPaddle,
      appleProductId: json['apple_product_id'] as String?,
    );
  }

  final String id;
  final String plan;
  final String status;
  final String? currentPeriodStart;
  final String? currentPeriodEnd;
  final String? cancelledAt;

  /// `paddle` or `apple`.
  final String provider;
  final String? appleProductId;

  bool get isApple => provider == kProviderApple;

  /// The subscription still blocks a second one (D7). The server treats
  /// every status except `cancelled` as live.
  bool get isLive => !const <String>{
    'cancelled',
    'canceled',
    'expired',
    'revoked',
    'refunded',
  }.contains(status);
}

const String kProviderPaddle = 'paddle';
const String kProviderApple = 'apple';

/// The org's live subscription, or null.
extension LiveSubscription on BillingSubscriptionInfo {
  BillingSubscription? get live =>
      subscription != null && subscription!.isLive ? subscription : null;
}

/// In-App Purchase on iOS (plan step 5b). Off by default, so `main` builds the
/// read-only billing section of build 1. Build with
/// `--dart-define=UPTRACK_APPLE_IAP=true` to sell the plans in the app.
/// Android never sells in the app (plan D9), whatever the define says.
const bool kAppleIapEnabled = bool.fromEnvironment('UPTRACK_APPLE_IAP');

/// Native purchase steering stays off until runtime storefront eligibility,
/// store-program enrollment and its reporting obligations are implemented.
/// A compile-time switch cannot establish any of those requirements.
const bool kBillingExternalLinkEnabled = false;

/// Web billing portal URL shown as read-only text while
/// [kBillingExternalLinkEnabled] is on (never opened from the app).
const String kBillingPortalUrl = 'https://uptrack.app/billing';
