import 'package:drift/drift.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/database/tables/tables.dart';
import 'package:everything_app/data/database/watch_extensions.dart';
import 'package:everything_app/data/models/folder.dart';

part 'bookmarks_dao.g.dart';

/// [BookmarksDao] is every SQL statement the Bookmarks sub-feature issues
/// (Requirement 6).
///
/// It shares [FoldersTable] with the vault, so every folder statement here is
/// scoped to [FolderScope.bookmark] — an unscoped query would put the user's
/// vault folders in the bookmark folder picker.
@DriftAccessor(tables: [BookmarksTable, FoldersTable])
class BookmarksDao extends DatabaseAccessor<AppDatabase>
    with _$BookmarksDaoMixin {
  BookmarksDao(super.db);

  // ── Bookmarks ──────────────────────────────────────────────────────────────

  /// [watchAll] streams every bookmark, most recently saved first.
  Stream<List<BookmarkEntry>> watchAll() => (select(bookmarksTable)
        ..orderBy([
          (b) => OrderingTerm(expression: b.savedAt, mode: OrderingMode.desc),
        ]))
      .watch()
      .distinctList();

  Future<BookmarkEntry?> findById(String id) =>
      (select(bookmarksTable)..where((b) => b.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsert(BookmarksTableCompanion bookmark) =>
      into(bookmarksTable).insertOnConflictUpdate(bookmark);

  Future<int> deleteById(String id) =>
      (delete(bookmarksTable)..where((b) => b.id.equals(id))).go();

  // ── Folders (Requirement 6.4) ──────────────────────────────────────────────

  Stream<List<FolderEntry>> watchFolders() => (select(foldersTable)
        ..where((f) => f.scope.equals(FolderScope.bookmark.name))
        ..orderBy([(f) => OrderingTerm(expression: f.name)]))
      .watch()
      .distinctList();

  Future<void> upsertFolder(FoldersTableCompanion folder) =>
      into(foldersTable).insertOnConflictUpdate(folder);

  /// [deleteFolder] removes a folder and returns its bookmarks to the top level.
  /// The bookmarks are kept: deleting a folder is about how links are arranged,
  /// not whether the user still wants them.
  Future<void> deleteFolder(String id) => transaction(() async {
        await (update(bookmarksTable)..where((b) => b.folderId.equals(id)))
            .write(const BookmarksTableCompanion(folderId: Value(null)));

        await (delete(foldersTable)..where((f) => f.id.equals(id))).go();
      });
}
