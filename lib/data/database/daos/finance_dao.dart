import 'package:drift/drift.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/database/tables/tables.dart';
import 'package:everything_app/data/database/watch_extensions.dart';

part 'finance_dao.g.dart';

/// [FinanceDao] is every SQL statement the Finance module issues.
///
/// As in [TasksDao], the `watch*` methods return streams: drift re-runs the query
/// and pushes a new list whenever a row changes, so a transaction saved in the
/// form refreshes the dashboard, the charts, the account balances and the budget
/// bar with no reload event anywhere.
///
/// [watchTransactions] deliberately streams **every** transaction rather than one
/// month's. The dashboard needs a six-month trend, the summary needs the selected
/// month, and the search spans everything — three overlapping windows over the
/// same rows, which one query serves and three would keep in sync by hand. The
/// month is a filter applied in memory, so changing it is free.
@DriftAccessor(tables: [TransactionsTable, AccountsTable, BudgetsTable])
class FinanceDao extends DatabaseAccessor<AppDatabase> with _$FinanceDaoMixin {
  FinanceDao(super.db);

  // ── Transactions ───────────────────────────────────────────────────────────

  /// [watchTransactions] streams every transaction, newest first.
  Stream<List<TransactionEntry>> watchTransactions() =>
      (select(transactionsTable)
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
              (t) =>
                  OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
            ]))
          .watch()
          .distinctList();

  Future<List<TransactionEntry>> allTransactions() =>
      select(transactionsTable).get();

  Future<TransactionEntry?> findTransaction(String id) =>
      (select(transactionsTable)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsertTransaction(TransactionsTableCompanion transaction) =>
      into(transactionsTable).insertOnConflictUpdate(transaction);

  Future<int> deleteTransaction(String id) =>
      (delete(transactionsTable)..where((t) => t.id.equals(id))).go();

  // ── Accounts ───────────────────────────────────────────────────────────────

  Stream<List<AccountEntry>> watchAccounts() => (select(accountsTable)
        ..orderBy([(a) => OrderingTerm(expression: a.name)]))
      .watch()
      .distinctList();

  Future<List<AccountEntry>> allAccounts() => select(accountsTable).get();

  Future<void> upsertAccount(AccountsTableCompanion account) =>
      into(accountsTable).insertOnConflictUpdate(account);

  /// [countTransactionsForAccount] is what decides whether an account can be
  /// deleted outright or has to be archived — deleting one with history behind it
  /// would leave transactions pointing at an account that no longer exists.
  Future<int> countTransactionsForAccount(String accountId) async {
    final count = transactionsTable.id.count();

    final query = selectOnly(transactionsTable)
      ..addColumns([count])
      ..where(transactionsTable.accountId.equals(accountId));

    final row = await query.getSingle();

    return row.read(count) ?? 0;
  }

  Future<int> deleteAccount(String id) =>
      (delete(accountsTable)..where((a) => a.id.equals(id))).go();

  /// [seedAccountsIfEmpty] installs the default accounts on first launch.
  ///
  /// Guarded on an empty table, so an account the user deleted is not reinstated
  /// on the next launch.
  Future<void> seedAccountsIfEmpty(List<AccountsTableCompanion> defaults) async {
    final existing = await select(accountsTable).get();
    if (existing.isNotEmpty) return;

    await transaction(() async {
      for (final account in defaults) {
        await into(accountsTable).insert(account);
      }
    });
  }

  // ── Budgets ────────────────────────────────────────────────────────────────

  Stream<List<BudgetEntry>> watchBudgets() =>
      select(budgetsTable).watch().distinctList();

  Future<BudgetEntry?> findBudget({required int month, required int year}) =>
      (select(budgetsTable)
            ..where((b) => b.month.equals(month) & b.year.equals(year)))
          .getSingleOrNull();

  Future<void> upsertBudget(BudgetsTableCompanion budget) =>
      into(budgetsTable).insertOnConflictUpdate(budget);

  Future<int> deleteBudget(String id) =>
      (delete(budgetsTable)..where((b) => b.id.equals(id))).go();
}
