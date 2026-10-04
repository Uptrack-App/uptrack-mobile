import '../../design/uptrack_design.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';
import 'social_login.dart';
import 'demo_session.dart' show isAndroidDemoAvailable;

/// Passwordless sign-up/sign-in, with social login and optional 2FA.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.returnLocation = '/', this.magicLink});

  final String returnLocation;
  final Uri? magicLink;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _magicToken = TextEditingController();
  String? _linkError;

  @override
  void initState() {
    super.initState();
    _receiveLink();
  }

  @override
  void didUpdateWidget(LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.magicLink != oldWidget.magicLink) _receiveLink();
  }

  void _receiveLink() {
    final uri = widget.magicLink;
    if (uri == null) return;
    final link = parseMagicLink(uri);
    _linkError = link == null
        ? 'Invalid sign-in link. Request a new link below.'
        : null;
    if (link == null) return;
    _email.text = link.email;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(authControllerProvider.notifier)
            .receiveMagicLink(email: link.email, token: link.token);
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _magicToken.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (
      AuthState? previous,
      AuthState next,
    ) {
      if (next.status == AuthStatus.signedIn &&
          previous?.status != AuthStatus.signedIn) {
        // maybeOf: null when pumped without a router in widget tests
        // (state change is asserted directly instead).
        GoRouter.maybeOf(context)?.go(widget.returnLocation);
      }
    });
    final AuthState auth = ref.watch(authControllerProvider);
    final AuthController controller = ref.read(authControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Uptrack')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: <Widget>[
                if (auth.status != AuthStatus.needsTwoFactor) ...<Widget>[
                  const UptrackBrand(),
                  const SizedBox(height: 16),
                  const Text('Sign up or sign in with your Uptrack account.'),
                  const SizedBox(height: 16),
                  _SocialLoginButtons(
                    isLoading: auth.isLoading,
                    onSignIn: controller.signInWithSocial,
                  ),
                  if (isAndroidDemoAvailable) ...<Widget>[
                    OutlinedButton.icon(
                      key: const ValueKey<String>('try-demo'),
                      onPressed: auth.isLoading
                          ? null
                          : () => context.go('/demo'),
                      icon: const Icon(Icons.explore_outlined),
                      label: const Text('Try demo'),
                    ),
                    const Text(
                      'Explore sample monitors and incidents. No account needed.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
                if (widget.returnLocation.startsWith(
                  '/billing/return',
                )) ...<Widget>[
                  const Text(
                    'Sign in with the same account you used in the browser to see your subscription.',
                  ),
                  const SizedBox(height: 16),
                ],
                if (auth.status == AuthStatus.needsTwoFactor)
                  _TwoFactorForm(
                    code: _code,
                    isLoading: auth.isLoading,
                    errorMessage: auth.errorMessage,
                    onSubmit: () {
                      if (_formKey.currentState!.validate()) {
                        controller.submitTwoFactorCode(_code.text);
                      }
                    },
                    onCancel: controller.cancelTwoFactor,
                  )
                else
                  _MagicLinkForm(
                    email: _email,
                    magicToken: _magicToken,
                    isLoading: auth.isLoading,
                    errorMessage: _linkError ?? auth.errorMessage,
                    magicLinkSent: auth.magicLinkSent,
                    onRequest: () {
                      if (validateEmail(_email.text) == null) {
                        setState(() => _linkError = null);
                        controller.requestMagicLink(_email.text);
                      } else {
                        _formKey.currentState!.validate();
                      }
                    },
                    onVerify: () {
                      if (_formKey.currentState!.validate()) {
                        controller.verifyMagicLink(
                          email: _email.text,
                          token: magicLinkInputToken(
                            input: _magicToken.text,
                            email: _email.text,
                          )!,
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class _TwoFactorForm extends StatelessWidget {
  const _TwoFactorForm({
    required this.code,
    required this.isLoading,
    required this.errorMessage,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController code;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text('Enter the 6-digit code from your authenticator app.'),
        const SizedBox(height: 12),
        if (errorMessage != null) _ErrorText(message: errorMessage!),
        TextFormField(
          controller: code,
          decoration: const InputDecoration(labelText: '2FA code'),
          keyboardType: TextInputType.number,
          autofillHints: const <String>[AutofillHints.oneTimeCode],
          validator: validateTwoFactorCode,
          onFieldSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 20),
        UptrackButton(label: 'Verify', onPressed: onSubmit, busy: isLoading),
        TextButton(
          onPressed: isLoading ? null : onCancel,
          child: const Text('Use a different account'),
        ),
      ],
    );
  }
}

class _MagicLinkForm extends StatelessWidget {
  const _MagicLinkForm({
    required this.email,
    required this.magicToken,
    required this.isLoading,
    required this.errorMessage,
    required this.magicLinkSent,
    required this.onRequest,
    required this.onVerify,
  });

  final TextEditingController email;
  final TextEditingController magicToken;
  final bool isLoading;
  final String? errorMessage;
  final bool magicLinkSent;
  final VoidCallback onRequest;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (errorMessage != null) _ErrorText(message: errorMessage!),
        TextFormField(
          controller: email,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const <String>[AutofillHints.email],
          validator: validateEmail,
        ),
        const SizedBox(height: 12),
        UptrackButton(
          label: 'Email me a sign-in link',
          onPressed: onRequest,
          busy: isLoading,
        ),
        if (magicLinkSent) ...<Widget>[
          const SizedBox(height: 8),
          const Text(
            'Check your email and open the link, then tap Open Uptrack to finish signing in. You can also paste the link below.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: magicToken,
            decoration: const InputDecoration(
              labelText: 'Sign-in link or code',
            ),
            autocorrect: false,
            enableSuggestions: false,
            obscureText: true,
            validator: (String? value) =>
                magicLinkInputToken(input: value ?? '', email: email.text) ==
                    null
                ? 'Paste the sign-in link for this email address'
                : null,
            onFieldSubmitted: (_) => onVerify(),
          ),
          const SizedBox(height: 12),
          UptrackButton(label: 'Sign in', onPressed: onVerify, busy: isLoading),
        ],
      ],
    );
  }
}

class _SocialLoginButtons extends ConsumerWidget {
  const _SocialLoginButtons({required this.isLoading, required this.onSignIn});
  final bool isLoading;
  final Future<void> Function(String) onSignIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(socialProvidersProvider)
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: LinearProgressIndicator(),
          ),
          error: (_, _) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextButton(
              onPressed: isLoading
                  ? null
                  : () => ref.invalidate(socialProvidersProvider),
              child: const Text('Retry loading social sign-in'),
            ),
          ),
          data: (providers) => providers.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final provider in <String>['google', 'github'])
                      if (providers.contains(provider))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: OutlinedButton(
                            onPressed: isLoading
                                ? null
                                : () => onSignIn(provider),
                            child: Text(
                              'Continue with ${provider == 'google' ? 'Google' : 'GitHub'}',
                            ),
                          ),
                        ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text('or use email', textAlign: TextAlign.center),
                    ),
                  ],
                ),
        );
  }
}
