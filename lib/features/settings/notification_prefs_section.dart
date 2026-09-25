import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/notification_preferences.dart';
import '../auth/auth_controller.dart';

/// Editable copy of the notification prefs (plain state — `copyWith`
/// keeps the settings form immutable between saves).
class EditablePrefs {
  const EditablePrefs({
    this.overrides = const <String, String?>{},
    this.quietStart = '',
    this.quietEnd = '',
    this.mobilePushEnabled = true,
    this.digestP3 = true,
  });

  factory EditablePrefs.fromPrefs(NotificationPreferences prefs) {
    return EditablePrefs(
      overrides: <String, String?>{
        for (final String severity in kSeverities)
          severity: prefs.severityOverrides[severity],
      },
      quietStart: _displayTime(prefs.quietHoursStart),
      quietEnd: _displayTime(prefs.quietHoursEnd),
      mobilePushEnabled: prefs.mobilePushEnabled,
      digestP3: prefs.digestP3,
    );
  }

  final Map<String, String?> overrides;
  final String quietStart;
  final String quietEnd;
  final bool mobilePushEnabled;
  final bool digestP3;

  EditablePrefs copyWith({
    Map<String, String?>? overrides,
    String? quietStart,
    String? quietEnd,
    bool? mobilePushEnabled,
    bool? digestP3,
  }) {
    return EditablePrefs(
      overrides: overrides ?? this.overrides,
      quietStart: quietStart ?? this.quietStart,
      quietEnd: quietEnd ?? this.quietEnd,
      mobilePushEnabled: mobilePushEnabled ?? this.mobilePushEnabled,
      digestP3: digestP3 ?? this.digestP3,
    );
  }

  /// Merge into a PATCH body (see [NotificationPreferences.toPatchJson]).
  Map<String, Object?> toPatchJson() {
    final Map<String, String> kept = <String, String>{};
    for (final MapEntry<String, String?> entry in overrides.entries) {
      final String? value = entry.value;
      if (value != null && value.isNotEmpty) {
        kept[entry.key] = value;
      }
    }
    String? normalized(String raw) {
      final String trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return <String, Object?>{
      'severity_overrides': kept,
      'quiet_hours_start': normalized(quietStart),
      'quiet_hours_end': normalized(quietEnd),
      'mobile_push_enabled': mobilePushEnabled,
      'digest_p3': digestP3,
    };
  }

  /// Server times arrive as `HH:MM:SS`; the form edits `HH:MM`.
  static String _displayTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return '';
    }
    final String trimmed = raw.trim();
    final List<String> parts = trimmed.split(':');
    if (parts.length >= 2) {
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    }
    return trimmed;
  }
}

class NotificationPrefsState {
  const NotificationPrefsState({
    this.isLoading = true,
    this.form,
    this.errorMessage,
    this.isSaving = false,
    this.savedMessage,
  });

  final bool isLoading;
  final EditablePrefs? form;
  final String? errorMessage;
  final bool isSaving;
  final String? savedMessage;

  NotificationPrefsState copyWith({
    bool? isLoading,
    EditablePrefs? form,
    String? errorMessage,
    bool? isSaving,
    String? savedMessage,
  }) {
    return NotificationPrefsState(
      isLoading: isLoading ?? this.isLoading,
      form: form ?? this.form,
      errorMessage: errorMessage,
      isSaving: isSaving ?? this.isSaving,
      savedMessage: savedMessage,
    );
  }
}

final NotifierProvider<NotificationPrefsController, NotificationPrefsState>
notificationPrefsControllerProvider =
    NotifierProvider<NotificationPrefsController, NotificationPrefsState>(
      NotificationPrefsController.new,
    );

/// Loads `GET /api/users/me/notification-preferences` into an editable form
/// and saves via PATCH.
class NotificationPrefsController extends Notifier<NotificationPrefsState> {
  @override
  NotificationPrefsState build() {
    unawaited(Future(() => load()));
    return const NotificationPrefsState();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final NotificationPreferences prefs = await ref
          .read(uptrackApiProvider)
          .getNotificationPreferences();
      state = state.copyWith(
        isLoading: false,
        form: EditablePrefs.fromPrefs(prefs),
      );
    } on DioException {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not load notification preferences. Check your connection and try again.',
      );
    }
  }

  void updateForm(EditablePrefs form) {
    state = state.copyWith(form: form, savedMessage: null);
  }

  /// Validates quiet-hours locally, then PATCHes; returns false (and keeps
  /// the form) on validation or server failure.
  Future<bool> save() async {
    final EditablePrefs? form = state.form;
    if (form == null || state.isSaving) {
      return false;
    }
    if (form.quietStart.trim().isNotEmpty &&
        !isValidQuietTime(form.quietStart)) {
      state = state.copyWith(
        errorMessage: 'Quiet-hours start must be HH:MM (24-hour).',
      );
      return false;
    }
    if (form.quietEnd.trim().isNotEmpty && !isValidQuietTime(form.quietEnd)) {
      state = state.copyWith(
        errorMessage: 'Quiet-hours end must be HH:MM (24-hour).',
      );
      return false;
    }
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final NotificationPreferences updated = await ref
          .read(uptrackApiProvider)
          .updateNotificationPreferences(form.toPatchJson());
      state = state.copyWith(
        isSaving: false,
        form: EditablePrefs.fromPrefs(updated),
        savedMessage: 'Preferences saved.',
      );
      return true;
    } on DioException catch (err) {
      state = state.copyWith(isSaving: false, errorMessage: _messageFor(err));
      return false;
    }
  }

  String _messageFor(DioException err) {
    final Object? data = err.response?.data;
    if (data is Map<String, Object?>) {
      final Object? serverError = data['error'];
      if (serverError is String && serverError.isNotEmpty) {
        return serverError;
      }
    }
    if (err.response?.statusCode == 422) {
      return 'Check the highlighted fields and try again.';
    }
    return 'Could not save. Check your connection and try again.';
  }
}

/// Settings notification-preferences section: mobile-push master switch,
/// severity→interruption overrides, quiet hours, P3 digest.
class NotificationPrefsSection extends ConsumerStatefulWidget {
  const NotificationPrefsSection({super.key});

  @override
  ConsumerState<NotificationPrefsSection> createState() =>
      _NotificationPrefsSectionState();
}

class _NotificationPrefsSectionState
    extends ConsumerState<NotificationPrefsSection> {
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  bool _controllersSynced = false;

  @override
  void initState() {
    super.initState();
    _startController = TextEditingController();
    _endController = TextEditingController();
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _syncControllers(EditablePrefs form) {
    if (_controllersSynced) {
      return;
    }
    _controllersSynced = true;
    _startController.text = form.quietStart;
    _endController.text = form.quietEnd;
  }

  @override
  Widget build(BuildContext context) {
    final NotificationPrefsState state = ref.watch(
      notificationPrefsControllerProvider,
    );
    final NotificationPrefsController controller = ref.read(
      notificationPrefsControllerProvider.notifier,
    );
    final ThemeData theme = Theme.of(context);
    final EditablePrefs? form = state.form;
    if (form != null) {
      _syncControllers(form);
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Notifications', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          if (state.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              ),
            )
          else if (form == null)
            _PrefsError(
              message: state.errorMessage ?? 'Could not load preferences.',
              onRetry: controller.load,
            )
          else ...<Widget>[
            SwitchListTile(
              key: const ValueKey<String>('prefs-mobile-push'),
              title: const Text('Mobile push'),
              subtitle: const Text('Master switch for push notifications.'),
              value: form.mobilePushEnabled,
              onChanged: state.isSaving
                  ? null
                  : (bool value) => controller.updateForm(
                      form.copyWith(mobilePushEnabled: value),
                    ),
            ),
            for (final String severity in kSeverities)
              _SeverityRow(
                severity: severity,
                value:
                    form.overrides[severity] ?? kDefaultInterruption[severity]!,
                isDefault: form.overrides[severity] == null,
                enabled: !state.isSaving,
                onChanged: (String? value) {
                  final Map<String, String?> next = Map<String, String?>.from(
                    form.overrides,
                  );
                  next[severity] = value;
                  controller.updateForm(form.copyWith(overrides: next));
                },
              ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _startController,
                    key: const ValueKey<String>('prefs-quiet-start'),
                    decoration: const InputDecoration(
                      labelText: 'Quiet from (HH:MM)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    enabled: !state.isSaving,
                    onChanged: (String value) =>
                        controller.updateForm(form.copyWith(quietStart: value)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _endController,
                    key: const ValueKey<String>('prefs-quiet-end'),
                    decoration: const InputDecoration(
                      labelText: 'Quiet until (HH:MM)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    enabled: !state.isSaving,
                    onChanged: (String value) =>
                        controller.updateForm(form.copyWith(quietEnd: value)),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              key: const ValueKey<String>('prefs-digest-p3'),
              title: const Text('P3 digest'),
              subtitle: const Text('Bundle low-severity alerts into a digest.'),
              value: form.digestP3,
              onChanged: state.isSaving
                  ? null
                  : (bool value) =>
                        controller.updateForm(form.copyWith(digestP3: value)),
            ),
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  state.errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (state.savedMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(state.savedMessage!),
              ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey<String>('prefs-save'),
              onPressed: state.isSaving ? null : controller.save,
              child: state.isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save preferences'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeverityRow extends StatelessWidget {
  const _SeverityRow({
    required this.severity,
    required this.value,
    required this.isDefault,
    required this.enabled,
    required this.onChanged,
  });

  final String severity;
  final String value;
  final bool isDefault;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text('$severity${isDefault ? ' (default)' : ''}'),
      trailing: DropdownButton<String>(
        key: ValueKey<String>('prefs-severity-$severity'),
        value: value,
        items: <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(
            value: kDefaultInterruption[severity],
            child: const Text('Default'),
          ),
          for (final String level in kInterruptionLevels)
            if (level != kDefaultInterruption[severity])
              DropdownMenuItem<String>(value: level, child: Text(level)),
        ],
        onChanged: enabled
            ? (String? selected) {
                if (selected == kDefaultInterruption[severity]) {
                  onChanged(null);
                } else {
                  onChanged(selected);
                }
              }
            : null,
      ),
    );
  }
}

class _PrefsError extends StatelessWidget {
  const _PrefsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: <Widget>[
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
