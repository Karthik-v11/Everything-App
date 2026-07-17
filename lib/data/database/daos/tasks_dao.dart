import 'package:drift/drift.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/database/tables/tables.dart';
import 'package:everything_app/data/database/watch_extensions.dart';

part 'tasks_dao.g.dart';

/// [TasksDao] is every SQL statement the Tasks module issues.
///
/// The `watch*` methods return streams: drift re-runs the query and pushes a new
/// list whenever any row in `tasks` changes, so any write in the app refreshes
/// every visible task list with no manual reload event.
@DriftAccessor(tables: [TasksTable, CategoriesTable])
class TasksDao extends DatabaseAccessor<AppDatabase> with _$TasksDaoMixin {
  TasksDao(super.db);

  // ── Reads ──────────────────────────────────────────────────────────────────

  /// [watchAll] streams every task, newest due date first.
  Stream<List<TaskEntry>> watchAll() => (select(tasksTable)
        ..orderBy([
          // Tasks with no due date sort last rather than first.
          (t) => OrderingTerm(expression: t.dueDate.isNull()),
          (t) => OrderingTerm(expression: t.dueDate),
          (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
        ]))
      .watch()
      .distinctList();

  /// [watchForDate] streams the tasks due on [date].
  ///
  /// Bounds are computed in Dart as a half-open range `[start, end)`. A SQL
  /// `date(due_date)` comparison would ignore the column index and evaluate in
  /// UTC, shifting which local day a task belongs to.
  Stream<List<TaskEntry>> watchForDate(DateTime date) {
    final start = date.dateOnly;
    final end = start.add(const Duration(days: 1));

    return (select(tasksTable)
          ..where(
            (t) =>
                t.dueDate.isBiggerOrEqualValue(start) &
                t.dueDate.isSmallerThanValue(end),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.dueDate)]))
        .watch()
      .distinctList();
  }

  Future<TaskEntry?> findById(String id) =>
      (select(tasksTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<TaskEntry>> allTasks() => select(tasksTable).get();

  // ── Writes ─────────────────────────────────────────────────────────────────

  Future<void> upsert(TasksTableCompanion task) =>
      into(tasksTable).insertOnConflictUpdate(task);

  /// [upsertAll] writes several tasks in one transaction.
  ///
  /// The recurrence rollover depends on the atomicity: completing a task and
  /// inserting its successor must both land or neither.
  Future<void> upsertAll(List<TasksTableCompanion> tasks) => transaction(() async {
        for (final task in tasks) {
          await into(tasksTable).insertOnConflictUpdate(task);
        }
      });

  Future<int> deleteById(String id) =>
      (delete(tasksTable)..where((t) => t.id.equals(id))).go();

  // ── Categories ─────────────────────────────────────────────────────────────

  Stream<List<CategoryEntry>> watchCategories() =>
      select(categoriesTable).watch().distinctList();

  Future<List<CategoryEntry>> allCategories() => select(categoriesTable).get();

  Future<void> upsertCategory(CategoriesTableCompanion category) =>
      into(categoriesTable).insertOnConflictUpdate(category);

  /// [seedCategoriesIfEmpty] installs the default categories on first launch.
  ///
  /// Guarded on an empty table, so a deleted default category is not reinstated
  /// on the next launch.
  Future<void> seedCategoriesIfEmpty(
    List<CategoriesTableCompanion> defaults,
  ) async {
    final existing = await select(categoriesTable).get();
    if (existing.isNotEmpty) return;

    await transaction(() async {
      for (final category in defaults) {
        await into(categoriesTable).insert(category);
      }
    });
  }
}
