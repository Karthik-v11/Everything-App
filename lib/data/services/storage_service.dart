import 'dart:io';

import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/storage_usage.dart';
import 'package:path_provider/path_provider.dart';

/// [StorageService] measures what the app occupies, per module
/// (Requirement 25.4).
///
/// ## Where the per-module figure comes from
///
/// Every module's rows live in **one** SQLite file, so "how much is Tasks using"
/// is not a question the file system can answer — `everything.db` is one number.
/// SQLite's `dbstat` virtual table can: it reports the page count per table, and
/// pages are what the file is made of, so summing `pgsize` per table is the real
/// on-disk cost rather than an estimate from row counts and average widths.
///
/// It is queried defensively. `dbstat` is a compile-time option
/// (`SQLITE_ENABLE_DBSTAT_VTAB`), and this app builds SQLite from source as
/// SQLCipher through a build hook (see `pubspec.yaml`) — a flag change upstream
/// would take it away with no warning at all, and the Settings screen would throw
/// where it used to inform. So a failure falls back to row counts with
/// [StorageUsage.isEstimated] set, and the screen says "142 items" instead of
/// claiming a size it cannot know.
class StorageService {
  StorageService({required this.database, this.documentsDirectoryOverride});

  final AppDatabase database;

  /// A test seam, the same one `BackupService` takes:
  /// `getApplicationDocumentsDirectory` needs a platform channel, so a test hands
  /// a temp directory instead. `start.dart` resolves the real one and is
  /// protected (CLAUDE.md §0), so it is resolved again here rather than threaded
  /// through `Bootstrap`.
  final String? documentsDirectoryOverride;

  /// Which tables belong to which module.
  ///
  /// `attachments` is Library's: the row is the record of a file the Library owns.
  /// The file's own bytes are counted separately, from the directory, because
  /// they are not in the database at all — the row is a path and a name.
  static const Map<StorageModule, List<String>> _tablesByModule = {
    StorageModule.tasks: ['tasks', 'categories'],
    StorageModule.library: [
      'bookmarks',
      'to_buy_items',
      'watchlist',
      'vault_items',
      'folders',
      'projects',
      'documents',
      'attachments',
    ],
    StorageModule.finance: ['transactions', 'accounts', 'budgets'],
  };

  /// [read] measures everything and returns the breakdown.
  Future<JsonResponse> read() async {
    try {
      final documents = await _documentsDirectory();

      final databaseBytes = await _databaseBytes(documents);
      final attachmentBytes = await _directoryBytes('$documents/attachments');
      final backupBytes = await _directoryBytes('$documents/backups');

      final perTable = await _bytesPerTable();
      final counts = await _rowsPerModule();

      final lines = <StorageLine>[];
      var accountedFor = 0;

      for (final entry in _tablesByModule.entries) {
        final bytes = perTable == null
            ? 0
            : entry.value.fold(
                0,
                (sum, table) => sum + (perTable[table] ?? 0),
              );

        accountedFor += bytes;

        lines.add(
          StorageLine(
            module: entry.key,
            bytes: entry.key == StorageModule.library
                ? bytes + attachmentBytes
                : bytes,
            itemCount: counts[entry.key] ?? 0,
          ),
        );
      }

      if (perTable != null) {
        // The FTS index is several shadow tables (`search_index`,
        // `search_index_data`, `_idx`, `_content`, `_docsize`, `_config`), and it
        // is genuinely large — it holds a copy of every title and body in the app.
        // Folding it into the modules it indexes would make each of them look
        // twice its size; naming it is the honest answer, and it is also the one
        // line here a user might act on.
        final searchBytes = perTable.entries
            .where((entry) => entry.key.startsWith('search_index'))
            .fold(0, (sum, entry) => sum + entry.value);
        accountedFor += searchBytes;

        lines.add(
          StorageLine(module: StorageModule.search, bytes: searchBytes),
        );
      }

      lines.add(
        StorageLine(
          module: StorageModule.backups,
          bytes: backupBytes,
          detail: backupBytes == 0 ? 'No backups yet' : '',
        ),
      );

      // Phase 13's model is downloaded on demand and does not exist yet. Saying
      // "Not installed" is the honest line; omitting the row would leave a
      // requirement's named module silently missing, and showing "0 B" would
      // imply an installed model that weighs nothing.
      lines.add(
        const StorageLine(
          module: StorageModule.aiModel,
          bytes: 0,
          detail: 'Not installed',
        ),
      );

      if (perTable != null) {
        // Whatever the file is that the modules are not: the schema, drift's
        // bookkeeping, and free pages a delete left behind. Never negative — a
        // database that has just been vacuumed can measure smaller than the sum
        // of its parts by a page or two.
        final other = databaseBytes - accountedFor;
        lines.add(
          StorageLine(
            module: StorageModule.other,
            bytes: other > 0 ? other : 0,
          ),
        );
      }

      return JsonResponse.success(
        message: 'Loaded successfully.',
        data: StorageUsage(
          lines: lines,
          databaseBytes: databaseBytes,
          attachmentBytes: attachmentBytes,
          isEstimated: perTable == null,
        ),
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not measure storage.',
      );
    }
  }

  /// [_bytesPerTable] is `dbstat`'s per-table page total, or null if the build
  /// does not carry the virtual table.
  Future<Map<String, int>?> _bytesPerTable() async {
    try {
      final rows = await database
          .customSelect('SELECT name, SUM(pgsize) AS bytes FROM dbstat '
              'GROUP BY name')
          .get();

      return {
        for (final row in rows)
          row.read<String>('name'): row.read<int?>('bytes') ?? 0,
      };
    } on Exception {
      return null;
    }
  }

  Future<Map<StorageModule, int>> _rowsPerModule() async {
    final counts = <StorageModule, int>{};

    for (final entry in _tablesByModule.entries) {
      var total = 0;
      for (final table in entry.value) {
        total += await _rowCount(table);
      }
      counts[entry.key] = total;
    }

    return counts;
  }

  Future<int> _rowCount(String table) async {
    try {
      final row = await database
          .customSelect('SELECT COUNT(*) AS c FROM $table')
          .getSingleOrNull();
      return row?.read<int?>('c') ?? 0;
    } on Exception {
      return 0;
    }
  }

  Future<String> _documentsDirectory() async {
    final override = documentsDirectoryOverride;
    if (override != null) return override;

    return (await getApplicationDocumentsDirectory()).path;
  }

  /// [_databaseBytes] is the database's real footprint, sidecars included.
  ///
  /// Two things here are easy to get wrong and both report a confident zero when
  /// you do:
  ///
  /// 1. **The file is not `everything.db`.** `drift_flutter` appends `.sqlite` to
  ///    the name it is given, and the name it is given (`kDatabaseName`) already
  ///    ends in `.db` — so the file on disk is `everything.db.sqlite`. Measuring
  ///    the obvious name measures a file that does not exist.
  /// 2. **The WAL is part of it.** SQLite in WAL mode keeps `-wal` and `-shm`
  ///    beside the database, and the `-wal` is not small — it holds every write
  ///    since the last checkpoint. Omitting it under-reports the app's real disk
  ///    use, sometimes by megabytes, right after a busy session.
  Future<int> _databaseBytes(String documents) async {
    const String base = '$kDatabaseName.sqlite';

    var total = 0;
    for (final suffix in ['', '-wal', '-shm']) {
      total += await _fileBytes('$documents/$base$suffix');
    }
    return total;
  }

  Future<int> _fileBytes(String path) async {
    try {
      final file = File(path);
      return file.existsSync() ? await file.length() : 0;
    } on FileSystemException {
      return 0;
    }
  }

  /// [_directoryBytes] sums a directory's files, one level deep.
  ///
  /// Not recursive: both directories it is pointed at are flat by construction
  /// (`AttachmentsService` writes `<id><ext>` and `BackupService` writes one file
  /// per backup), and a recursive walk of a user's documents directory is a
  /// Settings screen that gets slower the longer the app is owned.
  Future<int> _directoryBytes(String? path) async {
    if (path == null) return 0;

    try {
      final directory = Directory(path);
      if (!directory.existsSync()) return 0;

      var total = 0;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } on FileSystemException {
      return 0;
    }
  }
}
