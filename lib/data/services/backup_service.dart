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
// `show compute`: an unrestricted import collides with encrypt's `Key`.
import 'package:flutter/foundation.dart' show compute;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// [BackupService] exports and restores the whole database as a single encrypted,
/// integrity-tagged file (Requirement 22).
///
/// Encrypt-then-MAC: JSON, gzipped, AES-256-CBC, then HMAC-SHA256 over the
/// ciphertext. Restore verifies the tag before decrypting anything and long
/// before touching the live database, so a damaged or tampered backup is rejected
/// with on-device data untouched (Requirement 22.6). Decrypt-then-validate would
/// already have spent the attacker's malleability by the time it noticed.
///
/// The keys come from the user's backup PIN, not from this install: `EVB2` carries
/// the PBKDF2 salt and work factor it was sealed with, so the keys are a pure
/// function of the PIN and the file's own bytes, and the backup restores on a
/// reinstall or an unrelated phone. The earlier `EVB1` keyed off a random master
/// in secure storage, which the OS wipes on uninstall or "clear data" — those
/// backups failed their MAC and reported tampering when the file was intact and
/// the key merely gone. [openLegacy] still reads them while that master survives;
/// everything new is written as `EVB2`.
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

  /// Tags the envelope so a foreign or truncated file is refused before any crypto
  /// runs. [_legacyMagic] is the pre-portable format: still read, never written.
  static const String _magic = 'EVB2';
  static const String _legacyMagic = 'EVB1';
  static const String _extension = '.evbak';

  static const int _saltLength = 16;
  static const int _ivLength = 16; // AES-CBC block size.
  static const int _macLength = 32; // HMAC-SHA256 output.

  /// `magic ‖ iterations ‖ salt ‖ iv ‖ mac`.
  static const int _headerLength = 4 + 4 + _saltLength + _ivLength + _macLength;
  static const int _legacyHeaderLength = 4 + _ivLength + _macLength;

  // ── Create (Requirement 22.1) ──────────────────────────────────────────────

  /// Snapshots the database and writes one encrypted file, sealed with [pin].
  Future<JsonResponse> createBackup({required String pin}) async {
    final salt = security.backupSalt();
    const iterations = SecurityService.kBackupPBKDF2Iterations;

    final keys = await SecurityService.backupKeysFor(
      pin: pin,
      salt: salt,
      iterations: iterations,
    );
    if (!keys.success) return keys;
    final (:encKey, :macKey) = _keysOf(keys);

    try {
      final snapshot = await _exportSnapshot();
      // Compress and seal off the UI isolate: this serialises and encrypts the
      // whole database, which is seconds of frozen UI on a large one.
      final envelope = await compute(
        _compressAndSeal,
        (
          snapshot: snapshot,
          encKeyBytes: Uint8List.fromList(encKey.bytes),
          macKey: Uint8List.fromList(macKey),
          salt: salt,
          iterations: iterations,
        ),
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

  /// Reads a backup file and applies it, unsealing with [pin].
  Future<JsonResponse> restoreFromFile(String path, {required String pin}) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return JsonResponse.failure(
          statusCode: 404,
          message: 'That backup no longer exists.',
        );
      }
      return restoreFromBytes(await file.readAsBytes(), pin: pin);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not read the backup file.',
      );
    }
  }

  /// Verifies, decrypts and applies an envelope — in that order. [open] checks the
  /// HMAC first and fails on any mismatch, so a tampered backup never reaches
  /// [_importSnapshot] and the live database is untouched (Requirement 22.6). The
  /// import runs in one transaction, so a valid-but-malformed payload that fails
  /// halfway rolls back rather than leaving a half-restored database.
  Future<JsonResponse> restoreFromBytes(
    Uint8List bytes, {
    required String pin,
  }) async {
    final opened =
        _isLegacy(bytes) ? await _openLegacy(bytes) : await open(bytes, pin: pin);
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

  /// Returns the on-device backups, newest first.
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

  /// `compute` entry point for [createBackup]: it takes exactly one argument.
  static Uint8List _compressAndSeal(
    ({
      Map<String, dynamic> snapshot,
      Uint8List encKeyBytes,
      Uint8List macKey,
      Uint8List salt,
      int iterations,
    }) args,
  ) =>
      seal(
        Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(args.snapshot)))),
        encKey: Key(args.encKeyBytes),
        macKey: args.macKey,
        salt: args.salt,
        iterations: args.iterations,
      );

  // ── The sealed envelope (pure, tested directly — Property 10) ───────────────

  /// Wraps [plaintext] as `magic ‖ iterations ‖ salt ‖ iv ‖ hmac ‖ ciphertext`.
  ///
  /// The MAC covers the salt and work factor as well as the magic, IV and
  /// ciphertext: unauthenticated KDF parameters would let someone rewrite the
  /// iteration count to 1 and hand the file back for the user's own device to
  /// unseal cheaply.
  static Uint8List seal(
    Uint8List plaintext, {
    required Key encKey,
    required List<int> macKey,
    required Uint8List salt,
    required int iterations,
  }) {
    final iv = IV(_randomBytes(_ivLength));
    final encrypter = Encrypter(AES(encKey, mode: AESMode.cbc));
    final ciphertext = encrypter.encryptBytes(plaintext, iv: iv).bytes;

    final header = <int>[
      ...utf8.encode(_magic),
      ..._uint32(iterations),
      ...salt,
    ];
    final mac = Hmac(sha256, macKey).convert([...header, ...iv.bytes, ...ciphertext]).bytes;

    return Uint8List.fromList([...header, ...iv.bytes, ...mac, ...ciphertext]);
  }

  /// Derives the keys from [pin] and the file's own header, verifies the HMAC, and
  /// only then decrypts (Requirement 22.6). A wrong PIN is indistinguishable from
  /// a corrupt file at the MAC, so the message names the likelier cause first;
  /// offline PIN guessing is what [SecurityService.kBackupPBKDF2Iterations] is
  /// priced against.
  ///
  /// Fails — never throws, never partially succeeds — on a bad magic, a short
  /// file, or a MAC that does not verify. [JsonResponse.data] on success is the
  /// decrypted [Uint8List].
  static Future<JsonResponse> open(
    Uint8List envelope, {
    required String pin,
  }) async {
    try {
      if (envelope.length < _headerLength) {
        return JsonResponse.failure(
          statusCode: 422,
          message: 'This is not a valid backup file.',
        );
      }

      final header = envelope.sublist(0, 4 + 4 + _saltLength);
      if (!_constantTimeEquals(header.sublist(0, 4), utf8.encode(_magic))) {
        return JsonResponse.failure(
          statusCode: 422,
          message: 'This is not a valid backup file.',
        );
      }

      final iterations = ByteData.sublistView(envelope, 4, 8).getUint32(0);
      if (iterations <= 0) {
        return JsonResponse.failure(
          statusCode: 422,
          message: 'This is not a valid backup file.',
        );
      }

      final salt = envelope.sublist(8, 8 + _saltLength);
      final keys = await SecurityService.backupKeysFor(
        pin: pin,
        salt: salt,
        iterations: iterations,
      );
      if (!keys.success) return keys;
      final (:encKey, :macKey) = keys.data! as ({Key encKey, List<int> macKey});

      final ivStart = 4 + 4 + _saltLength;
      final iv = envelope.sublist(ivStart, ivStart + _ivLength);
      final mac = envelope.sublist(ivStart + _ivLength, _headerLength);
      final ciphertext = envelope.sublist(_headerLength);

      final expected =
          Hmac(sha256, macKey).convert([...header, ...iv, ...ciphertext]).bytes;
      if (!_constantTimeEquals(mac, expected)) {
        return JsonResponse.failure(
          statusCode: 401,
          message: 'Wrong PIN, or this backup is damaged. Nothing was changed.',
        );
      }

      return _decrypt(encKey: encKey, iv: iv, ciphertext: ciphertext);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 422,
        message: 'This backup could not be read.',
      );
    }
  }

  /// True for an `EVB1` file — one sealed before backups were keyed by the PIN.
  static bool _isLegacy(Uint8List envelope) =>
      envelope.length >= 4 &&
      _constantTimeEquals(envelope.sublist(0, 4), utf8.encode(_legacyMagic));

  /// Opens an `EVB1` file with the install's stored master key: this device only,
  /// and only until the master is wiped. Kept so a long-running install can read
  /// its own history; nothing writes this format.
  Future<JsonResponse> _openLegacy(Uint8List envelope) async {
    final keys = await security.backupKeys();
    if (!keys.success) return keys;
    final (:encKey, :macKey) = _keysOf(keys);

    try {
      if (envelope.length < _legacyHeaderLength) {
        return JsonResponse.failure(
          statusCode: 422,
          message: 'This is not a valid backup file.',
        );
      }

      final header = envelope.sublist(0, 4);
      final iv = envelope.sublist(4, 4 + _ivLength);
      final mac = envelope.sublist(4 + _ivLength, _legacyHeaderLength);
      final ciphertext = envelope.sublist(_legacyHeaderLength);

      final expected =
          Hmac(sha256, macKey).convert([...header, ...iv, ...ciphertext]).bytes;
      if (!_constantTimeEquals(mac, expected)) {
        return JsonResponse.failure(
          statusCode: 422,
          message: 'This backup was made by an older version and can only be '
              'restored on the device that created it. Nothing was changed.',
        );
      }

      return _decrypt(encKey: encKey, iv: iv, ciphertext: ciphertext);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 422,
        message: 'This backup could not be read.',
      );
    }
  }

  /// The tail both formats share, reached only after a verified MAC.
  static JsonResponse _decrypt({
    required Key encKey,
    required List<int> iv,
    required List<int> ciphertext,
  }) {
    final encrypter = Encrypter(AES(encKey, mode: AESMode.cbc));
    final plaintext = encrypter.decryptBytes(
      Encrypted(Uint8List.fromList(ciphertext)),
      iv: IV(Uint8List.fromList(iv)),
    );
    return JsonResponse.success(
      message: 'Verified.',
      data: Uint8List.fromList(plaintext),
    );
  }

  static Uint8List _uint32(int value) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.big);

  // ── Database snapshot ──────────────────────────────────────────────────────

  /// Reads every drift table into a plain JSON structure.
  ///
  /// Iterating [AppDatabase.allTables] keeps this schema-independent: a new table
  /// is exported with no change here. Every column is an `int`/`double`/`String`/
  /// `null` (money in minor units, dates in unix seconds, enums by name), so the
  /// raw row map is already JSON-encodable. The FTS index and its shadow tables
  /// are not drift tables and so are correctly excluded — restore rebuilds them
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

  /// Replaces the database contents with the snapshot, atomically.
  ///
  /// Foreign keys are deferred to commit time rather than switched off: the
  /// replacement must still be referentially consistent, but the delete-then-fill
  /// order need not be topologically sorted. Every write is inside one
  /// [AppDatabase.transaction], so any failure rolls back. The FTS triggers fire
  /// per row and leave the index consistent, so no rebuild is needed; drift's
  /// stream queries are notified once at the end so open screens re-read.
  Future<void> _importSnapshot(Map<String, dynamic> snapshot) async {
    final tables = (snapshot['tables'] as Map).cast<String, dynamic>();
    final ordered = database.allTables.toList();

    await database.transaction(() async {
      await database.customStatement('PRAGMA defer_foreign_keys = ON');

      // One batch, not one statement per row. Every `await` on a statement is a
      // full marshal to drift's background isolate and back, so the previous
      // shape cost one round-trip per restored row — at the 10,000-item scale
      // Requirement 24.2 contemplates, 10,000 sequential hops inside a single
      // transaction. `batch` sends the whole restore in one hop, which is the
      // same reason the index creation in `AppDatabase.beforeOpen` is batched.
      await database.batch((b) {
        for (final table in ordered) {
          b.customStatement('DELETE FROM ${table.actualTableName}');
        }

        for (final table in ordered) {
          final rows = (tables[table.actualTableName] as List?) ?? const [];
          for (final row in rows) {
            final map = (row as Map).cast<String, Object?>();
            final columns = map.keys.toList();
            if (columns.isEmpty) continue;

            final placeholders = List.filled(columns.length, '?').join(', ');
            b.customStatement(
              'INSERT INTO ${table.actualTableName} '
              '(${columns.join(', ')}) VALUES ($placeholders)',
              [for (final column in columns) map[column]],
            );
          }
        }
      });
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

  /// Compares without short-circuiting, so a MAC check does not leak how many
  /// leading bytes matched.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
