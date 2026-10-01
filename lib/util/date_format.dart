import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Converts a parsed UTC instant to the zone shown to the user. The app shows
/// device-local time; goldens pin this to UTC so they do not depend on the
/// zone of the machine that runs them.
@visibleForTesting
DateTime Function(DateTime) displayTimeZone = _toLocal;

DateTime _toLocal(DateTime t) => t.toLocal();

final DateFormat _timestamp = DateFormat('MMM d, y, HH:mm');

/// Formats an ISO 8601 timestamp from the API (for example
/// `2026-09-26T00:00:00Z`) as human-readable local time, such as
/// "Sep 26, 2026, 02:00". Returns an empty string for null or empty input,
/// and the input unchanged if it does not parse.
String formatTimestamp(String? iso) {
  if (iso == null || iso.trim().isEmpty) return '';
  final DateTime? parsed = DateTime.tryParse(iso.trim());
  if (parsed == null) return iso;
  return _timestamp.format(displayTimeZone(parsed));
}
