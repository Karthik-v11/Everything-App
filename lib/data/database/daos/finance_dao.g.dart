// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finance_dao.dart';

// ignore_for_file: type=lint
mixin _$FinanceDaoMixin on DatabaseAccessor<AppDatabase> {
  $TransactionsTableTable get transactionsTable =>
      attachedDatabase.transactionsTable;
  $AccountsTableTable get accountsTable => attachedDatabase.accountsTable;
  $BudgetsTableTable get budgetsTable => attachedDatabase.budgetsTable;
  FinanceDaoManager get managers => FinanceDaoManager(this);
}

class FinanceDaoManager {
  final _$FinanceDaoMixin _db;
  FinanceDaoManager(this._db);
  $$TransactionsTableTableTableManager get transactionsTable =>
      $$TransactionsTableTableTableManager(
        _db.attachedDatabase,
        _db.transactionsTable,
      );
  $$AccountsTableTableTableManager get accountsTable =>
      $$AccountsTableTableTableManager(_db.attachedDatabase, _db.accountsTable);
  $$BudgetsTableTableTableManager get budgetsTable =>
      $$BudgetsTableTableTableManager(_db.attachedDatabase, _db.budgetsTable);
}
