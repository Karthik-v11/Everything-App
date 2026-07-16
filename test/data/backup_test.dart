import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/services/backup_service.dart';
import 'package:everything_app/data/services/security_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

/// Property 10 — a backup round-trips exactly, and any tampering is caught before
/// the live database is touched (Requirement 22.6).
///
/// The envelope is tested against its **bytes**: a round-trip test alone would
/// pass against an implementation that skipped the integrity tag entirely, which
/// is the failure this layer exists to prevent. So every group below flips a byte
/// and asserts the open *fails* — the tag is only doing its job if a changed
/// ciphertext, IV or MAC is rejected.
void main() {
  final encKey = Key(Uint8List.fromList(List.generate(32, (i) => i)));
  final macKey = List.generate(32, (i) => 255 - i);

  group('envelope integrity (Property 10)', () {
    final payload =
        Uint8List.fromList(List.generate(500, (i) => (i * 7) % 256));

    test('seal then open returns the original bytes', () {
      final sealed = BackupService.seal(payload, encKey: encKey, macKey: macKey);
      final opened = BackupService.open(sealed, encKey: encKey, macKey: macKey);

      expect(opened.success, isTrue);
      expect(opened.data, equals(payload));
    });

    test('a flipped ciphertext byte fails the integrity check', () {
      final sealed = BackupService.seal(payload, encKey: encKey, macKey: macKey);
      // The ciphertext starts after the 4-byte magic, 16-byte IV and 32-byte MAC.
      sealed[60] ^= 0x01;

      final opened = BackupService.open(sealed, encKey: encKey, macKey: macKey);
      expect(opened.success, isFalse);
      expect(opened.message.toLowerCase(), contains('tampered'));
    });

    test('a flipped MAC byte fails the integrity check', () {
      final sealed = BackupService.seal(payload, encKey: encKey, macKey: macKey);
      sealed[25] ^= 0x01; // Inside the 32-byte MAC region (offset 20..52).

      expect(
        BackupService.open(sealed, encKey: encKey, macKey: macKey).success,
        isFalse,
      );
    });

    test('a flipped IV byte fails the integrity check', () {
      final sealed = BackupService.seal(payload, encKey: encKey, macKey: macKey);
      sealed[6] ^= 0x01; // Inside the 16-byte IV region (offset 4..20).

      expect(
        BackupService.open(sealed, encKey: encKey, macKey: macKey).success,
        isFalse,
      );
    });

    test('the wrong MAC key is rejected without decrypting', () {
      final sealed = BackupService.seal(payload, encKey: encKey, macKey: macKey);
      final wrongMac = List.generate(32, (i) => i);

      expect(
        BackupService.open(sealed, encKey: encKey, macKey: wrongMac).success,
        isFalse,
      );
    });

    test('a truncated or unrecognised file is refused', () {
      expect(
        BackupService.open(
          Uint8List.fromList([1, 2, 3]),
          encKey: encKey,
          macKey: macKey,
        ).success,
        isFalse,
      );

      final notOurs = Uint8List.fromList(List.filled(100, 0));
      expect(
        BackupService.open(notOurs, encKey: encKey, macKey: macKey).success,
        isFalse,
      );
    });
  });

  group('database round-trip and tamper abort (Property 10)', () {
    late AppDatabase database;
    late BackupService service;
    late Directory tempDir;

    setUp(() async {
      database = AppDatabase.memory();
      tempDir = await Directory.systemTemp.createTemp('backup_test');
      service = BackupService(
        database: database,
        security: SecurityService(
          storage: _FakeStorage(),
          localAuth: LocalAuthentication(),
        ),
        backupsDirectoryOverride: tempDir.path,
      );
    });

    tearDown(() async {
      await database.close();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<void> insertTask(String id, String title) => database.customStatement(
          'INSERT INTO tasks (id, title, created_at, updated_at) '
          'VALUES (?, ?, ?, ?)',
          [id, title, 1000, 1000],
        );

    Future<Set<String>> taskIds() async {
      final rows = await database.customSelect('SELECT id FROM tasks').get();
      return rows.map((r) => r.data['id'] as String).toSet();
    }

    test('restore replaces the database with the backed-up state', () async {
      await insertTask('a', 'Task A');

      final created = await service.createBackup();
      expect(created.success, isTrue);

      // Diverge from the snapshot: drop A, add B.
      await database.customStatement("DELETE FROM tasks WHERE id = 'a'");
      await insertTask('b', 'Task B');
      expect(await taskIds(), equals({'b'}));

      final backups = await service.listBackups();
      final path = (backups.data! as List).first.path as String;

      final restored = await service.restoreFromFile(path);
      expect(restored.success, isTrue);
      // Back to exactly the snapshot: A present, B gone.
      expect(await taskIds(), equals({'a'}));
    });

    test('a tampered backup aborts and leaves the live data untouched', () async {
      await insertTask('a', 'Task A');
      final created = await service.createBackup();
      final path = (created.data! as dynamic).path as String;

      // The live database moves on after the backup was taken.
      await insertTask('b', 'Task B');

      // Corrupt a byte deep in the ciphertext of the stored backup.
      final file = File(path);
      final bytes = await file.readAsBytes();
      bytes[bytes.length - 1] ^= 0x01;
      await file.writeAsBytes(bytes, flush: true);

      final restored = await service.restoreFromFile(path);
      expect(restored.success, isFalse);
      // Nothing was rolled back to, because nothing was touched.
      expect(await taskIds(), equals({'a', 'b'}));
    });
  });
}

/// [_FakeStorage] is an in-memory keychain, so the backup keys can be generated
/// and re-read without the platform channel.
class _FakeStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
