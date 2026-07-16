import 'package:drift/drift.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/database/tables/tables.dart';
import 'package:everything_app/data/database/watch_extensions.dart';

part 'documents_dao.g.dart';

/// [DocumentsDao] is every SQL statement the Document Writer issues
/// (Requirement 11).
///
/// [watchAll] streams every document at once. The project detail screen filters
/// this one stream by [DocumentEntry.projectId] rather than running a per-project
/// query, for the same reason the tasks list does: one stream means a document
/// saved anywhere refreshes every screen showing it, with no reload event.
@DriftAccessor(tables: [DocumentsTable])
class DocumentsDao extends DatabaseAccessor<AppDatabase>
    with _$DocumentsDaoMixin {
  DocumentsDao(super.db);

  Stream<List<DocumentEntry>> watchAll() => (select(documentsTable)
        ..orderBy([
          (d) => OrderingTerm(expression: d.updatedAt, mode: OrderingMode.desc),
        ]))
      .watch()
      .distinctList();

  Future<DocumentEntry?> findById(String id) =>
      (select(documentsTable)..where((d) => d.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsert(DocumentsTableCompanion document) =>
      into(documentsTable).insertOnConflictUpdate(document);

  Future<int> deleteById(String id) =>
      (delete(documentsTable)..where((d) => d.id.equals(id))).go();
}
