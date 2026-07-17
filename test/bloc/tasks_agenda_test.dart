import 'package:clock/clock.dart';
import 'package:everything_app/bloc/tasks/tasks_bloc.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Dashboard agenda's two derived figures (design.md §6.3, §6.5, §11).
///
/// These clear CLAUDE.md §17's bar because both are pure and both can be
/// confidently wrong in a way the screen would not reveal: `overdueCount` sits
/// directly above rows that state their own due status, so an off-by-one
/// definition puts a number on screen that the list beneath it contradicts.
///
/// Every case runs under a fixed clock — 15 July 2026, 12:00 — because both
/// getters read `clock.now()` and "is 09:00 today overdue?" is exactly the
/// question at issue.
void main() {
  final now = DateTime(2026, 7, 15, 12);

  Task task({
    required String id,
    DateTime? due,
    TaskStatus status = TaskStatus.pending,
  }) =>
      Task(
        id: id,
        title: 'Task $id',
        createdAt: now,
        updatedAt: now,
        dueDate: due,
        status: status,
      );

  TasksState stateWith(List<Task> tasks) =>
      TasksState(selectedDate: now, tasks: tasks);

  T at<T>(T Function() body) => withClock(Clock.fixed(now), body);

  group('TasksState.overdueCount', () {
    test('a task due at 09:00 today is not overdue at noon', () {
      // Per-day, matching dateGroups. The row beneath it reads "Due Today", so a
      // count that called it overdue would be arguing with its own list.
      final state = stateWith([
        task(id: '1', due: DateTime(2026, 7, 15, 9)),
      ]);

      expect(at(() => state.overdueCount), 0);
    });

    test('a task due yesterday is overdue', () {
      final state = stateWith([
        task(id: '1', due: DateTime(2026, 7, 14, 23, 59)),
      ]);

      expect(at(() => state.overdueCount), 1);
    });

    test('completed and undated tasks are never overdue', () {
      final state = stateWith([
        task(id: '1', due: DateTime(2026, 7, 1), status: TaskStatus.completed),
        task(id: '2'),
      ]);

      expect(at(() => state.overdueCount), 0);
    });

    test('the subline agrees with the rows: overdue is a subset of today', () {
      // design.md §6.3: "3 Overdue · 7 tasks today" means seven in total, three
      // of them late — not ten.
      final state = stateWith([
        task(id: '1', due: DateTime(2026, 7, 13)),
        task(id: '2', due: DateTime(2026, 7, 14)),
        task(id: '3', due: DateTime(2026, 7, 15, 9)),
        task(id: '4', due: DateTime(2026, 7, 15, 18)),
      ]);

      final overdue = at(() => state.overdueCount);
      final total = at(() => state.todayTasks.length);

      expect(overdue, 2);
      expect(total, 4);
      expect(overdue, lessThanOrEqualTo(total));
    });
  });

  group('TasksState.nextUpcoming', () {
    test('is the earliest task still ahead of the clock today', () {
      final state = stateWith([
        task(id: 'later', due: DateTime(2026, 7, 15, 18)),
        task(id: 'soon', due: DateTime(2026, 7, 15, 13)),
      ]);

      expect(at(() => state.nextUpcoming)?.id, 'soon');
    });

    test('a task whose moment has passed is not upcoming', () {
      // Per-minute here, unlike overdueCount — the panel counts down, and there
      // is nothing to count down to.
      final state = stateWith([
        task(id: '1', due: DateTime(2026, 7, 15, 9)),
      ]);

      expect(at(() => state.nextUpcoming), isNull);
    });

    test('ignores completed tasks', () {
      final state = stateWith([
        task(
          id: 'done',
          due: DateTime(2026, 7, 15, 13),
          status: TaskStatus.completed,
        ),
        task(id: 'open', due: DateTime(2026, 7, 15, 17)),
      ]);

      expect(at(() => state.nextUpcoming)?.id, 'open');
    });

    test('ignores undated tasks and tomorrow\'s', () {
      final state = stateWith([
        task(id: 'undated'),
        task(id: 'tomorrow', due: DateTime(2026, 7, 16, 9)),
      ]);

      expect(at(() => state.nextUpcoming), isNull);
    });

    test('an empty day yields null, which the panel renders as its own state', () {
      expect(at(() => stateWith(const []).nextUpcoming), isNull);
    });
  });
}
