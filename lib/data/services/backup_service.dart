import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/models/backup_metadata.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/services/security_service.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// [BackupService] exports and restores the whole database as a single encrypted,
/// integrity-tagged file (Requirement 22).
///
/// **The format is encrypt-then-MAC.** The database is serialised to JSON,
/// gzipped, encrypted with AES-256-CBC, and then an HMAC-SHA256 tag is computed
/// over the ciphertext. Restore verifies the tag **before it decrypts anything and
/// long before it touches the live database** — a damaged or tampered backup is
/// rejected with the on-device data left exactly as it was (Requirement 22.6). A
/// round-trip that decrypted first and validated later would already have spent
/// the attacker's malleability by the time it noticed.
///
/// Like every other service it returns [JsonResponse] and never throws.
///
/// The seal/open pair is static and pure so the integrity guarantee can be tested
/// against the bytes directly (Property 10), with no database in the picture.
class BackupService {
  BackupService({
    required this.database,
    required this.security,
    this.backupsDirectoryOverride,
  });

  final AppDatabase database;
  final SecurityService security;

  /// An explicit directory for the backup files, so a test can point them at a
  /// temporary location. Production resolves the app documents directory.
  final String? backupsDirectoryOverride;

  /// [_magic] tags the envelope so a file that is not one of ours — or a truncated
  /// one — is refused before any crypto runs.
  static const String _magic = 'EVB1';
  static const String _extension = '.evbak';

  static const int _ivLength = 16; // AES-CBC block size.
  static const int _macLength = 32; // HMAC-SHA256 output.
  static const int _headerLength = 4 + _ivLength + _macLength;

  // ── Create (Requirement 22.1) ──────────────────────────────────────────────

  /// [createBackup] snapshots the database and writes one encrypted file.
  Future<JsonResponse> createBackup() async {
    final keys = await security.backupKeys();
    if (!keys.success) return keys;
    final (:encKey, :macKey) = _keysOf(keys);

    try {
      final snapshot = await _exportSnapshot();
      final compressed = gzip.encode(utf8.encode(jsonEncode(snapshot)));
      final envelope = seal(
        Uint8List.fromList(compressed),
        encKey: encKey,
        macKey: macKey,
      );

      final directory = await _resolveDirectory();
      final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
      final file = File('${directory.path}/everything-$stamp$_extension');
      await file.writeAsBytes(envelope, flush: true);

      final stat = await file.stat();
      return JsonResponse.created(
        message: 'Backup created.',
        data: BackupMetadata(
          path: file.path,
          createdAt: stat.modified,
          sizeBytes: stat.size,
        ),
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not create the backup.',
      );
    }
  }

  // ── Restore (Requirement 22.6) ─────────────────────────────────────────────

  /// [restoreFromFile] reads a backup file and applies it.
  Future<JsonResponse> restoreFromFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return JsonResponse.failure(
          statusCode: 404,
          message: 'That backup no longer exists.',
        );
      }
      return restoreFromBytes(await file.readAsBytes());
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not read the backup file.',
      );
    }
  }

  /// [restoreFromBytes] verifies, decrypts and applies an envelope.
  ///
  /// The order is the whole point: [open] checks the HMAC first and returns a
  /// failure on any mismatch, so a tampered backup never reaches [_importSnapshot]
  /// and the live database is untouched (Requirement 22.6). The import itself runs
  /// in a single transaction, so even a valid-but-malformed payload that fails
  /// halfway rolls back rather than leaving a half-restored database.
  Future<JsonResponse> restoreFromBytes(Uint8List bytes) async {
    final keys = await security.backupKeys();
    if (!keys.success) return keys;
    final (:encKey, :macKey) = _keysOf(keys);

    final opened = open(bytes, encKey: encKey, macKey: macKey);
    if (!opened.success) return opened;

    try {
      final json = utf8.decode(gzip.decode(opened.data! as Uint8List));
      final snapshot = jsonDecode(json) as Map<String, dynamic>;
      await _importSnapshot(snapshot);
      return JsonResponse.success(message: 'Restore complete.');
    } on Exception {
      // Reached only after a valid HMAC, so the file was ours but its contents do
      // not fit this schema. The transaction has already rolled back.
      return JsonResponse.failure(
        statusCode: 422,
        message: 'The backup was valid but could not be applied.',
      );
    }
  }

  // ── Manage the local backup set ────────────────────────────────────────────

  /// [listBackups] returns the on-device backups, newest first.
  Future<JsonResponse> listBackups() async {
    try {
      final directory = await _resolveDirectory();
      final entries = await directory
          .list()
          .where((e) => e is File && e.path.endsWith(_extension))
          .toList();

      final backups = <BackupMetadata>[];
      for (final entry in entries) {
        final stat = await entry.stat();
        backups.add(
          BackupMetadata(
            path: entry.path,
            createdAt: stat.modified,
            sizeBytes: stat.size,
          ),
        );
      }
      backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return JsonResponse.success(message: 'Loaded.', data: backups);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not list the backups.',
      );
    }
  }

  Future<JsonResponse> deleteBackup(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
      return JsonResponse.success(message: 'Backup deleted.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not delete the backup.',
      );
    }
  }

  // ── The sealed envelope (pure, tested directly — Property 10) ───────────────

  /// [seal] wraps [plaintext] as `magic ‖ iv ‖ hmac ‖ ciphertext`.
  ///
  /// The MAC covers the magic, the IV and the ciphertext — everything an attacker
  /// could otherwise alter without detection.
  static Uint8List seal(
    Uint8List plaintext, {
    required Key encKey,
    required List<int> macKey,
  }) {
    final iv = IV(_randomBytes(_ivLength));
    final encrypter = Encrypter(AES(encKey, mode: AESMode.cbc));
    final ciphertext = encrypter.encryptBytes(plaintext, iv: iv).bytes;

    final header = utf8.encode(_magic);
    final mac = Hmac(sha256, macKey)
        .convert([...header, ...iv.bytes, ...ciphertext])
        .bytes;

    return Uint8List.fromList([
      ...header,
      ...iv.bytes,
      ...mac,
      ...ciphertext,
    ]);
  }

  /// [open] verifies the HMAC and only then decrypts (Requirement 22.6).
  ///
  /// Returns a failure — never a throw, never a partial result — on a bad magic, a
  /// short file, or a MAC that does not verify. [JsonResponse.data] on success is
  /// the decrypted [Uint8List].
  static JsonResponse open(
    Uint8List envelope, {
    required Key encKey,
    required List<int> macKey,
  }) {
    try {
      if (envelope.length < _headerLength) {
        return JsonResponse.failure(
          statusCode: 422,
          message: 'This is not a valid backup file.',
        );
      }

      final header = envelope.sublist(0, 4);
      if (!_constantTimeEquals(header, utf8.encode(_magic))) {
        return JsonResponse.failure(
          statusCode: 422,
          message: 'This is not a valid backup file.',
        );
      }

      final iv = envelope.sublist(4, 4 + _ivLength);
      final mac = envelope.sublist(4 + _ivLength, _headerLength);
      final ciphertext = envelope.sublist(_headerLength);

      final expected = Hmac(sha256, macKey)
          .convert([...header, ...iv, ...ciphertext])
          .bytes;
      if (!_constantTimeEquals(mac, expected)) {
        return JsonResponse.failure(
          statusCode: 422,
          message: 'This backup is damaged or has been tampered with. '
              'Nothing was changed.',
        );
      }

      final encrypter = Encrypter(AES(encKey, mode: AESMode.cbc));
      final plaintext = encrypter.decryptBytes(
        Encrypted(Uint8List.fromList(ciphertext)),
        iv: IV(Uint8List.fromList(iv)),
      );

      return JsonResponse.success(
        message: 'Verified.',
        data: Uint8List.fromList(plaintext),
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 422,
        message: 'This backup could not be read.',
      );
    }
  }

  // ── Database snapshot ──────────────────────────────────────────────────────

  /// [_exportSnapshot] reads every drift table into a plain JSON structure.
  ///
  /// Iterating [AppDatabase.allTables] keeps this independent of the schema: a
  /// table added in a later phase is exported with no change here. Every column is
  /// stored as an `int`/`double`/`String`/`null` (money is minor units, dates are
  /// unix seconds, enums are their name), so the raw row map is already
  /// JSON-encodable with no per-type handling. The FTS index and its shadow tables
  /// are not drift tables, so they are correctly excluded — restore rebuilds them
  /// through the triggers.
  Future<Map<String, dynamic>> _exportSnapshot() async {
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final table in database.allTables) {
      final rows = await database
          .customSelect('SELECT * FROM ${table.actualTableName}')
          .get();
      tables[table.actualTableName] = rows.map((row) => row.data).toList();
    }

    return {
      'app': 'everything',
      'formatVersion': 1,
      'schemaVersion': database.schemaVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'tables': tables,
    };
  }

  /// [_importSnapshot] replaces the database contents with the snapshot, atomically.
  ///
  /// Foreign keys are deferred to commit time rather than switched off: the whole
  /// replacement still has to be referentially consistent, but the delete-then-fill
  /// order no longer has to be topologically sorted. Every write is inside one
  /// [AppDatabase.transaction], so any failure rolls the database back to where it
  /// started. The reconciling FTS triggers fire per row and leave the search index
  /// consistent with the restored data, so no rebuild is needed; drift's stream
  /// queries are notified once at the end so every open screen re-reads.
  Future<void> _importSnapshot(Map<String, dynamic> snapshot) async {
    final tables = (snapshot['tables'] as Map).cast<String, dynamic>();
    final ordered = database.allTables.toList();

    await database.transaction(() async {
      await database.customStatement('PRAGMA defer_foreign_keys = ON');

      for (final table in ordered) {
        await database.customStatement('DELETE FROM ${table.actualTableName}');
      }

      for (final table in ordered) {
        final rows = (tables[table.actualTableName] as List?) ?? const [];
        for (final row in rows) {
          final map = (row as Map).cast<String, Object?>();
          final columns = map.keys.toList();
          if (columns.isEmpty) continue;

          final placeholders = List.filled(columns.length, '?').join(', ');
          await database.customStatement(
            'INSERT INTO ${table.actualTableName} '
            '(${columns.join(', ')}) VALUES ($placeholders)',
            [for (final column in columns) map[column]],
          );
        }
      }
    });

    database.markTablesUpdated(ordered);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<Directory> _resolveDirectory() async {
    final base =
        backupsDirectoryOverride ?? (await getApplicationDocumentsDirectory()).path;
    final directory = Directory('$base/backups');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  ({Key encKey, List<int> macKey}) _keysOf(JsonResponse response) =>
      response.data! as ({Key encKey, List<int> macKey});

  static final Random _random = Random.secure();

  static Uint8List _randomBytes(int length) => Uint8List.fromList(
        List<int>.generate(length, (_) => _random.nextInt(256)),
      );

  /// [_constantTimeEquals] compares without short-circuiting, so a MAC check does
  /// not leak how many leading bytes matched.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
