import 'package:drift/drift.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/database/tables/tables.dart';
import 'package:everything_app/data/database/watch_extensions.dart';

part 'watchlist_dao.g.dart';

/// [WatchlistDao] is every SQL statement the Watchlist issues (Requirement 8).
@DriftAccessor(tables: [WatchlistTable])
class WatchlistDao extends DatabaseAccessor<AppDatabase>
    with _$WatchlistDaoMixin {
  WatchlistDao(super.db);

  Stream<List<WatchlistItemEntry>> watchAll() => (select(watchlistTable)
        ..orderBy([
          (w) => OrderingTerm(expression: w.createdAt, mode: OrderingMode.desc),
        ]))
      .watch()
      .distinctList();

  Future<WatchlistItemEntry?> findById(String id) =>
      (select(watchlistTable)..where((w) => w.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsert(WatchlistTableCompanion item) =>
      into(watchlistTable).insertOnConflictUpdate(item);

  Future<int> deleteById(String id) =>
      (delete(watchlistTable)..where((w) => w.id.equals(id))).go();
}
