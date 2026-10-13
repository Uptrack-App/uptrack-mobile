import '../../design/uptrack_design.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../dashboard/dashboard_controller.dart';
import 'billing_section.dart';

const List<String> checkoutPaidPlans = <String>['pro', 'team', 'business'];

/// A browser return is navigation only; it never grants access or exchanges
/// credentials. The app must independently read the signed-in account's plan.
String? checkoutReturnLocation(Uri? uri) {
  if (uri == null || uri.path != '/billing/return') return null;
  final String? plan = uri.queryParameters['plan'];
  return checkoutPaidPlans.contains(plan)
      ? '/billing/return?plan=$plan'
      : '/billing/return';
}

class CheckoutReturnState {
  const CheckoutReturnState({
    required this.email,
    required this.plan,
    required this.ready,
  });

  final String email;
  final String plan;
  final bool ready;
}

final checkoutReturnProvider = FutureProvider.autoDispose
    .family<CheckoutReturnState, String?>((
      Ref ref,
      String? expectedPlan,
    ) async {
      bool disposed = false;
      ref.onDispose(() => disposed = true);
      final api = ref.read(uptrackApiProvider);
      final me = await api.getMe();
      final billing = await api.getBillingSubscription();
      final bool ready =
          checkoutPaidPlans.contains(billing.plan) &&
          (expectedPlan == null || billing.plan == expectedPlan) &&
          billing.subscription?.plan == billing.plan &&
          <String>[
            'active',
            'trialing',
          ].contains(billing.subscription?.status) &&
          me.organization.plan == billing.plan &&
          me.organization.featuresEnabled != false;
      if (ready && !disposed) {
        ref.invalidate(settingsBillingProvider);
        ref.invalidate(dashboardProvider);
      }
      return CheckoutReturnState(
        email: me.user.email,
        plan: billing.plan,
        ready: ready,
      );
    });

class CheckoutReturnScreen extends ConsumerWidget {
  const CheckoutReturnScreen({super.key, this.expectedPlan});

  final String? expectedPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(checkoutReturnProvider(expectedPlan));
    return Scaffold(
      appBar: AppBar(title: const Text('Your subscription')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: status.when(
              loading: () => const Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Checking your subscription…'),
                ],
              ),
              error: (Object error, StackTrace stack) => Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text(
                    'Could not check your subscription. Check your connection and try again.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        ref.invalidate(checkoutReturnProvider(expectedPlan)),
                    child: const Text('Try again'),
                  ),
                ],
              ),
              data: (CheckoutReturnState data) => Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    data.ready ? Icons.check_circle_outline : Icons.schedule,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    data.ready
                        ? 'Your ${data.plan} plan is ready'
                        : 'Your subscription is not active yet',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  UptrackDataText(
                    'Signed in as ${data.email}',
                    textAlign: TextAlign.center,
                  ),
                  if (!data.ready) ...<Widget>[
                    const SizedBox(height: 12),
                    const Text(
                      'Use the same account you used in the browser. If you just paid, confirmation may still be processing. Please do not pay again.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          ref.invalidate(checkoutReturnProvider(expectedPlan)),
                      child: const Text('Check again'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () => context.go(data.ready ? '/' : '/settings'),
                    child: Text(
                      data.ready
                          ? 'Continue to dashboard'
                          : 'View account settings',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
