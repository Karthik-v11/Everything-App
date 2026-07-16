// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'documents_dao.dart';

// ignore_for_file: type=lint
mixin _$DocumentsDaoMixin on DatabaseAccessor<AppDatabase> {
  $DocumentsTableTable get documentsTable => attachedDatabase.documentsTable;
  DocumentsDaoManager get managers => DocumentsDaoManager(this);
}

class DocumentsDaoManager {
  final _$DocumentsDaoMixin _db;
  DocumentsDaoManager(this._db);
  $$DocumentsTableTableTableManager get documentsTable =>
      $$DocumentsTableTableTableManager(
        _db.attachedDatabase,
        _db.documentsTable,
      );
}
