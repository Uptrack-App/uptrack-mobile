import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/features/monitors/monitor_widgets.dart';
import 'package:uptrack_mobile/features/settings/notification_prefs_section.dart';
import 'package:uptrack_mobile/push/live_activity_support.dart';

void main() {
  test('displayUrl drops the scheme and a trailing slash', () {
    expect(displayUrl('https://api.example.com/'), 'api.example.com');
    expect(displayUrl('http://example.com/health'), 'example.com/health');
    expect(displayUrl('tcp://db.internal:5432'), 'db.internal:5432');
    expect(displayUrl('example.com'), 'example.com');
  });

  test('monitorTypeLabel', () {
    expect(monitorTypeLabel('http'), 'HTTP');
    expect(monitorTypeLabel('icmp'), 'Ping');
    expect(monitorTypeLabel('keyword'), 'Keyword');
    expect(monitorTypeLabel('heart_beat'), 'Heart beat');
  });

  test('regionsLabel', () {
    expect(regionsLabel(''), isNull);
    expect(regionsLabel('any'), 'any region');
    expect(regionsLabel('majority'), 'majority of regions');
    expect(regionsLabel('all'), 'all regions');
  });

  test('severity and interruption labels', () {
    expect(severityLabel('p1'), 'P1');
    expect(severityLabel('info'), 'Info');
    expect(interruptionLabel('passive'), 'Quiet');
    expect(interruptionLabel('active'), 'Normal');
    expect(interruptionLabel('time-sensitive'), 'Time-sensitive');
  });

  test('deviceLabel names the OS and its version', () {
    expect(
      deviceLabel(TargetPlatform.iOS, 'Version 27.0 (Build 24A123)'),
      'iOS 27.0',
    );
    expect(deviceLabel(TargetPlatform.android, '15'), 'Android 15');
    expect(deviceLabel(TargetPlatform.iOS, ''), 'iOS');
    expect(deviceLabel(TargetPlatform.macOS, '15.1'), isNull);
  });
}
