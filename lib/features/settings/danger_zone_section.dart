import '../../design/uptrack_design.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';

/// Account deletion (R2.6): owner-only, password re-authentication for
/// accounts that have a password, subscription must already be cancelled
/// (the server answers 409 until then). From the app, the server accepts a
/// device token only within 15 minutes of a sign-in (D11); otherwise it
/// answers 403 `reauth_required` and the user signs in again here. On success the full local wipe runs through
/// [AuthController.signOut] (tokens, widget data, offline cache,
/// notifications) and the auth redirect sends the user to login.
class DangerZoneSection extends ConsumerStatefulWidget {
  const DangerZoneSection({super.key});

  @override
  ConsumerState<DangerZoneSection> createState() => _DangerZoneSectionState();
}

class _DangerZoneSectionState extends ConsumerState<DangerZoneSection> {
  final TextEditingController _password = TextEditingController();
  bool _confirmed = false;
  bool _busy = false;
  bool _reauthRequired = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
      _reauthRequired = false;
    });
    try {
      final String password = _password.text;
      await ref
          .read(uptrackApiProvider)
          .deleteAccount(password: password.isEmpty ? null : password);
      await ref.read(authControllerProvider.notifier).signOut();
    } on DioException catch (e) {
      setState(() {
        _reauthRequired = _isReauthRequired(e);
        _error = _messageFor(e);
        _busy = false;
      });
    }
  }

  static bool _isReauthRequired(DioException e) {
    final Object? data = e.response?.data;
    return e.response?.statusCode == 403 &&
        data is Map &&
        data['code'] == 'reauth_required';
  }

  /// Maps the `POST /api/auth/account` failures to actionable copy. Prefers
  /// the server's message when it carries one.
  static String _messageFor(DioException e) {
    final Object? data = e.response?.data;
    final Object? serverMessage = data is Map ? data['error'] : null;
    switch (e.response?.statusCode) {
      case 409:
        return serverMessage is String && serverMessage.isNotEmpty
            ? serverMessage
            : 'Cancel your subscription first (Settings → Billing), so you are not charged after deletion.';
      case 422:
        return 'That password is incorrect. Try again.';
      case 403:
        if (_isReauthRequired(e)) {
          return 'For your safety, sign in again. Then delete your account within 15 minutes.';
        }
        return 'Only the organization owner can delete the account.';
      case 401:
        return 'Your session expired. Sign in again, then retry deletion.';
      default:
        if (serverMessage is String && serverMessage.isNotEmpty) {
          return serverMessage;
        }
        return 'Could not delete the account. Try again later.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Danger zone', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Deleting your account soft-deletes you and your organization. '
            'Data is purged after 30 days. This cannot be undone.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey<String>('delete-password'),
            controller: _password,
            obscureText: true,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Password',
              helperText: 'Only if your account has a password. Otherwise leave it empty.',
              border: OutlineInputBorder(),
            ),
          ),
          CheckboxListTile(
            key: const ValueKey<String>('delete-confirm'),
            value: _confirmed,
            enabled: !_busy,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('I understand this is permanent.'),
            onChanged: (bool? v) => setState(() => _confirmed = v ?? false),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                key: const ValueKey<String>('delete-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (_reauthRequired)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: UptrackButton(
                key: const ValueKey<String>('delete-reauth'),
                label: 'Sign in again',
                kind: UptrackButtonKind.secondary,
                icon: Icons.login,
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).signOut(),
              ),
            ),
          UptrackButton(
            key: const ValueKey<String>('delete-account'),
            label: 'Delete my account',
            kind: UptrackButtonKind.destructive,
            icon: Icons.delete_forever_outlined,
            busy: _busy,
            onPressed: _confirmed ? _delete : null,
          ),
        ],
      ),
    );
  }
}
