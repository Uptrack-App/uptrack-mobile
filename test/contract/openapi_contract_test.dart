import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/api/uptrack_api.dart';

/// Contract test: every endpoint used by `lib/api/` must exist in the
/// web backend's OpenAPI spec.
///
/// Skips (does not fail) when the spec file is absent, e.g. in CI where
/// only the mobile repo is checked out.
void main() {
  test('mobile endpoints exist in openapi-v2.json', () {
    const String specPath =
        '/Users/le/repos/uptrack-app/uptrack-web/openapi-v2.json';
    final File specFile = File(specPath);
    if (!specFile.existsSync()) {
      markTestSkipped('OpenAPI spec not found at $specPath');
      return;
    }

    final Map<String, Object?> spec =
        jsonDecode(specFile.readAsStringSync()) as Map<String, Object?>;
    final Object? pathsValue = spec['paths'];
    if (pathsValue is! Map<String, Object?>) {
      fail('OpenAPI spec at $specPath has no "paths" object');
    }
    final Map<String, Object?> paths = pathsValue;

    // Every path used by lib/api/ (+ the Live Activity token endpoint the
    // native iOS side registers through, asserted by template even though
    // no Dart call site references it yet).
    const Map<String, List<String>> usedEndpoints = <String, List<String>>{
      kGetMePath: <String>['get'],
      kListMonitorsPath: <String>['get'],
      kIncidentsPath: <String>['get'],
      kIncidentDetailPath: <String>['get'],
      kIncidentAcknowledgePath: <String>['post'],
      kIncidentEscalatePath: <String>['post'],
      kMonitorSnoozePath: <String>['post'],
      kMonitorDetailPath: <String>['get'],
      kMonitorChecksPath: <String>['get'],
      kMonitorAnalyticsPath: <String>['get'],
      kStatusPagePath: <String>['get'],
      kBillingSubscriptionPath: <String>['get'],
      kDeviceTokensPath: <String>['get', 'post'],
      '/api/auth/device-tokens/{id}': <String>['delete'],
      kPushDevicesPath: <String>['post', 'delete'],
      '/api/push/live-activities': <String>['post', 'delete'],
      kNotificationPreferencesPath: <String>['get', 'patch'],
    };

    for (final MapEntry<String, List<String>> entry in usedEndpoints.entries) {
      final Object? pathItem = paths[entry.key];
      expect(
        pathItem,
        isNotNull,
        reason: '${entry.key} used by lib/api/ missing from $specPath',
      );
      if (pathItem is Map<String, Object?>) {
        for (final String method in entry.value) {
          expect(
            pathItem.containsKey(method),
            isTrue,
            reason: '${entry.key} has no "$method" operation in $specPath',
          );
        }
      } else {
        fail('${entry.key} is not an object in $specPath');
      }
    }
  });

  test('status page declares the ?password= query param', () {
    const String specPath =
        '/Users/le/repos/uptrack-app/uptrack-web/openapi-v2.json';
    final File specFile = File(specPath);
    if (!specFile.existsSync()) {
      markTestSkipped('OpenAPI spec not found at $specPath');
      return;
    }

    final Map<String, Object?> spec =
        jsonDecode(specFile.readAsStringSync()) as Map<String, Object?>;
    final Map<String, Object?> paths = (spec['paths'] as Map)
        .cast<String, Object?>();
    final Map<String, Object?> statusItem = (paths[kStatusPagePath] as Map)
        .cast<String, Object?>();
    final Map<String, Object?> getOp = (statusItem['get'] as Map)
        .cast<String, Object?>();
    final List<Object?> parameters =
        (getOp['parameters'] as List?)?.cast<Object?>() ?? <Object?>[];
    final bool hasPassword = parameters.any((Object? p) {
      if (p is! Map) return false;
      final Map<String, Object?> param = p.cast<String, Object?>();
      return param['name'] == 'password' && param['in'] == 'query';
    });
    expect(
      hasPassword,
      isTrue,
      reason: '$kStatusPagePath GET declares no ?password= param in $specPath',
    );
  });
}
