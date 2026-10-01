import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:uptrack_mobile/util/date_format.dart';

void main() {
  tearDown(() => displayTimeZone = (DateTime t) => t.toLocal());

  group('formatTimestamp', () {
    test('formats an ISO UTC timestamp as readable text', () {
      displayTimeZone = (DateTime t) => t.toUtc();
      expect(formatTimestamp('2026-09-26T00:00:00Z'), 'Sep 26, 2026, 00:00');
      expect(formatTimestamp('2026-01-05T14:07:59Z'), 'Jan 5, 2026, 14:07');
    });

    test('applies a UTC offset in the input', () {
      displayTimeZone = (DateTime t) => t.toUtc();
      expect(
        formatTimestamp('2026-09-26T09:30:00+07:00'),
        'Sep 26, 2026, 02:30',
      );
    });

    test('shows device-local time by default', () {
      const String iso = '2026-09-26T00:00:00Z';
      final String expected = DateFormat('MMM d, y, HH:mm')
          .format(DateTime.parse(iso).toLocal());
      expect(formatTimestamp(iso), expected);
    });

    test('never shows the raw ISO string', () {
      expect(formatTimestamp('2026-09-26T00:00:00Z'), isNot(contains('T')));
      expect(formatTimestamp('2026-09-26T00:00:00Z'), isNot(contains('Z')));
    });

    test('handles null, empty and unparsable input', () {
      expect(formatTimestamp(null), '');
      expect(formatTimestamp('  '), '');
      expect(formatTimestamp('yesterday'), 'yesterday');
    });
  });
}
