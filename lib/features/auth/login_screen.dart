import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';

enum _LoginMode { password, magicLink }

/// Sign-in screen: password (+2FA when prompted) or magic link.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _magicToken = TextEditingController();
  _LoginMode _mode = _LoginMode.password;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
        GoRouter.maybeOf(context)?.go('/');
      }
    });
    final AuthState auth = ref.watch(authControllerProvider);
    final AuthController controller = ref.read(authControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in to Uptrack')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: <Widget>[
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
                else if (_mode == _LoginMode.password)
                  _PasswordForm(
                    email: _email,
                    password: _password,
                    isLoading: auth.isLoading,
                    errorMessage: auth.errorMessage,
                    onSubmit: () {
                      if (_formKey.currentState!.validate()) {
                        controller.signInWithPassword(
                          email: _email.text,
                          password: _password.text,
                        );
                      }
                    },
                    onMagicLink: () => setState(() {
                      _mode = _LoginMode.magicLink;
                    }),
                  )
                else
                  _MagicLinkForm(
                    email: _email,
                    magicToken: _magicToken,
                    isLoading: auth.isLoading,
                    errorMessage: auth.errorMessage,
                    magicLinkSent: auth.magicLinkSent,
                    onRequest: () {
                      if (validateEmail(_email.text) == null) {
                        controller.requestMagicLink(_email.text);
                      } else {
                        _formKey.currentState!.validate();
                      }
                    },
                    onVerify: () {
                      if (_formKey.currentState!.validate()) {
                        controller.verifyMagicLink(
                          email: _email.text,
                          token: _magicToken.text.trim(),
                        );
                      }
                    },
                    onBack: () => setState(() {
                      _mode = _LoginMode.password;
                    }),
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

class _PasswordForm extends StatelessWidget {
  const _PasswordForm({
    required this.email,
    required this.password,
    required this.isLoading,
    required this.errorMessage,
    required this.onSubmit,
    required this.onMagicLink,
  });

  final TextEditingController email;
  final TextEditingController password;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onSubmit;
  final VoidCallback onMagicLink;

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
        TextFormField(
          controller: password,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
          autofillHints: const <String>[AutofillHints.password],
          validator: validatePassword,
          onFieldSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: isLoading ? null : onSubmit,
          child: isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Sign in'),
        ),
        TextButton(
          onPressed: isLoading ? null : onMagicLink,
          child: const Text('Email me a sign-in link instead'),
        ),
      ],
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
        FilledButton(
          onPressed: isLoading ? null : onSubmit,
          child: isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verify'),
        ),
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
    required this.onBack,
  });

  final TextEditingController email;
  final TextEditingController magicToken;
  final bool isLoading;
  final String? errorMessage;
  final bool magicLinkSent;
  final VoidCallback onRequest;
  final VoidCallback onVerify;
  final VoidCallback onBack;

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
        FilledButton.tonal(
          onPressed: isLoading ? null : onRequest,
          child: const Text('Email me a sign-in link'),
        ),
        if (magicLinkSent) ...<Widget>[
          const SizedBox(height: 8),
          const Text('Check your inbox, then paste the code below.'),
          const SizedBox(height: 12),
          TextFormField(
            controller: magicToken,
            decoration: const InputDecoration(labelText: 'Sign-in code'),
            validator: (String? value) =>
                (value == null || value.trim().isEmpty)
                ? 'Paste the code from your email'
                : null,
            onFieldSubmitted: (_) => onVerify(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: isLoading ? null : onVerify,
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Verify code'),
          ),
        ],
        TextButton(
          onPressed: isLoading ? null : onBack,
          child: const Text('Back to password sign-in'),
        ),
      ],
    );
  }
}
