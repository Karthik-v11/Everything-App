// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attachments_dao.dart';

// ignore_for_file: type=lint
mixin _$AttachmentsDaoMixin on DatabaseAccessor<AppDatabase> {
  $AttachmentsTableTable get attachmentsTable =>
      attachedDatabase.attachmentsTable;
  AttachmentsDaoManager get managers => AttachmentsDaoManager(this);
}

class AttachmentsDaoManager {
  final _$AttachmentsDaoMixin _db;
  AttachmentsDaoManager(this._db);
  $$AttachmentsTableTableTableManager get attachmentsTable =>
      $$AttachmentsTableTableTableManager(
        _db.attachedDatabase,
        _db.attachmentsTable,
      );
}
