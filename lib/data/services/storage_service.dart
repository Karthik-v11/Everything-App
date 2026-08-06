import 'dart:io';

import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/storage_usage.dart';
import 'package:path_provider/path_provider.dart';

/// [StorageService] measures what the app occupies, per module
/// (Requirement 25.4).
///
/// Every module's rows share one SQLite file, so per-module size comes from the
/// `dbstat` virtual table (`pgsize` summed per table) rather than the file
/// system. `dbstat` is a compile-time option (`SQLITE_ENABLE_DBSTAT_VTAB`) and
/// this app builds SQLite from source as SQLCipher (see `pubspec.yaml`), so it
/// can vanish upstream without warning: a failure falls back to row counts with
/// [StorageUsage.isEstimated] set rather than claiming a size it cannot know.
class StorageService {
  StorageService({required this.database, this.documentsDirectoryOverride});

  final AppDatabase database;

  /// Test seam: `getApplicationDocumentsDirectory` needs a platform channel, so
  /// a test hands a temp directory instead.
  final String? documentsDirectoryOverride;

  /// Which tables belong to which module. `attachments` is Library's; the files'
  /// own bytes are counted separately from the directory, as the row holds only
  /// a path and a name.
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
        // The FTS index is several `search_index*` shadow tables holding a copy
        // of every title and body, so folding it into the modules it indexes
        // would make each look twice its size.
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

      if (perTable != null) {
        // The schema, drift's bookkeeping, and free pages a delete left behind.
        // Clamped: a just-vacuumed database can measure smaller than the sum of
        // its parts by a page or two.
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

  /// Every module's row count in one statement.
  ///
  /// Counting table by table meant one awaited round-trip to drift's background
  /// isolate per table — fourteen of them, fully serialised, to fill one section
  /// of the Settings screen. Scalar subqueries fold them into a single hop, the
  /// way [_bytesPerTable] already reads every table's size in one grouped
  /// `dbstat` query.
  Future<Map<StorageModule, int>> _rowsPerModule() async {
    final tables = [
      for (final entry in _tablesByModule.entries) ...entry.value,
    ];

    // The alias is positional (`c0`, `c1`, …) rather than the table name: table
    // names are safe here (they are this file's own constants, not input), but
    // the index keeps the read below independent of quoting rules.
    final projection = [
      for (var i = 0; i < tables.length; i++)
        '(SELECT COUNT(*) FROM ${tables[i]}) AS c$i',
    ].join(', ');

    try {
      final row =
          await database.customSelect('SELECT $projection').getSingleOrNull();
      if (row == null) return _zeroCounts;

      final byTable = <String, int>{
        for (var i = 0; i < tables.length; i++)
          tables[i]: row.read<int?>('c$i') ?? 0,
      };

      final counts = <StorageModule, int>{};
      for (final entry in _tablesByModule.entries) {
        var total = 0;
        for (final table in entry.value) {
          total += byTable[table] ?? 0;
        }
        counts[entry.key] = total;
      }
      return counts;
    } on Exception {
      return _zeroCounts;
    }
  }

  Map<StorageModule, int> get _zeroCounts => {
        for (final module in _tablesByModule.keys) module: 0,
      };

  Future<String> _documentsDirectory() async {
    final override = documentsDirectoryOverride;
    if (override != null) return override;

    return (await getApplicationDocumentsDirectory()).path;
  }

  /// [_databaseBytes] is the database's real footprint, sidecars included.
  ///
  /// `drift_flutter` appends `.sqlite` to `kDatabaseName`, which already ends in
  /// `.db`, so the file on disk is `everything.db.sqlite`. The `-wal` and `-shm`
  /// sidecars count too: the WAL holds every write since the last checkpoint and
  /// can be megabytes.
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
  /// (`AttachmentsService` writes `<id><ext>`, `BackupService` one file per
  /// backup), and a recursive walk would slow as the app accumulates data.
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
