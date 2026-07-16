// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'to_buy_dao.dart';

// ignore_for_file: type=lint
mixin _$ToBuyDaoMixin on DatabaseAccessor<AppDatabase> {
  $ToBuyItemsTableTable get toBuyItemsTable => attachedDatabase.toBuyItemsTable;
  ToBuyDaoManager get managers => ToBuyDaoManager(this);
}

class ToBuyDaoManager {
  final _$ToBuyDaoMixin _db;
  ToBuyDaoManager(this._db);
  $$ToBuyItemsTableTableTableManager get toBuyItemsTable =>
      $$ToBuyItemsTableTableTableManager(
        _db.attachedDatabase,
        _db.toBuyItemsTable,
      );
}
