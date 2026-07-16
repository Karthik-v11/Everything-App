import 'dart:io';

import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Drives the real [AppDatabase.encrypted] open path against real files.
///
/// SQLCipher is present here because `flutter test` honours the `hooks`
/// `user_defines` block in `pubspec.yaml`, the same one that keys the shipped
/// app — so these exercise the actual encryption, not a stand-in.
void main() {
  late Directory directory;

  String fileIn(Directory directory) =>
      '${directory.path}/$kDatabaseName.sqlite';

  setUp(() => directory = Directory.systemTemp.createTempSync('db_recovery'));
  tearDown(() => directory.deleteSync(recursive: true));

  const keyA = 'aaaa1111bbbb2222cccc3333dddd4444';
  const keyB = 'ffff9999eeee8888dddd7777cccc6666';

  AppDatabase openWith(String key) => AppDatabase.encrypted(
        encryptionKey: key,
        databaseDirectory: directory.path,
        temporaryDirectory: directory.path,
      );

  Future<int> countTasksWith(String key) async {
    final database = openWith(key);
    final tasks = await database.select(database.tasksTable).get();
    await database.close();
    return tasks.length;
  }

  Future<void> writeTaskWith(String key) async {
    final database = openWith(key);
    final now = DateTime.now();
    await database.into(database.tasksTable).insert(
          Task(id: 'id', title: 'Survivor', createdAt: now, updatedAt: now)
              .toCompanion(),
        );
    await database.close();
  }

  test('a correctly keyed database opens and keeps its rows', () async {
    await writeTaskWith(keyA);

    expect(await countTasksWith(keyA), 1, reason: 'data must survive a reopen');
  });

  test('a plaintext database from a pre-encryption build is replaced', () async {
    // The reported failure: a file no key of ours ever wrote.
    sqlite3.open(fileIn(directory))
      ..execute('CREATE TABLE legacy (id TEXT)')
      ..close();

    expect(await countTasksWith(keyA), 0, reason: 'a fresh database opens');
    expect(File(fileIn(directory)).existsSync(), isTrue, reason: 'recreated');
  });

  test('a database written with a lost key is replaced', () async {
    await writeTaskWith(keyA);

    expect(await countTasksWith(keyB), 0, reason: 'keyB cannot read keyA rows');
  });

  test('the -wal and -shm sidecars of a discarded file go with it', () async {
    sqlite3.open(fileIn(directory))
      ..execute('CREATE TABLE legacy (id TEXT)')
      ..close();
    File('${fileIn(directory)}-wal').writeAsStringSync('stale journal');
    File('${fileIn(directory)}-shm').writeAsStringSync('stale shared memory');

    await countTasksWith(keyA);

    final wal = File('${fileIn(directory)}-wal');
    expect(
      !wal.existsSync() || wal.readAsStringSync() != 'stale journal',
      isTrue,
      reason: 'the discarded database\'s journal must not survive',
    );
  });

  test('a first launch has no file to probe', () async {
    expect(File(fileIn(directory)).existsSync(), isFalse);

    expect(await countTasksWith(keyA), 0);
  });
}
