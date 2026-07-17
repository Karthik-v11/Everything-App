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
  const pin = '135790';
  final salt = Uint8List.fromList(List.generate(16, (i) => i * 3));

  // A low work factor: these tests assert what the KDF is wired to, not how
  // expensive it is. Production uses [SecurityService.kBackupPBKDF2Iterations],
  // and the file carries whatever it was sealed with, so a cheap salt here opens
  // exactly the way a costly one does.
  const iterations = 1000;

  Future<Uint8List> sealWith(Uint8List payload, {String withPin = pin}) async {
    final keys = await SecurityService.backupKeysFor(
      pin: withPin,
      salt: salt,
      iterations: iterations,
    );
    final (:encKey, :macKey) = keys.data! as ({Key encKey, List<int> macKey});
    return BackupService.seal(
      payload,
      encKey: encKey,
      macKey: macKey,
      salt: salt,
      iterations: iterations,
    );
  }

  group('envelope integrity (Property 10)', () {
    final payload =
        Uint8List.fromList(List.generate(500, (i) => (i * 7) % 256));

    // magic(4) ‖ iterations(4) ‖ salt(16) ‖ iv(16) ‖ mac(32) = 72.
    const headerLength = 72;

    test('seal then open returns the original bytes', () async {
      final opened = await BackupService.open(await sealWith(payload), pin: pin);

      expect(opened.success, isTrue);
      expect(opened.data, equals(payload));
    });

    test('a flipped ciphertext byte fails the integrity check', () async {
      final sealed = await sealWith(payload);
      sealed[headerLength + 8] ^= 0x01;

      final opened = await BackupService.open(sealed, pin: pin);
      expect(opened.success, isFalse);
      expect(opened.message.toLowerCase(), contains('damaged'));
    });

    test('a flipped MAC byte fails the integrity check', () async {
      final sealed = await sealWith(payload);
      sealed[45] ^= 0x01; // Inside the MAC region (offset 40..72).

      expect((await BackupService.open(sealed, pin: pin)).success, isFalse);
    });

    test('a flipped IV byte fails the integrity check', () async {
      final sealed = await sealWith(payload);
      sealed[30] ^= 0x01; // Inside the IV region (offset 24..40).

      expect((await BackupService.open(sealed, pin: pin)).success, isFalse);
    });

    /// The KDF parameters are inside the MAC, so downgrading the work factor is
    /// caught like any other tamper. Unauthenticated, this would be the cheapest
    /// possible attack on the file: rewrite the count to 1 and let the owner's own
    /// device do the unsealing.
    test('a rewritten iteration count fails the integrity check', () async {
      final sealed = await sealWith(payload);
      ByteData.sublistView(sealed, 4, 8).setUint32(0, 1);

      expect((await BackupService.open(sealed, pin: pin)).success, isFalse);
    });

    test('a flipped salt byte fails the integrity check', () async {
      final sealed = await sealWith(payload);
      sealed[12] ^= 0x01; // Inside the salt region (offset 8..24).

      expect((await BackupService.open(sealed, pin: pin)).success, isFalse);
    });

    test('the wrong PIN is rejected without decrypting', () async {
      final opened =
          await BackupService.open(await sealWith(payload), pin: '999999');

      expect(opened.success, isFalse);
      expect(opened.message.toLowerCase(), contains('pin'));
    });

    /// The regression this format exists for: the PIN and the file are jointly
    /// sufficient. Nothing is read from secure storage, so there is no install
    /// state left to lose — a fresh phone opens this exactly as the one that
    /// sealed it did.
    test('a backup opens with only the PIN and the file', () async {
      final sealed = await sealWith(payload);
      final salvaged = Uint8List.fromList(sealed);

      expect((await BackupService.open(salvaged, pin: pin)).data, equals(payload));
    });

    test('two backups under the same PIN derive different keys', () {
      // Same PIN, different files: the salts differ, so cracking one reveals
      // nothing about the other.
      final security = SecurityService(
        storage: _FakeStorage(),
        localAuth: LocalAuthentication(),
      );
      expect(security.backupSalt(), isNot(equals(security.backupSalt())));
    });

    test('a truncated or unrecognised file is refused', () async {
      expect(
        (await BackupService.open(Uint8List.fromList([1, 2, 3]), pin: pin))
            .success,
        isFalse,
      );

      final notOurs = Uint8List.fromList(List.filled(100, 0));
      expect((await BackupService.open(notOurs, pin: pin)).success, isFalse);
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

      final created = await service.createBackup(pin: pin);
      expect(created.success, isTrue);

      // Diverge from the snapshot: drop A, add B.
      await database.customStatement("DELETE FROM tasks WHERE id = 'a'");
      await insertTask('b', 'Task B');
      expect(await taskIds(), equals({'b'}));

      final backups = await service.listBackups();
      final path = (backups.data! as List).first.path as String;

      final restored = await service.restoreFromFile(path, pin: pin);
      expect(restored.success, isTrue);
      // Back to exactly the snapshot: A present, B gone.
      expect(await taskIds(), equals({'a'}));
    });

    /// The bug this format replaced: the old envelope was keyed by a random master
    /// in secure storage, so wiping app data — or moving to a new phone — left an
    /// intact file that reported itself as tampered with. A second service over a
    /// **fresh database and empty keychain** is exactly that new install.
    test('a backup restores on an install that never held the old key', () async {
      await insertTask('a', 'Task A');
      final created = await service.createBackup(pin: pin);
      final path = (created.data! as dynamic).path as String;

      final freshDatabase = AppDatabase.memory();
      final freshInstall = BackupService(
        database: freshDatabase,
        security: SecurityService(
          storage: _FakeStorage(), // Empty: nothing carried over.
          localAuth: LocalAuthentication(),
        ),
        backupsDirectoryOverride: tempDir.path,
      );
      addTearDown(freshDatabase.close);

      final restored = await freshInstall.restoreFromFile(path, pin: pin);
      expect(restored.success, isTrue);

      final rows = await freshDatabase.customSelect('SELECT id FROM tasks').get();
      expect(rows.map((r) => r.data['id']).toSet(), equals({'a'}));
    });

    test('the wrong PIN leaves the live data untouched', () async {
      await insertTask('a', 'Task A');
      final created = await service.createBackup(pin: pin);
      final path = (created.data! as dynamic).path as String;

      await insertTask('b', 'Task B');

      final restored = await service.restoreFromFile(path, pin: '000000');
      expect(restored.success, isFalse);
      expect(await taskIds(), equals({'a', 'b'}));
    });

    test('a tampered backup aborts and leaves the live data untouched', () async {
      await insertTask('a', 'Task A');
      final created = await service.createBackup(pin: pin);
      final path = (created.data! as dynamic).path as String;

      // The live database moves on after the backup was taken.
      await insertTask('b', 'Task B');

      // Corrupt a byte deep in the ciphertext of the stored backup.
      final file = File(path);
      final bytes = await file.readAsBytes();
      bytes[bytes.length - 1] ^= 0x01;
      await file.writeAsBytes(bytes, flush: true);

      final restored = await service.restoreFromFile(path, pin: pin);
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
