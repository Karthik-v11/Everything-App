import 'dart:math';

import 'package:drift/drift.dart' show Variable;
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/database/daos/tasks_dao.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/data/repositories/tasks_repository.dart';
import 'package:everything_app/data/services/tasks_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task create — the < 200 ms bar over a populated table (Requirement 24.2,
/// Phase 14).
///
/// Benchmarked rather than assumed, on the same reasoning as the search bar in
/// `search_test.dart`: an insert into `tasks` fires the `search_ai_tasks` FTS5
/// trigger and touches two indexes, and none of that cost is visible by reading
/// the write path. A regression here — an added trigger, an index dropped, a
/// widened companion — is silent until it is measured.
///
/// **What this bounds, and what it does not.** The plan's 200 ms is a
/// *user-perceived* budget: tap to the task appearing on screen, which on a real
/// device also includes the bloc rebuild and the frames to render it. This runs
/// on the host against `NativeDatabase.memory()`, so it measures only the
/// database portion of that budget — repository → service → DAO → SQLite. It is
/// the part that can regress silently in CI, and it is a floor, not the bar: an
/// unencrypted in-memory DB is faster than SQLCipher on flash, and a passing run
/// here does not clear the on-device budget. Device timing needs a device.
void main() {
  late AppDatabase database;
  late TasksRepository repository;

  // A fixed timestamp for the seed rows: create timing does not read them.
  const stamp = 1700000000;

  Future<void> insertTask(String id, String title, String notes) =>
      database.customInsert(
        'INSERT INTO tasks (id, title, notes, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?)',
        variables: [
          Variable<String>(id),
          Variable<String>(title),
          Variable<String>(notes),
          const Variable<int>(stamp),
          const Variable<int>(stamp),
        ],
      );

  setUp(() {
    database = AppDatabase.memory();
    repository = TasksRepositoryImpl(
      tasksService: TasksService(dao: TasksDao(database)),
    );
  });

  tearDown(() => database.close());

  group('Requirement 24.2 — a task create stays under 200 ms over 10,000 tasks',
      () {
    test('a create against a seeded 10k table lands within the budget',
        () async {
      final random = Random(14);
      const words = [
        'alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf',
        'hotel', 'india', 'juliet', 'report', 'invoice', 'meeting', 'travel',
        'grocery', 'project', 'design', 'review', 'budget', 'holiday',
      ];

      String phrase() => List.generate(
            3,
            (_) => words[random.nextInt(words.length)],
          ).join(' ');

      // The write is measured against a populated table and its indexes, not an
      // empty one. Seeded in one transaction so the FTS triggers fire per row
      // but the seed itself stays fast.
      await database.transaction(() async {
        for (var i = 0; i < 10000; i++) {
          await insertTask('seed-$i', 'Task ${phrase()}', phrase());
        }
      });

      // The seed rows reached the FTS index, so the triggers are live on this
      // connection: `beforeOpen` installed them and nothing here bypassed them.
      final seeded = await database
          .customSelect('SELECT count(*) AS c FROM search_index')
          .getSingle();
      expect(seeded.read<int>('c'), 10000);

      Task taskNamed(String id) => Task(
            id: id,
            title: 'Create $id ${phrase()}',
            notes: phrase(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );

      // Warm up once — the first insert compiles the statement — then measure.
      await repository.create(taskNamed('warmup'));

      for (var i = 0; i < 5; i++) {
        final watch = Stopwatch()..start();
        final response = await repository.create(taskNamed('bench-$i'));
        watch.stop();

        expect(response.success, isTrue);
        expect(
          watch.elapsedMilliseconds,
          lessThan(200),
          reason: 'create #$i took ${watch.elapsedMilliseconds}ms',
        );
      }

      // Each measured create carried its row through the trigger into the FTS
      // index. Without this the benchmark could pass while measuring a write
      // that never paid the trigger cost.
      final after = await database
          .customSelect('SELECT count(*) AS c FROM search_index')
          .getSingle();
      expect(
        after.read<int>('c'),
        10006,
        reason: 'the FTS trigger did not fire for every measured create',
      );
    });
  });
}
