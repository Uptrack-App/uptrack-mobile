import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/device_token.dart';
import '../auth/auth_controller.dart';

/// State for the device-management list on the settings screen.
class DeviceTokensState {
  const DeviceTokensState({
    this.isLoading = true,
    this.devices = const <DeviceToken>[],
    this.errorMessage,
    this.revokingIds = const <String>{},
  });

  final bool isLoading;
  final List<DeviceToken> devices;
  final String? errorMessage;
  final Set<String> revokingIds;

  DeviceTokensState copyWith({
    bool? isLoading,
    List<DeviceToken>? devices,
    String? errorMessage,
    Set<String>? revokingIds,
  }) {
    return DeviceTokensState(
      isLoading: isLoading ?? this.isLoading,
      devices: devices ?? this.devices,
      errorMessage: errorMessage,
      revokingIds: revokingIds ?? this.revokingIds,
    );
  }
}

final NotifierProvider<DeviceTokensController, DeviceTokensState>
deviceTokensControllerProvider =
    NotifierProvider<DeviceTokensController, DeviceTokensState>(
      DeviceTokensController.new,
    );

/// Loads `GET /api/auth/device-tokens` and revokes per device.
class DeviceTokensController extends Notifier<DeviceTokensState> {
  @override
  DeviceTokensState build() {
    // Deferred: setting `state` synchronously inside build() throws
    // (uninitialized provider), so the initial fetch runs on the event
    // queue, after the provider is mounted.
    unawaited(Future(() => load()));
    return const DeviceTokensState();
  }

  /// Explicit reload (initial build also triggers one; tests await this).
  Future<void> load() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final List<DeviceToken> devices = await ref
          .read(uptrackApiProvider)
          .listDeviceTokens();
      state = state.copyWith(isLoading: false, devices: devices);
    } on DioException catch (err) {
      state = state.copyWith(isLoading: false, errorMessage: _messageFor(err));
    }
  }

  /// Revokes one device; returns false (and keeps the row) on failure.
  Future<bool> revoke(String id) async {
    if (state.revokingIds.contains(id)) {
      return false;
    }
    state = state.copyWith(revokingIds: <String>{...state.revokingIds, id});
    try {
      await ref.read(uptrackApiProvider).revokeDeviceToken(id);
      state = state.copyWith(
        devices: state.devices.where((DeviceToken d) => d.id != id).toList(),
        revokingIds: state.revokingIds.where((String e) => e != id).toSet(),
      );
      return true;
    } on DioException catch (err) {
      state = state.copyWith(
        revokingIds: state.revokingIds.where((String e) => e != id).toSet(),
        errorMessage: _messageFor(err),
      );
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
    if (err.response?.statusCode == 404) {
      return 'That device is already gone. Refresh the list.';
    }
    if (err.response?.statusCode == 401) {
      return 'Session expired. Sign in again.';
    }
    return 'Something went wrong. Check your connection and try again.';
  }
}
