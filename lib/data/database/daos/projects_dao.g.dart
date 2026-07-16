// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'projects_dao.dart';

// ignore_for_file: type=lint
mixin _$ProjectsDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProjectsTableTable get projectsTable => attachedDatabase.projectsTable;
  $TasksTableTable get tasksTable => attachedDatabase.tasksTable;
  $DocumentsTableTable get documentsTable => attachedDatabase.documentsTable;
  $AttachmentsTableTable get attachmentsTable =>
      attachedDatabase.attachmentsTable;
  ProjectsDaoManager get managers => ProjectsDaoManager(this);
}

class ProjectsDaoManager {
  final _$ProjectsDaoMixin _db;
  ProjectsDaoManager(this._db);
  $$ProjectsTableTableTableManager get projectsTable =>
      $$ProjectsTableTableTableManager(_db.attachedDatabase, _db.projectsTable);
  $$TasksTableTableTableManager get tasksTable =>
      $$TasksTableTableTableManager(_db.attachedDatabase, _db.tasksTable);
  $$DocumentsTableTableTableManager get documentsTable =>
      $$DocumentsTableTableTableManager(
        _db.attachedDatabase,
        _db.documentsTable,
      );
  $$AttachmentsTableTableTableManager get attachmentsTable =>
      $$AttachmentsTableTableTableManager(
        _db.attachedDatabase,
        _db.attachmentsTable,
      );
}
