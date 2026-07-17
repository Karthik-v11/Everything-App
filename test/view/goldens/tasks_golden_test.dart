import 'package:bloc_test/bloc_test.dart';
import 'package:everything_app/bloc/tasks/tasks_bloc.dart';
import 'package:everything_app/data/models/category.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/view/screens/tasks/tasks_page.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

/// The Tasks list is the app's densest derivation: one flat list of every open
/// task, split into Overdue / a section per day / No date, each sorted by urgency,
/// with a calendar strip bound to it and the priority and category markers of the
/// reference UI on every card.
///
/// None of that is checkable by reading [TasksState] — the grouping is a getter,
/// the flattening is in the page, and the ordering is only visible once rendered.
/// This golden pins the whole of it, red Overdue header included.
///
/// **Known limitation.** `DateTimeX.relativeLabel` lives in `core/utils/`, which
/// is protected, and reads `DateTime.now()` directly rather than `clock.now()`.
/// Under the frozen clock it therefore measures against the real wall clock, so
/// the day sections read '16 Jan' rather than 'Today'/'Tomorrow'. That is stable
/// — it is wrong by the same amount every day — but it does mean these goldens do
/// not exercise the relative wording. `Task.isOverdue` does honour the frozen
/// clock, which is why the Overdue section below is real.
void main() {
  final createdAt = DateTime(2026, 1, 10, 8);

  const work = Category(id: 'c1', name: 'Work', colorValue: 0xFF4C8BF5);
  const home = Category(id: 'c2', name: 'Home', colorValue: 0xFF66BB6A);

  Task task({
    required String id,
    required String title,
    DateTime? dueDate,
    TaskPriority priority = TaskPriority.medium,
    String? categoryId,
    List<SubTask> subtasks = const <SubTask>[],
    List<String> tags = const <String>[],
  }) =>
      Task(
        id: id,
        title: title,
        dueDate: dueDate,
        priority: priority,
        categoryId: categoryId,
        subtasks: subtasks,
        tags: tags,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

  final state = TasksState(
    selectedDate: DateTime(2026, 1, 15),
    categories: const [work, home],
    tasks: [
      // Two days past the frozen clock: the red Overdue section.
      task(
        id: 't1',
        title: 'Renew domain registration',
        dueDate: DateTime(2026, 1, 13, 9),
        priority: TaskPriority.critical,
        categoryId: 'c1',
      ),
      task(
        id: 't2',
        title: 'Reply to the landlord',
        dueDate: DateTime(2026, 1, 14, 17),
        priority: TaskPriority.high,
        categoryId: 'c2',
      ),
      // The frozen "today".
      task(
        id: 't3',
        title: 'Ship the golden tests',
        dueDate: DateTime(2026, 1, 15, 18),
        priority: TaskPriority.high,
        categoryId: 'c1',
        subtasks: const [
          SubTask(id: 's1', title: 'Freeze the clock', isDone: true),
          SubTask(id: 's2', title: 'Load the fonts', isDone: true),
          SubTask(id: 's3', title: 'Write the fixtures'),
        ],
        tags: const ['phase-14'],
      ),
      task(
        id: 't4',
        title: 'Water the plants',
        dueDate: DateTime(2026, 1, 15, 20),
        priority: TaskPriority.low,
        categoryId: 'c2',
      ),
      task(
        id: 't5',
        title: 'Team retrospective',
        dueDate: DateTime(2026, 1, 16, 11),
        categoryId: 'c1',
      ),
      task(
        id: 't6',
        title: 'Book the flights',
        dueDate: DateTime(2026, 1, 20, 9),
        priority: TaskPriority.high,
      ),
      // No due date: the section that exists so a saved task cannot vanish.
      task(id: 't7', title: 'Read SICP, eventually'),
      // Completed, so "By date" must not list it at all.
      Task(
        id: 't8',
        title: 'Pay the electricity bill',
        dueDate: DateTime(2026, 1, 12),
        status: TaskStatus.completed,
        completedAt: DateTime(2026, 1, 12, 19),
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    ],
  );

  testWidgets('the Tasks list renders its date sections, overdue first',
      (tester) async {
    await freeze(() async {
      final bloc = MockTasksBloc();
      whenListen(bloc, const Stream<TasksState>.empty(), initialState: state);

      await pumpGolden(
        tester,
        BlocProvider<TasksBloc>.value(value: bloc, child: const TasksPage()),
      );

      // The section header, plus the status line on each of the two late cards.
      // The cards now say *how* late ("Overdue by 2 days") rather than a bare
      // badge, which is still the frozen clock being read rather than the real
      // one — the reason an overdue fixture renders coherently at all.
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.textContaining('Overdue by'), findsNWidgets(2));
      expect(find.text('Renew domain registration'), findsOneWidget);
      expect(find.text('Pay the electricity bill'), findsNothing,
          reason: '"By date" lists open work only');

      await expectLater(
        find.byType(TasksPage),
        matchesGoldenFile('goldens/tasks_page.png'),
      );
    });
  });
}
