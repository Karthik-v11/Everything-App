import 'package:drift/drift.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/database/tables/tables.dart';
import 'package:everything_app/data/database/watch_extensions.dart';
import 'package:everything_app/data/models/folder.dart';

part 'bookmarks_dao.g.dart';

/// [BookmarksDao] is every SQL statement the Bookmarks sub-feature issues
/// (Requirement 6).
///
/// As in the other DAOs, `watch*` returns a stream: drift re-runs the query on any
/// change to the rows behind it, so a bookmark saved in the sheet — or enriched in
/// the background once its page has been fetched — refreshes the list with no
/// reload event.
///
/// It reaches [FoldersTable] as well as its own, and every folder statement here is
/// scoped to [FolderScope.bookmark]. The vault shares that table, and an unscoped
/// query would put the user's vault folders in the bookmark folder picker.
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
  ///
  /// The bookmarks themselves are kept. Deleting a folder is a statement about how
  /// the user wants their links *arranged*, not about whether they still want them
  /// — and a folder delete that silently took thirty saved links with it is the
  /// kind of thing an undo button exists to apologise for.
  Future<void> deleteFolder(String id) => transaction(() async {
        await (update(bookmarksTable)..where((b) => b.folderId.equals(id)))
            .write(const BookmarksTableCompanion(folderId: Value(null)));

        await (delete(foldersTable)..where((f) => f.id.equals(id))).go();
      });
}
