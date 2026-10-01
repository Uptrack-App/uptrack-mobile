import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/theme/status_colors.dart';

void main() {
  group('statusLabel matches the web StatusBadge labels', () {
    const Map<String?, String> cases = <String?, String>{
      'up': 'Up',
      'operational': 'Up',
      'down': 'Down',
      'degraded': 'Degraded',
      'visual_regression': 'Degraded',
      'partial_outage': 'Degraded',
      'paused': 'Paused',
      'disabled': 'Paused',
      'unknown': 'Unknown',
      'pending': 'Pending',
      null: 'Pending',
      '': 'Pending',
      'UP': 'Up',
    };
    for (final MapEntry<String?, String> c in cases.entries) {
      test('${c.key} -> ${c.value}', () {
        expect(statusLabel(c.key), c.value);
      });
    }
  });

  test('other statuses are humanized and capitalized', () {
    expect(statusLabel('investigating'), 'Investigating');
    expect(statusLabel('resolved'), 'Resolved');
    expect(statusLabel('major_outage'), 'Major outage');
    expect(statusLabel('under-maintenance'), 'Under maintenance');
  });

  test('labels agree with the shared status looks', () {
    final UptrackStatusColors c = UptrackStatusColors.light;
    for (final String s in <String>['up', 'down', 'degraded', 'paused']) {
      expect(statusLabel(s), c.forStatus(s).label);
    }
  });
}
