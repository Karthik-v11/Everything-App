// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_dao.dart';

// ignore_for_file: type=lint
mixin _$VaultDaoMixin on DatabaseAccessor<AppDatabase> {
  $VaultItemsTableTable get vaultItemsTable => attachedDatabase.vaultItemsTable;
  $FoldersTableTable get foldersTable => attachedDatabase.foldersTable;
  VaultDaoManager get managers => VaultDaoManager(this);
}

class VaultDaoManager {
  final _$VaultDaoMixin _db;
  VaultDaoManager(this._db);
  $$VaultItemsTableTableTableManager get vaultItemsTable =>
      $$VaultItemsTableTableTableManager(
        _db.attachedDatabase,
        _db.vaultItemsTable,
      );
  $$FoldersTableTableTableManager get foldersTable =>
      $$FoldersTableTableTableManager(_db.attachedDatabase, _db.foldersTable);
}
