import 'package:drift/drift.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/database/tables/tables.dart';
import 'package:everything_app/data/database/watch_extensions.dart';

part 'to_buy_dao.g.dart';

/// [ToBuyDao] is every SQL statement the To Buy list issues (Requirement 7).
///
/// [watchAll] streams the whole list, purchased items included: the screen groups
/// rather than hides them, and the reminder plan needs to see a purchased item to
/// know its alarm should be withdrawn. Filtering here would leave the planner
/// unable to tell a purchased item from a deleted one.
@DriftAccessor(tables: [ToBuyItemsTable])
class ToBuyDao extends DatabaseAccessor<AppDatabase> with _$ToBuyDaoMixin {
  ToBuyDao(super.db);

  Stream<List<ToBuyItemEntry>> watchAll() => (select(toBuyItemsTable)
        ..orderBy([
          (i) => OrderingTerm(expression: i.createdAt, mode: OrderingMode.desc),
        ]))
      .watch()
      .distinctList();

  Future<ToBuyItemEntry?> findById(String id) =>
      (select(toBuyItemsTable)..where((i) => i.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsert(ToBuyItemsTableCompanion item) =>
      into(toBuyItemsTable).insertOnConflictUpdate(item);

  Future<int> deleteById(String id) =>
      (delete(toBuyItemsTable)..where((i) => i.id.equals(id))).go();
}
