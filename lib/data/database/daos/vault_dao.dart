import 'package:drift/drift.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/database/tables/tables.dart';
import 'package:everything_app/data/database/watch_extensions.dart';
import 'package:everything_app/data/models/folder.dart';

part 'vault_dao.g.dart';

/// [VaultDao] is every SQL statement the Vault issues (Requirement 9).
///
/// Nothing here encrypts or decrypts anything: it moves `encryptedPayload` in and
/// out as an opaque string, and the cipher lives in `SecurityService`. That is what
/// keeps the two concerns separable — the database layer cannot leak a plaintext it
/// has never held.
///
/// It shares [FoldersTable] with [BookmarksDao], so every folder statement here is
/// scoped to [FolderScope.vault].
@DriftAccessor(tables: [VaultItemsTable, FoldersTable])
class VaultDao extends DatabaseAccessor<AppDatabase> with _$VaultDaoMixin {
  VaultDao(super.db);

  // ── Items ──────────────────────────────────────────────────────────────────

  Stream<List<VaultItemEntry>> watchAll() => (select(vaultItemsTable)
        ..orderBy([(v) => OrderingTerm(expression: v.name)]))
      .watch()
      .distinctList();

  Future<VaultItemEntry?> findById(String id) =>
      (select(vaultItemsTable)..where((v) => v.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsert(VaultItemsTableCompanion item) =>
      into(vaultItemsTable).insertOnConflictUpdate(item);

  Future<int> deleteById(String id) =>
      (delete(vaultItemsTable)..where((v) => v.id.equals(id))).go();

  // ── Folders (Requirement 9.4) ──────────────────────────────────────────────

  Stream<List<FolderEntry>> watchFolders() => (select(foldersTable)
        ..where((f) => f.scope.equals(FolderScope.vault.name))
        ..orderBy([(f) => OrderingTerm(expression: f.name)]))
      .watch()
      .distinctList();

  Future<void> upsertFolder(FoldersTableCompanion folder) =>
      into(foldersTable).insertOnConflictUpdate(folder);

  /// [deleteFolder] removes a folder and returns its items to the top level.
  ///
  /// The items are kept, as in [BookmarksDao.deleteFolder] and for a stronger
  /// reason: a vault item is something the user chose to store because losing it
  /// would hurt, and a folder delete is not a request to lose it.
  Future<void> deleteFolder(String id) => transaction(() async {
        await (update(vaultItemsTable)..where((v) => v.folderId.equals(id)))
            .write(const VaultItemsTableCompanion(folderId: Value(null)));

        await (delete(foldersTable)..where((f) => f.id.equals(id))).go();
      });
}
