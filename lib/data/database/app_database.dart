import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/data/database/tables/tables.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

part 'app_database.g.dart';

/// [AppDatabase] is the app's single local database, the Offline_Store.
///
/// It is opened as SQLCipher with a 256-bit key held in the platform keychain or
/// keystore, satisfying AES-256 at rest (Requirement 23.1). The key is never
/// stored in the database, in shared preferences, or in the app bundle.
///
/// Every read and write in the app goes through here; there is no network source
/// of truth (Requirement 21).
@DriftDatabase(
  tables: [
    TasksTable,
    CategoriesTable,
    TransactionsTable,
    AccountsTable,
    BudgetsTable,
    BookmarksTable,
    ToBuyItemsTable,
    WatchlistTable,
    VaultItemsTable,
    FoldersTable,
    ProjectsTable,
    DocumentsTable,
    AttachmentsTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Describes — does not open — the on-device database keyed with
  /// [encryptionKey]. `driftDatabase` returns a delayed connection, so sqlite3 is
  /// opened, keyed by [_applyKey] and verified by [_verifyKeyed] on the first
  /// query, in drift's background isolate: off the path to the first frame, but
  /// still before any statement can see a row. A wrong key or a plain-SQLite
  /// binary fails on the first read rather than corrupting data quietly.
  ///
  /// [databaseDirectory] and [temporaryDirectory] are already-resolved
  /// `path_provider` paths, passed in because `drift_flutter` would otherwise
  /// resolve both itself, adding two platform round-trips to the first query.
  /// Optional so a caller with no bootstrap (a test) gets the default lookup.
  ///
  /// [_discardIfUnreadable] runs first, so a file this key cannot open is replaced
  /// rather than left to fail every statement the app issues.
  factory AppDatabase.encrypted({
    required String encryptionKey,
    String? databaseDirectory,
    String? temporaryDirectory,
  }) {
    return AppDatabase(
      DatabaseConnection.delayed(
        Future(() async {
          // Skipped when the directory was not passed: locating the file would
          // need `path_provider`, which is confined to the bootstrap (CLAUDE.md
          // §14). Every caller that opens a real database supplies it.
          if (databaseDirectory != null) {
            await _discardIfUnreadable(
              _fileIn(databaseDirectory),
              encryptionKey,
            );
          }

          return driftDatabase(
            name: kDatabaseName,
            native: DriftNativeOptions(
              databaseDirectory: databaseDirectory == null
                  ? null
                  : (() async => databaseDirectory),
              tempDirectoryPath: temporaryDirectory == null
                  ? null
                  : (() async => temporaryDirectory),
              setup: (database) => _applyKey(database, encryptionKey),
            ),
          );
        }),
      ),
    );
  }

  /// [AppDatabase.memory] is an unencrypted in-memory database for tests.
  factory AppDatabase.memory() =>
      AppDatabase(DatabaseConnection(NativeDatabase.memory()));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        beforeOpen: (details) async {
          // Drift does not enable foreign keys by default, and SQLite ignores
          // every FK constraint silently until it is switched on per connection.
          await customStatement('PRAGMA foreign_keys = ON');

          // All index and trigger creation is batched into a single round-trip
          // to drift's background isolate. Running them sequentially cost 32
          // individual marshalling round-trips, which was the single largest
          // cold-start bottleneck on the path to the first row of data.
          await batch((b) {
            for (final statement in _indexStatements) {
              b.customStatement(statement);
            }
          });
          await _createSearchIndexBatched();
        },
      );

  /// Indexes backing the columns the streaming queries filter and sort on. Every
  /// `watch*` query re-runs on any write to its table and, unindexed, does a full
  /// scan plus an in-SQLite sort each time — the stutter on a long list.
  ///
  /// Created here rather than via a `schemaVersion` bump: an index is derived
  /// data, not schema the models depend on, so `IF NOT EXISTS` on every open is
  /// idempotent, keeps the single schema version, and covers a database written by
  /// an earlier build with no migration step. SQLite skips an existing index after
  /// a cheap catalogue check.
  static const List<String> _indexStatements = [
    // Tasks: `watchForDate` filters on due_date alone.
    'CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks (due_date)',
    // `TasksDao.watchAll` sorts on the *expression* `(due_date IS NULL)` first,
    // which no plain column index can satisfy — it scanned and built a temp
    // B-tree on every write to `tasks`. These two match the ORDER BY term for
    // term, including the leading expression, so the scan walks the index in
    // order and the sort disappears. Verified with EXPLAIN QUERY PLAN.
    'CREATE INDEX IF NOT EXISTS idx_tasks_order '
        'ON tasks ((due_date IS NULL), due_date ASC, created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_tasks_project_order '
        'ON tasks (project_id, (due_date IS NULL), due_date ASC, created_at DESC)',
    // Subsumed by idx_tasks_project_order, which leads with the same column.
    'DROP INDEX IF EXISTS idx_tasks_project_id',
    // Finance: the transaction list orders by date then created_at. A date-only
    // index still left the tiebreak to a temp B-tree; the composite covers both
    // terms and makes the date-only index redundant.
    'CREATE INDEX IF NOT EXISTS idx_transactions_order '
        'ON transactions (date DESC, created_at DESC)',
    'DROP INDEX IF EXISTS idx_transactions_date',
    'CREATE INDEX IF NOT EXISTS idx_transactions_account_id '
        'ON transactions (account_id)',
    // Budgets are looked up by the month they apply to.
    'CREATE INDEX IF NOT EXISTS idx_budgets_month_year ON budgets (month, year)',
    // Folders are split into the bookmark and vault namespaces by scope, then
    // listed by name; the composite serves both clauses of that one query and
    // makes the scope-only index it replaces redundant.
    'CREATE INDEX IF NOT EXISTS idx_folders_scope_name ON folders (scope, name)',
    'DROP INDEX IF EXISTS idx_folders_scope',
    // Documents belonging to a project; attachments' polymorphic owner.
    'CREATE INDEX IF NOT EXISTS idx_documents_project_id '
        'ON documents (project_id)',
    'CREATE INDEX IF NOT EXISTS idx_attachments_owner '
        'ON attachments (owner_type, owner_id)',
    // The remaining list orders. Each backs an `ORDER BY` on a whole-table watch,
    // which re-runs on every write to its table.
    'CREATE INDEX IF NOT EXISTS idx_bookmarks_saved_at ON bookmarks (saved_at)',
    'CREATE INDEX IF NOT EXISTS idx_documents_updated_at '
        'ON documents (updated_at)',
    'CREATE INDEX IF NOT EXISTS idx_to_buy_items_created_at '
        'ON to_buy_items (created_at)',
    'CREATE INDEX IF NOT EXISTS idx_watchlist_created_at '
        'ON watchlist (created_at)',
    'CREATE INDEX IF NOT EXISTS idx_projects_created_at '
        'ON projects (created_at)',
    'CREATE INDEX IF NOT EXISTS idx_vault_items_name ON vault_items (name)',
    'CREATE INDEX IF NOT EXISTS idx_accounts_name ON accounts (name)',
    // Reassigning a folder's contents when the folder is deleted.
    'CREATE INDEX IF NOT EXISTS idx_bookmarks_folder_id '
        'ON bookmarks (folder_id)',
    'CREATE INDEX IF NOT EXISTS idx_vault_items_folder_id '
        'ON vault_items (folder_id)',
  ];

  /// Builds the FTS5 index behind Global Search (Requirements 17, 24.2) in a
  /// single batched round-trip.
  ///
  /// Eight `LIKE '%q%'` scans cannot hold the <300 ms bar over 10,000 items
  /// (Requirement 24.2); a token-indexed FTS5 virtual table can. `search_index` is
  /// standalone: `item_id` and `module` are `UNINDEXED` so a hit maps back to its
  /// row, and only `title` and `body` are tokenised.
  ///
  /// Triggers on each source table keep it in sync per write, so search is always
  /// current with no rebuild step and nothing on the read path the requirement
  /// bounds.
  ///
  /// The vault contributes its [VaultItemsTable.name] and nothing else
  /// (Requirement 9.5): `encryptedPayload` is never tokenised, so its contents
  /// never enter an index.
  ///
  /// Runs on every open behind `IF NOT EXISTS` rather than a `schemaVersion` bump
  /// — derived data, not schema. [_backfillSearchIndex] seeds it once from rows
  /// predating it; the triggers only fire on future writes.
  Future<void> _createSearchIndexBatched() async {
    final existed = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = "
      "'search_index'",
    ).get();

    // FTS table + 8 sources × 3 triggers in one batched round-trip.
    await batch((b) {
      b.customStatement(
        'CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5('
        'item_id UNINDEXED, module UNINDEXED, title, body, '
        "tokenize = 'unicode61 remove_diacritics 2')",
      );

      for (final source in _searchSources) {
        // AFTER INSERT: add the new row's searchable text.
        b.customStatement(
          'CREATE TRIGGER IF NOT EXISTS search_ai_${source.table} '
          'AFTER INSERT ON ${source.table} BEGIN '
          'INSERT INTO search_index(item_id, module, title, body) VALUES '
          "(new.id, '${source.module}', ${source.titleExpr('new.')}, "
          '${source.bodyExpr('new.')}); END',
        );
        // AFTER UPDATE: drop the old FTS row and re-add. An in-place update is
        // not possible without the FTS rowid, which the string primary key is
        // not.
        b.customStatement(
          'CREATE TRIGGER IF NOT EXISTS search_au_${source.table} '
          'AFTER UPDATE ON ${source.table} BEGIN '
          "DELETE FROM search_index WHERE module = '${source.module}' "
          'AND item_id = old.id; '
          'INSERT INTO search_index(item_id, module, title, body) VALUES '
          "(new.id, '${source.module}', ${source.titleExpr('new.')}, "
          '${source.bodyExpr('new.')}); END',
        );
        // AFTER DELETE: withdraw the row's text so a deleted item stops
        // matching.
        b.customStatement(
          'CREATE TRIGGER IF NOT EXISTS search_ad_${source.table} '
          'AFTER DELETE ON ${source.table} BEGIN '
          "DELETE FROM search_index WHERE module = '${source.module}' "
          'AND item_id = old.id; END',
        );
      }
    });

    if (existed.isEmpty) await _backfillSearchIndex();
  }

  /// Seeds the FTS index from existing rows, only the first time `search_index` is
  /// created — the triggers cover every write after that. Without it, a database
  /// from an earlier build would search as though empty until each row was edited.
  Future<void> _backfillSearchIndex() async {
    await batch((b) {
      for (final source in _searchSources) {
        b.customStatement(
          'INSERT INTO search_index(item_id, module, title, body) '
          "SELECT id, '${source.module}', ${source.titleExpr('')}, "
          '${source.bodyExpr('')} FROM ${source.table}',
        );
      }
    });
  }

  /// The eight modules Global Search spans (Requirement 17.1) and the columns each
  /// contributes. [body] is empty for the watchlist, and for the vault, whose
  /// contents are encrypted and must never be indexed (Requirement 9.5).
  static const List<_SearchSource> _searchSources = [
    _SearchSource(module: 'tasks', table: 'tasks', body: ['notes']),
    _SearchSource(
      module: 'transactions',
      table: 'transactions',
      body: ['category', 'notes'],
    ),
    _SearchSource(module: 'bookmarks', table: 'bookmarks', body: ['url']),
    _SearchSource(
      module: 'to_buy',
      table: 'to_buy_items',
      title: 'name',
      body: ['store', 'notes'],
    ),
    _SearchSource(module: 'watchlist', table: 'watchlist'),
    _SearchSource(module: 'vault', table: 'vault_items', title: 'name'),
    _SearchSource(
      module: 'projects',
      table: 'projects',
      title: 'name',
      body: ['description'],
    ),
    _SearchSource(
      module: 'documents',
      table: 'documents',
      body: ['content_json'],
    ),
  ];

  /// SQLITE_NOTADB, what SQLCipher returns when page 1 fails to decrypt: the file
  /// was written with a different key, or with none.
  static const int _sqliteNotADb = 26;

  /// The path `drift_flutter` will open for [kDatabaseName]. Appends the same
  /// `.sqlite` suffix `driftDatabase` does — a mismatch would leave the real
  /// database unchecked and delete nothing.
  static String _fileIn(String directory) => '$directory/$kDatabaseName.sqlite';

  /// Deletes a database [encryptionKey] cannot open.
  ///
  /// A key and a file drift apart when the file predates encryption, or when the
  /// keystore entry is lost while the file survives (a restored backup, a reset
  /// keystore). [SecurityService.databaseKey] then mints a fresh key and every
  /// statement dies at `PRAGMA key`. The data is unrecoverable either way, so
  /// replacing the file at least leaves a working app.
  ///
  /// This deletes user data, so it is deliberately narrow: only [_sqliteNotADb] —
  /// page 1 provably did not decrypt — counts as a mismatch. Every other failure
  /// rethrows: a locked, busy or permission-denied file is transient, its data
  /// intact, and wiping it would turn a bad launch into permanent loss. A missing
  /// file is a first launch and needs no probe.
  ///
  /// The probe runs on a spawned isolate. It opens and keys sqlite3 over FFI,
  /// which is synchronous and blocks whichever isolate it lands on; run inline it
  /// would land on the UI isolate, because `DatabaseConnection.delayed` schedules
  /// its future on the calling isolate — i.e. on top of the first frames, not
  /// inside drift's background isolate the way the keyed connection itself is.
  static Future<void> _discardIfUnreadable(
    String path,
    String encryptionKey,
  ) async {
    if (!File(path).existsSync()) return;

    final isReadable = await Isolate.run(() => _probeKey(path, encryptionKey));
    if (isReadable) return;

    await File(path).delete();

    // The journal and shared-memory sidecars describe the file just deleted.
    // Leaving them would hand the fresh database another database's journal.
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('$path$suffix');
      if (sidecar.existsSync()) await sidecar.delete();
    }
  }

  /// Whether [encryptionKey] can actually decrypt the database at [path].
  ///
  /// Runs on a spawned isolate (see [_discardIfUnreadable]), so it must be a
  /// top-level-callable static taking only sendable arguments, and must return a
  /// sendable result rather than an open handle.
  ///
  /// Opened here rather than in drift's `setup`: by the time `setup` runs, drift
  /// holds an open handle on the very file that would have to be replaced.
  static bool _probeKey(String path, String encryptionKey) {
    final database = sqlite3.open(path);
    try {
      _applyKey(database, encryptionKey);
      return true;
    } on SqliteException catch (error) {
      // Narrow by design: only a provable page-1 decryption failure means the key
      // and the file have diverged. A locked, busy or permission-denied file is
      // transient and its data intact, so it rethrows rather than being wiped.
      if (error.resultCode != _sqliteNotADb) rethrow;
      return false;
    } finally {
      database.close();
    }
  }

  /// Keys the connection and proves the result is really encrypted. `PRAGMA key`
  /// must be the first statement on the connection — any read before it locks the
  /// handle into plaintext mode.
  ///
  /// The key is passed in SQLCipher's raw form (`x'<64 hex>'`), not as a
  /// passphrase. Given a passphrase, SQLCipher stretches it with 256,000 rounds of
  /// PBKDF2-HMAC-SHA512 — 150–400 ms on a midrange device, paid on every open.
  /// [SecurityService.databaseKey] already mints the key as 32 bytes of CSPRNG
  /// output, so there is no low-entropy passphrase to stretch and the KDF buys
  /// nothing. The raw form skips it and uses the 32 bytes as the cipher key
  /// directly, which is what the stretching was only ever approximating.
  static void _applyKey(CommonDatabase database, String encryptionKey) {
    // Raw-key syntax takes exactly 64 hex characters. Anything else would be
    // parsed as a passphrase instead — silently reinstating the KDF and, worse,
    // deriving a different key than the one this file was written with.
    assert(
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(encryptionKey),
      'The database key must be 64 hex characters for SQLCipher raw-key mode.',
    );
    database.execute('PRAGMA key = "x\'$encryptionKey\'";');
    _verifyKeyed(database);
  }

  /// Throws if SQLCipher is absent from the built binary. Plain SQLite ignores an
  /// unknown `PRAGMA key` instead of erroring, so without this check a mis-built
  /// binary would run correctly while writing an entirely unencrypted database.
  static void _verifyKeyed(CommonDatabase database) {
    final cipher = database.select('PRAGMA cipher_version;');
    if (cipher.isEmpty || '${cipher.first.values.first}'.trim().isEmpty) {
      throw StateError(
        'SQLCipher is not available: the database would be stored unencrypted. '
        'Check the `hooks: user_defines: sqlite3: source: sqlcipher` block in '
        'pubspec.yaml.',
      );
    }

    // Forces SQLCipher to decrypt page 1 now, so a wrong key throws here rather
    // than at an arbitrary later read.
    database.execute('SELECT count(*) FROM sqlite_master;');
  }
}

/// One module's contribution to the FTS index (see [AppDatabase._searchSources]).
///
/// [titleExpr] and [bodyExpr] render the same columns in two contexts: prefixed
/// with `new.` inside a trigger, and bare inside the backfill `SELECT`. Every
/// column is `coalesce`d to `''` so a null note never nulls the whole value.
class _SearchSource {
  const _SearchSource({
    required this.module,
    required this.table,
    this.title = 'title',
    this.body = const [],
  });

  final String module;
  final String table;
  final String title;
  final List<String> body;

  String titleExpr(String prefix) => "coalesce($prefix$title, '')";

  String bodyExpr(String prefix) {
    if (body.isEmpty) return "''";
    return body.map((column) => "coalesce($prefix$column, '')").join(" || ' ' || ");
  }
}
