import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/models/billing_subscription.dart';
import 'package:uptrack_mobile/api/models/current_user.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';
import 'package:uptrack_mobile/features/auth/auth_controller.dart';
import 'package:uptrack_mobile/features/settings/billing_section.dart';
import 'package:uptrack_mobile/features/settings/profile_section.dart';

import '../auth/auth_test.dart' show FakeAdapter, jsonResponse, meFixture;

class _Auth extends AuthController {
  @override
  AuthState build() =>
      const AuthState(status: AuthStatus.signedIn, deviceTokenId: 'dt-a');

  void set(AuthState next) => state = next;
}

/// The profile and the billing of the Settings screen (and the Plans
/// screen, which gates D7 and D8 on them) belong to the account that is
/// signed in now, not to the account before a sign-out.
void main() {
  test(
    'a new sign-in loads the profile and billing of the new account',
    () async {
      String role = 'owner';
      String plan = 'free';
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:4000'));
      dio.httpClientAdapter = FakeAdapter((RequestOptions o) async {
        if (o.path == kGetMePath) {
          final Map<String, Object?> me = meFixture();
          (me['user']! as Map<String, Object?>)['role'] = role;
          return jsonResponse(me);
        }
        return jsonResponse(<String, Object?>{'plan': plan, 'data': null});
      });
      final ProviderContainer c = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          uptrackApiProvider.overrideWithValue(UptrackApi(dio: dio)),
        ],
      );
      addTearDown(c.dispose);

      final CurrentUserResponse a = await c.read(
        settingsProfileProvider.future,
      );
      final BillingSubscriptionInfo billingA = await c.read(
        settingsBillingProvider.future,
      );
      expect(a.user.role, 'owner');
      expect(billingA.plan, 'free');

      final _Auth auth = c.read(authControllerProvider.notifier) as _Auth;
      auth.set(const AuthState());
      role = 'member';
      plan = 'team';
      auth.set(
        const AuthState(status: AuthStatus.signedIn, deviceTokenId: 'dt-b'),
      );

      final CurrentUserResponse b = await c.read(
        settingsProfileProvider.future,
      );
      final BillingSubscriptionInfo billingB = await c.read(
        settingsBillingProvider.future,
      );
      expect(b.user.role, 'member');
      expect(billingB.plan, 'team');
    },
  );
}
