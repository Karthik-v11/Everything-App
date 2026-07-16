import 'dart:io';

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

  /// [AppDatabase.encrypted] describes the on-device database keyed with
  /// [encryptionKey].
  ///
  /// It does not open anything. `driftDatabase` returns a delayed connection, so
  /// sqlite3 is opened, keyed by [_applyKey] and verified by [_verifyKeyed] on
  /// the first query, in the background isolate drift runs its connection on.
  /// The verification is therefore off the UI isolate and off the path to the
  /// first frame — but it still runs before any statement this app issues can
  /// see a row, which is what it is for. A wrong key or a plain-SQLite binary
  /// still fails on the first read rather than corrupting data quietly.
  ///
  /// [databaseDirectory] and [temporaryDirectory] are the already-resolved
  /// `path_provider` paths. They are passed in because `drift_flutter` would
  /// otherwise resolve both itself, adding two platform round-trips to the first
  /// query. They are optional so that a caller with no bootstrap (a test) still
  /// gets the default lookup.
  ///
  /// [_discardIfUnreadable] runs first, so a file this key cannot open is
  /// replaced rather than left to fail every statement the app issues.
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
          await _createIndexes();
          await _createSearchIndex();
        },
      );

  /// [_createIndexes] backs the columns the streaming queries filter and sort on.
  ///
  /// Every `watch*` query re-runs on any write to its table and, without an
  /// index, does a full table scan plus an in-SQLite sort each time — the cost
  /// that shows up as a stutter when a list is long. These indexes turn those
  /// scans into lookups on the exact columns the DAOs use in `WHERE`/`ORDER BY`
  /// (see `tasks_dao`, `finance_dao`, `projects_dao`, `bookmarks_dao`,
  /// `vault_dao`).
  ///
  /// They are created here rather than through a `schemaVersion` bump on purpose:
  /// an index is derived data, not schema the app's models depend on, so
  /// `CREATE INDEX IF NOT EXISTS` on every open is idempotent, keeps the single
  /// schema version the rest of the code assumes, and covers a database written
  /// by an earlier build without a migration step. SQLite skips an index that
  /// already exists after a cheap catalogue check, so the repeated call costs
  /// nothing after the first launch.
  Future<void> _createIndexes() async {
    const statements = [
      // Tasks: the by-date list and the project sub-view.
      'CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks (due_date)',
      'CREATE INDEX IF NOT EXISTS idx_tasks_project_id ON tasks (project_id)',
      // Finance: the transaction list orders by date; balances group by account.
      'CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions (date)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_account_id '
          'ON transactions (account_id)',
      // Budgets are looked up by the month they apply to.
      'CREATE INDEX IF NOT EXISTS idx_budgets_month_year ON budgets (month, year)',
      // Folders are split into the bookmark and vault namespaces by scope.
      'CREATE INDEX IF NOT EXISTS idx_folders_scope ON folders (scope)',
      // Documents belonging to a project; attachments' polymorphic owner.
      'CREATE INDEX IF NOT EXISTS idx_documents_project_id '
          'ON documents (project_id)',
      'CREATE INDEX IF NOT EXISTS idx_attachments_owner '
          'ON attachments (owner_type, owner_id)',
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }

  /// [_createSearchIndex] builds the FTS5 index behind Global Search (Phase 9,
  /// Requirements 17, 24.2).
  ///
  /// Eight `LIKE '%q%'` scans across eight tables cannot hold the < 300 ms bar
  /// over 10,000 items (Requirement 24.2); an FTS5 virtual table indexed by
  /// tokens can. `search_index` is a **standalone** FTS5 table — [item_id] and
  /// [module] are stored `UNINDEXED` so a hit maps back to its row and its
  /// module, and only [title] and [body] are tokenised.
  ///
  /// It is kept in sync by triggers on each source table rather than rewritten on
  /// read: every write to a task, a transaction, a bookmark and so on reconciles
  /// its one FTS row, so search is always current without a rebuild step. The
  /// per-write cost is a delete-by-scan of the FTS content on update/delete, which
  /// is a few milliseconds against a single-row write and never on the read path
  /// the requirement bounds.
  ///
  /// **The vault contributes its [VaultItemsTable.name] and nothing else**
  /// (Requirement 9.5): its `encryptedPayload` is never tokenised, so a vault
  /// search matches on the item's title alone and its contents never enter an
  /// index.
  ///
  /// Like [_createIndexes], this runs on every open behind `IF NOT EXISTS` rather
  /// than through a `schemaVersion` bump: the index is derived data, not schema
  /// the models depend on. The one-time [_backfillSearchIndex] seeds it from rows
  /// written by builds that predate it — the triggers only fire on future writes.
  Future<void> _createSearchIndex() async {
    final existed = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = "
      "'search_index'",
    ).get();

    await customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5('
      'item_id UNINDEXED, module UNINDEXED, title, body, '
      "tokenize = 'unicode61 remove_diacritics 2')",
    );

    for (final source in _searchSources) {
      // AFTER INSERT: add the new row's searchable text.
      await customStatement(
        'CREATE TRIGGER IF NOT EXISTS search_ai_${source.table} '
        'AFTER INSERT ON ${source.table} BEGIN '
        'INSERT INTO search_index(item_id, module, title, body) VALUES '
        "(new.id, '${source.module}', ${source.titleExpr('new.')}, "
        '${source.bodyExpr('new.')}); END',
      );
      // AFTER UPDATE: drop the old FTS row and re-add. An in-place update is not
      // possible without the FTS rowid, which the string primary key is not.
      await customStatement(
        'CREATE TRIGGER IF NOT EXISTS search_au_${source.table} '
        'AFTER UPDATE ON ${source.table} BEGIN '
        "DELETE FROM search_index WHERE module = '${source.module}' "
        'AND item_id = old.id; '
        'INSERT INTO search_index(item_id, module, title, body) VALUES '
        "(new.id, '${source.module}', ${source.titleExpr('new.')}, "
        '${source.bodyExpr('new.')}); END',
      );
      // AFTER DELETE: withdraw the row's text so a deleted item stops matching.
      await customStatement(
        'CREATE TRIGGER IF NOT EXISTS search_ad_${source.table} '
        'AFTER DELETE ON ${source.table} BEGIN '
        "DELETE FROM search_index WHERE module = '${source.module}' "
        'AND item_id = old.id; END',
      );
    }

    if (existed.isEmpty) await _backfillSearchIndex();
  }

  /// [_backfillSearchIndex] seeds the FTS index from existing rows, once.
  ///
  /// Runs only the first time [search_index] is created — the triggers cover
  /// every write after that. Without it, a database that already holds a user's
  /// tasks and transactions from an earlier build would search as though empty
  /// until each row happened to be edited.
  Future<void> _backfillSearchIndex() async {
    for (final source in _searchSources) {
      await customStatement(
        'INSERT INTO search_index(item_id, module, title, body) '
        "SELECT id, '${source.module}', ${source.titleExpr('')}, "
        '${source.bodyExpr('')} FROM ${source.table}',
      );
    }
  }

  /// [_searchSources] is the eight modules Global Search spans (Requirement 17.1)
  /// and the columns each contributes to the index.
  ///
  /// [body] is empty for the two modules with nothing to index past their title —
  /// the watchlist, and the vault, whose contents are encrypted and must never be
  /// indexed (Requirement 9.5).
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

  /// [_sqliteNotADb] is SQLITE_NOTADB, what SQLCipher returns when page 1 fails
  /// to decrypt: the file was written with a different key, or with none.
  static const int _sqliteNotADb = 26;

  /// [_fileIn] is the path `drift_flutter` will open for [kDatabaseName].
  ///
  /// It appends the same `.sqlite` suffix `driftDatabase` does, so the probe and
  /// drift agree on which file is being talked about. A mismatch here would leave
  /// the real database unchecked and delete nothing.
  static String _fileIn(String directory) => '$directory/$kDatabaseName.sqlite';

  /// [_discardIfUnreadable] deletes a database [encryptionKey] cannot open.
  ///
  /// A key and a file drift apart when the file predates encryption, or when the
  /// keystore entry is lost while the file survives — a restored backup, a reset
  /// keystore. [SecurityService.databaseKey] then mints a *fresh* key, and every
  /// statement the app issues dies at `PRAGMA key` on a file that key never
  /// wrote. The data in it is gone either way: it cannot be decrypted without the
  /// original key, and nothing in the app still holds one. Replacing the file at
  /// least leaves a working app rather than one where every write reports a
  /// module-specific failure that has nothing to do with the module.
  ///
  /// **This deletes user data, so it is deliberately narrow.** Only
  /// [_sqliteNotADb] — page 1 provably did not decrypt — is treated as a
  /// mismatch. Every other failure rethrows untouched: a locked, busy, or
  /// permission-denied file is a transient problem whose data is still intact and
  /// still readable once the cause clears, and wiping it would turn a bad launch
  /// into permanent loss. A missing file is a first launch and needs no probe.
  static Future<void> _discardIfUnreadable(
    String path,
    String encryptionKey,
  ) async {
    final file = File(path);
    if (!file.existsSync()) return;

    // Opened here rather than in drift's `setup` because the recovery is a file
    // operation: by the time `setup` runs, drift holds an open handle on the very
    // file that would have to be replaced. This costs one page-1 read per launch,
    // off the path to the first frame but on the UI isolate.
    final database = sqlite3.open(path);
    try {
      _applyKey(database, encryptionKey);
      return;
    } on SqliteException catch (error) {
      if (error.resultCode != _sqliteNotADb) rethrow;
    } finally {
      database.close();
    }

    await file.delete();

    // The journal and shared-memory sidecars describe the file just deleted.
    // Leaving them would hand the fresh database another database's journal.
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('$path$suffix');
      if (sidecar.existsSync()) await sidecar.delete();
    }
  }

  /// [_applyKey] keys the connection and proves the result is really encrypted.
  ///
  /// `PRAGMA key` must be the very first statement on the connection — any read
  /// before it locks the database into plaintext mode for that handle.
  static void _applyKey(CommonDatabase database, String encryptionKey) {
    // The key is interpolated into SQL, so a `'` in it would break out of the
    // literal. Keys are hex, but the escaping holds regardless.
    final escaped = encryptionKey.replaceAll("'", "''");
    database.execute("PRAGMA key = '$escaped';");
    _verifyKeyed(database);
  }

  /// [_verifyKeyed] throws if SQLCipher is not present in the built binary.
  ///
  /// Plain SQLite ignores an unknown `PRAGMA key` instead of erroring, so without
  /// this check a mis-built binary would run correctly while writing an entirely
  /// unencrypted database. The pubspec `hooks` block is what selects SQLCipher.
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

/// [_SearchSource] describes one module's contribution to the FTS index
/// (see [AppDatabase._searchSources]).
///
/// [titleExpr] and [bodyExpr] render the same columns in two contexts: prefixed
/// with `new.` inside a trigger, and bare inside the one-time backfill `SELECT`.
/// Every column is `coalesce`d to `''` so a null note or description never nulls
/// the whole indexed value.
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
