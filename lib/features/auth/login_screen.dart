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

    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = dark ? UptrackColors.upDark : UptrackColors.upLight;
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.of(context).accessibleNavigation;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                accent.withValues(alpha: dark ? .10 : .06),
                theme.colorScheme.surface,
              ),
              theme.colorScheme.surface,
              theme.colorScheme.surface,
            ],
            stops: const [0, .48, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  children: [
                    _LoginEntrance(
                      reduceMotion: reduceMotion,
                      start: 0,
                      child: Row(
                        children: [
                          const Expanded(child: UptrackBrand()),
                          ExcludeSemantics(
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: accent.withValues(alpha: .18),
                                ),
                              ),
                              child: Icon(
                                auth.status == AuthStatus.needsTwoFactor
                                    ? Icons.shield_outlined
                                    : Icons.monitor_heart_outlined,
                                color: accent,
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    _LoginEntrance(
                      reduceMotion: reduceMotion,
                      start: .12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome to Uptrack',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: -.8,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            auth.status == AuthStatus.needsTwoFactor
                                ? 'One more step to keep your account secure.'
                                : 'Your uptime, always in view.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    _LoginEntrance(
                      reduceMotion: reduceMotion,
                      start: .24,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(
                            UptrackRadii.frame,
                          ),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                          boxShadow: dark
                              ? UptrackShadows.raisedDark
                              : UptrackShadows.raisedLight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (auth.status != AuthStatus.needsTwoFactor) ...[
                              Text(
                                'Sign up or sign in with your Uptrack account.',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 20),
                              _SocialLoginButtons(
                                isLoading: auth.isLoading,
                                onSignIn: controller.signInWithSocial,
                              ),
                            ],
                            if (widget.returnLocation.startsWith(
                              '/billing/return',
                            )) ...[
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
                    if (isAndroidDemoAvailable &&
                        auth.status != AuthStatus.needsTwoFactor) ...[
                      const SizedBox(height: 24),
                      _LoginEntrance(
                        reduceMotion: reduceMotion,
                        start: .38,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton.icon(
                              key: const ValueKey<String>('try-demo'),
                              onPressed: auth.isLoading
                                  ? null
                                  : () => context.go('/demo'),
                              icon: const Icon(
                                Icons.explore_outlined,
                                size: 20,
                              ),
                              label: const Text('Try demo'),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Explore sample monitors and incidents. No account needed.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Finite, staggered entrance: never loops or blocks an input. Honor the OS
/// reduced-motion preference and accessibility navigation immediately.
class _LoginEntrance extends StatelessWidget {
  const _LoginEntrance({
    required this.child,
    required this.start,
    required this.reduceMotion,
  });
  final Widget child;
  final double start;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: reduceMotion ? 1 : 0, end: 1),
    duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 720),
    curve: Interval(start, 1, curve: Curves.easeOutCubic),
    child: child,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 18 * (1 - value)),
        child: child,
      ),
    ),
  );
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
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (errorMessage != null) _ErrorText(message: errorMessage!),
        TextFormField(
          controller: email,
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.mail_outline, size: 20),
          ),
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
    final media = MediaQuery.of(context);
    if (media.disableAnimations || media.accessibleNavigation) return form;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: form,
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
                      child: Row(
                        children: [
                          Expanded(child: Divider()),
                          Flexible(
                            flex: 4,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'or use email',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                    ),
                  ],
                ),
        );
  }
}
