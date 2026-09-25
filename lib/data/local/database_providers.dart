import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'cache_repository.dart';

/// Shared Drift database for the offline cache (see T022).
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>((
  Ref ref,
) {
  final AppDatabase db = AppDatabase();
  ref.onDispose(() {
    unawaited(db.close());
  });
  return db;
});

/// Read-through cache over [AppDatabase] with staleness timestamps.
final Provider<CacheRepository> cacheRepositoryProvider =
    Provider<CacheRepository>(
      (Ref ref) => CacheRepository(ref.watch(appDatabaseProvider)),
    );
