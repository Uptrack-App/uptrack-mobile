import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/incident.dart';
import '../../api/models/monitor.dart';
import '../../api/uptrack_api.dart';
import '../../data/local/app_database.dart';
import '../../data/local/cache_repository.dart';
import '../../data/local/database_providers.dart';
import '../auth/auth_controller.dart';

/// Resolved incidents kept for the dashboard history section.
///
/// The response queue is never truncated — the cap only applies to history,
/// which is a "what happened recently" list rather than a to-do list.
const int maxResolvedHistory = 5;

/// The three incident sections the dashboard shows, derived from one full
/// `GET /api/incidents` response.
class DashboardIncidents {
  const DashboardIncidents({
    required this.needsAcknowledgement,
    required this.acknowledgedOngoing,
    required this.recentResolved,
  });

  /// The truthy empty set, so a construction site that has no incidents does
  /// not have to spell out three empty lists (and cannot invent rows).
  static const DashboardIncidents empty = DashboardIncidents(
    needsAcknowledgement: <Incident>[],
    acknowledgedOngoing: <Incident>[],
    recentResolved: <Incident>[],
  );

  /// Ongoing and not yet acknowledged, oldest outstanding first.
  ///
  /// This is the response queue: nobody has looked at these yet, so they come
  /// first and they are shown in full rather than truncated to the newest few.
  final List<Incident> needsAcknowledgement;

  /// Ongoing and acknowledged — the acknowledgement is on record, so these sit
  /// below the queue, oldest first.
  ///
  /// Deliberately described no further than that: an acknowledgement is a
  /// timestamp the server recorded, not evidence that anybody was assigned the
  /// incident.
  final List<Incident> acknowledgedOngoing;

  /// Recently resolved history, newest first, bounded by [maxResolvedHistory].
  final List<Incident> recentResolved;

  /// How many incidents are waiting on a person.
  int get outstandingCount => needsAcknowledgement.length;
}

/// Dashboard content: monitor counts by status, an uptime summary, and the
/// incident response queue.
class DashboardData {
  const DashboardData({
    required this.totalMonitors,
    required this.loadedMonitors,
    required this.totalMonitorsKnown,
    required this.countsByStatus,
    required this.averageUptime,
    required this.offline,
    this.incidents = DashboardIncidents.empty,
  });

  /// Monitors the account has, as reported by the server.
  ///
  /// Only meaningful when [totalMonitorsKnown]; from the offline cache the
  /// server's total is unknown, and a cached row count must never be presented
  /// as one (see [loadedMonitors]).
  final int totalMonitors;

  /// Monitors in this response (or in the offline cache). The status counts and
  /// the uptime average are computed from exactly these rows.
  final int loadedMonitors;

  /// Whether [totalMonitors] is a server-reported total rather than the size of
  /// the loaded page.
  final bool totalMonitorsKnown;

  final Map<String, int> countsByStatus;
  final double? averageUptime;

  /// The response queue and recent history, already partitioned.
  final DashboardIncidents incidents;

  /// True when served from the offline cache because the API was
  /// unreachable (cache fallback).
  final bool offline;

  int get upCount => countsByStatus['up'] ?? 0;
  int get downCount => countsByStatus['down'] ?? 0;

  /// Statuses that are neither up nor down, counted over the loaded rows.
  int get otherCount => loadedMonitors - upCount - downCount;

  /// Whether the server reports monitors this response does not carry.
  bool get hasMoreMonitors =>
      totalMonitorsKnown && loadedMonitors < totalMonitors;

  /// Truthful description of what the monitor metrics cover.
  ///
  /// A bounded page says so ("Showing 100 of 137 monitors") instead of letting
  /// the counts read as the whole account, and the offline cache says the total
  /// is unknown rather than passing its row count off as one.
  String get monitorScopeSummary {
    if (!totalMonitorsKnown) {
      return 'Showing $loadedMonitors cached monitors. '
          'The account total is unknown while offline.';
    }
    if (hasMoreMonitors) {
      return 'Showing $loadedMonitors of $totalMonitors monitors. '
          'Status counts and uptime cover the $loadedMonitors shown.';
    }
    return 'Showing all $totalMonitors monitors.';
  }

  /// Whether this response carries nothing at all: no monitor rows and no
  /// incident rows in any section.
  ///
  /// Incident rows count here because they are content in their own right — a
  /// dashboard with incidents but no monitors is not an empty dashboard.
  bool get isEmpty =>
      loadedMonitors == 0 &&
      incidents.needsAcknowledgement.isEmpty &&
      incidents.acknowledgedOngoing.isEmpty &&
      incidents.recentResolved.isEmpty;

  /// What an empty dashboard is allowed to claim, or null when it is not empty.
  ///
  /// An empty *screen* is not the same fact as an empty *account*, and the
  /// difference decides the copy:
  ///
  /// * server says 0 monitors and there are no incidents — the account really
  ///   is empty, so the onboarding line is true;
  /// * server says the account has monitors but this response carried none —
  ///   the data is missing, so the screen must not report a zero it did not
  ///   observe; it offers a refresh instead;
  /// * offline with an empty cache — nothing is known, so the screen says so
  ///   and keeps the offline indicator rather than claiming an empty account.
  DashboardEmptyCopy? get emptyCopy {
    if (!isEmpty) {
      return null;
    }
    if (totalMonitorsKnown) {
      if (totalMonitors == 0) {
        return const DashboardEmptyCopy(
          headline: 'No monitors yet.',
          detail: 'Add a monitor on the web dashboard to get started.',
        );
      }
      // The account has monitors and this page is blank: report the gap, not a
      // zero.
      return DashboardEmptyCopy(
        headline: 'Monitor data unavailable',
        detail:
            'This account has $totalMonitors monitors, but this response '
            'carried none. Refresh to try again.',
        showRefresh: true,
      );
    }
    // The account total is unknown, so nothing here may be presented as the
    // state of the whole organisation.
    if (offline) {
      return const DashboardEmptyCopy(
        headline: 'No cached monitor data',
        detail:
            'You are offline and nothing is saved for this account yet, so its '
            'monitor total is unknown. Reconnect and refresh to load your '
            'monitors.',
        showRefresh: true,
      );
    }
    return const DashboardEmptyCopy(
      headline: 'Monitor data unavailable',
      detail:
          'Nothing is loaded for this account yet, and its monitor total is '
          'unknown. Refresh to try again.',
      showRefresh: true,
    );
  }
}

/// Copy for a dashboard that has nothing to show.
///
/// Kept next to the data rather than in the widget so the truthfulness rules
/// can be asserted without rendering, and so every empty branch names the same
/// two things: what is known, and what to do about it.
class DashboardEmptyCopy {
  const DashboardEmptyCopy({
    required this.headline,
    required this.detail,
    this.showRefresh = false,
  });

  /// What is actually known about this account.
  final String headline;

  /// Why the screen is empty, and what would change it.
  final String detail;

  /// Whether retrying is the useful next step (missing data is; an account
  /// with no monitors yet is not).
  final bool showRefresh;
}

/// Counts rows by their exact status string.
Map<String, int> countByStatus(Iterable<String> statuses) {
  final Map<String, int> counts = <String, int>{};
  for (final String status in statuses) {
    counts[status] = (counts[status] ?? 0) + 1;
  }
  return counts;
}

/// Mean of the non-null uptime values, or `null` when there are none.
double? averageUptime(Iterable<double?> values) {
  double sum = 0;
  int count = 0;
  for (final double? value in values) {
    if (value == null) {
      continue;
    }
    sum += value;
    count++;
  }
  if (count == 0) {
    return null;
  }
  return sum / count;
}

/// Maps API incidents to cache snapshots for the offline store.
IncidentSnapshot incidentToSnapshot(Incident incident) => IncidentSnapshot(
  id: incident.id,
  monitorId: incident.monitorId,
  monitorName: incident.monitorName,
  status: incident.status,
  startedAt: incident.startedAt,
  resolvedAt: incident.resolvedAt,
  acknowledgedAt: incident.acknowledgedAt,
  insertedAt: incident.insertedAt,
);

/// Parses an API timestamp, treating missing and unparseable values alike.
DateTime? _parseInstant(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

/// The instant a row's ordering is anchored to: the parsed `started_at`, or the
/// parsed `inserted_at` when the start is missing, blank or unparseable.
///
/// Derived *per row* rather than compared field by field. Comparing `started_at`
/// across rows first treated a row with no start as though it had no date at
/// all, so an incident inserted ten days ago lost to one that started an hour
/// ago; with the fallback resolved first, the row competes on the real age it
/// does have. Only a row with no usable date at all is undated.
DateTime? incidentEffectiveStart(Incident incident) =>
    _parseInstant(incident.startedAt) ?? _parseInstant(incident.insertedAt);

/// Orders two rows by their [incidentEffectiveStart], with a wholly undated row
/// sorting **last in both directions**.
///
/// The undated-last rule is applied before the direction is applied rather than
/// by negating an oldest-first comparator: negating would also flip the undated
/// case and put unknown dates at the top of the newest-first history, which
/// reads as "most recently resolved" for a row nobody can date.
int _compareByEffectiveStart(
  Incident a,
  Incident b, {
  required bool newestFirst,
}) {
  final DateTime? left = incidentEffectiveStart(a);
  final DateTime? right = incidentEffectiveStart(b);
  if (left == null && right == null) {
    // Equal so the caller's stable tiebreak (the incident id) decides.
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return newestFirst ? right.compareTo(left) : left.compareTo(right);
}

/// Oldest outstanding first: effective start, then the stable incident id.
///
/// Public because the feed's "needs acknowledgement" filter uses the same
/// order, so a row looks the same on the dashboard and in the feed. Ties fall
/// to the id, which is stable across runs and independent of the order the API
/// returned the rows in.
int compareOutstanding(Incident a, Incident b) {
  final int byStart = _compareByEffectiveStart(a, b, newestFirst: false);
  if (byStart != 0) {
    return byStart;
  }
  return a.id.compareTo(b.id);
}

/// Newest first by effective start, then the stable incident id.
///
/// Still anchored to when the incident started rather than when it resolved:
/// resolution is not what the user is reading this list for, and `resolved_at`
/// is null for anything still open.
int compareNewestFirst(Incident a, Incident b) {
  final int byStart = _compareByEffectiveStart(a, b, newestFirst: true);
  if (byStart != 0) {
    return byStart;
  }
  return a.id.compareTo(b.id);
}

/// Splits the incidents of one response into the dashboard sections.
///
/// Runs on the *whole* list, before anything is truncated. Taking the newest N
/// first and calling it "recent incidents" is what hid older ongoing incidents
/// that were still waiting for a person: a burst of quick resolutions pushed
/// them off the screen while they stayed open.
DashboardIncidents partitionIncidents(
  List<Incident> incidents, {
  int resolvedHistoryLimit = maxResolvedHistory,
}) {
  assert(resolvedHistoryLimit >= 0, 'history limit cannot be negative');
  final List<Incident> outstanding =
      incidents.where((Incident i) => i.isOngoing && !i.isAcknowledged).toList()
        ..sort(compareOutstanding);
  final List<Incident> acknowledged =
      incidents.where((Incident i) => i.isOngoing && i.isAcknowledged).toList()
        ..sort(compareOutstanding);
  final List<Incident> resolved =
      incidents.where((Incident i) => !i.isOngoing).toList()
        ..sort(compareNewestFirst);
  return DashboardIncidents(
    needsAcknowledgement: List<Incident>.unmodifiable(outstanding),
    acknowledgedOngoing: List<Incident>.unmodifiable(acknowledged),
    recentResolved: List<Incident>.unmodifiable(
      resolved.length <= resolvedHistoryLimit
          ? resolved
          : resolved.sublist(0, resolvedHistoryLimit),
    ),
  );
}

/// Maps a cached incident row back to the API shape.
Incident incidentFromCached(CachedIncident row) => Incident(
  id: row.id,
  monitorId: row.monitorId,
  status: row.status,
  insertedAt: row.insertedAt,
  monitorName: row.monitorName,
  startedAt: row.startedAt,
  resolvedAt: row.resolvedAt,
  acknowledgedAt: row.acknowledgedAt,
);

/// Throws when the session that captured [session] is no longer the cache's
/// session, meaning whatever was read belongs to a session that has ended.
///
/// Called again *after* every awaited cache read, not only before it: a check
/// made before the read cannot observe a logout that lands while the read is in
/// flight (TOCTOU), and the rows it returns would then reach the screen after
/// the session they belong to was wiped.
void _rejectEndedSession(CacheRepository cache, int session) {
  if (session != cache.sessionEpoch) {
    throw const SessionEndedException();
  }
}

/// Source of [DashboardData] (faked in widget tests).
abstract class DashboardRepository {
  Future<DashboardData> load();
}

/// Loads monitors + incidents from the API, persists them to the offline
/// cache, and falls back to the cache when the API is unreachable.
/// Rethrows the API error when the cache is empty too.
class ApiDashboardRepository implements DashboardRepository {
  ApiDashboardRepository({required this.api, required this.cache});

  final UptrackApi api;
  final CacheRepository cache;

  /// Resolved incidents kept for the dashboard history section.
  static const int maxRecentIncidents = maxResolvedHistory;

  /// Monitors requested per page.
  ///
  /// The list endpoint is paginated, so this bounds the response rather than
  /// fetching everything: [DashboardData.totalMonitors] keeps the server's real
  /// total and the screen says how much of it is on screen.
  static const int monitorPageSize = 100;

  /// All incident rows the cache holds, used when a list write is fenced or
  /// when the API is unreachable.
  ///
  /// Nothing is truncated here: the sections are derived from whatever rows
  /// exist, so a cache fallback cannot silently drop an outstanding incident.
  ///
  /// [session] is rechecked after the read so a logout that lands while the
  /// cache is being read rejects the load instead of returning old rows.
  Future<List<Incident>> _cachedIncidents(int session) async {
    final CachedList<CachedIncident> cached = await cache.getIncidents();
    _rejectEndedSession(cache, session);
    return cached.data.map(incidentFromCached).toList();
  }

  @override
  Future<DashboardData> load() async {
    // Captured before the request so an acknowledge landing mid-flight keeps
    // priority in the offline cache (see CacheRepository.saveIncidentsIfCurrent).
    final int revision = cache.incidentRevision;
    final int session = cache.sessionEpoch;
    try {
      final MonitorListResponse monitors = await api.listMonitors(
        perPage: monitorPageSize,
      );
      // One unfiltered list response. There is no second "ongoing only" fetch:
      // the endpoint has no limit and returns the whole history, so a second
      // request would only risk disagreeing with this one.
      final IncidentListResponse incidents = await api.listIncidents();
      // Both writes take the captured session epoch and run behind the same
      // ordered cache boundary, so a logout between the requests and these
      // writes cannot repopulate monitors or incidents on disk.
      final bool monitorsStored = await cache.saveMonitors(
        monitors.data,
        session: session,
      );
      final bool applied = await cache.saveIncidentsIfCurrent(
        // The full response is cached, not a truncated section: the cache is
        // the offline history, and saving only what the dashboard happens to
        // show would wipe everything else from it.
        incidents.data.map(incidentToSnapshot).toList(),
        revision,
        session: session,
      );
      if (!monitorsStored || session != cache.sessionEpoch) {
        // The session ended while this load was in flight; report it as a
        // load failure rather than showing the previous session's rows.
        throw const SessionEndedException();
      }
      // A fenced incident write means a newer mutation already owns those
      // rows; serving this older response would contradict it.
      final List<Incident> all = applied
          ? incidents.data
          : await _cachedIncidents(session);
      return DashboardData(
        totalMonitors: monitors.meta.total,
        loadedMonitors: monitors.data.length,
        totalMonitorsKnown: true,
        countsByStatus: countByStatus(
          monitors.data.map((Monitor m) => m.status),
        ),
        averageUptime: averageUptime(
          monitors.data.map((Monitor m) => m.uptimePercentage),
        ),
        // Derived from the full list, never from a truncated one.
        incidents: partitionIncidents(all),
        offline: false,
      );
    } on DioException {
      final CachedList<CachedMonitor> monitors = await cache.getMonitors();
      final CachedList<CachedIncident> incidents = await cache.getIncidents();
      // Rechecked after both reads, not only before them: a logout landing
      // while they were in flight must not surface the previous session's
      // monitors or incident rows.
      _rejectEndedSession(cache, session);
      if (monitors.data.isEmpty && incidents.data.isEmpty) {
        rethrow;
      }
      final int cachedMonitors = monitors.data.length;
      return DashboardData(
        // The cache holds at most one page of monitors and no server total, so
        // the row count is reported as the loaded count and the total is marked
        // unknown: a stale page must not read as the whole account.
        totalMonitors: cachedMonitors,
        loadedMonitors: cachedMonitors,
        totalMonitorsKnown: false,
        countsByStatus: countByStatus(
          monitors.data.map((CachedMonitor m) => m.status),
        ),
        averageUptime: averageUptime(
          monitors.data.map((CachedMonitor m) => m.uptimePercentage),
        ),
        incidents: partitionIncidents(
          incidents.data.map(incidentFromCached).toList(),
        ),
        offline: true,
      );
    }
  }
}

final Provider<DashboardRepository> dashboardRepositoryProvider =
    Provider<DashboardRepository>(
      (Ref ref) => ApiDashboardRepository(
        api: ref.watch(uptrackApiProvider),
        cache: ref.watch(cacheRepositoryProvider),
      ),
    );

final FutureProvider<DashboardData> dashboardProvider =
    FutureProvider<DashboardData>(
      (Ref ref) => ref.watch(dashboardRepositoryProvider).load(),
      // No automatic retry: a failed load falls back to the offline cache
      // inside the repository, and any remaining error is retried
      // explicitly via the Retry button / pull-to-refresh.
      retry: (int retryCount, Object error) => null,
    );

/// User-facing message for a dashboard load failure (prefers the
/// server's `error` field when present).
String dashboardErrorMessage(Object err) {
  if (err is DioException) {
    final Object? data = err.response?.data;
    if (data is Map<String, Object?>) {
      final Object? serverError = data['error'];
      if (serverError is String && serverError.isNotEmpty) {
        return serverError;
      }
    }
    if (err.response?.statusCode == 401) {
      return 'Session expired. Sign in again.';
    }
  }
  return 'Could not load the dashboard. Check your connection and try again.';
}
