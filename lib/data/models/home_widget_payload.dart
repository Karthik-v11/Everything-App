import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:intl/intl.dart';

/// [HomeWidgetTask] is one row on the tasks widget.
///
/// A deliberately thin projection of [Task]: a title, whether it is done, and a
/// due label. The home screen has no room for anything else, and a widget that
/// carried the whole task would put notes, subtasks and reminders into a shared
/// container that another process can read (see [HomeWidgetPayload]).
class HomeWidgetTask extends Equatable {
  const HomeWidgetTask({
    required this.id,
    required this.title,
    required this.isCompleted,
    required this.isOverdue,
    this.dueLabel = '',
  });

  final String id;
  final String title;
  final bool isCompleted;
  final bool isOverdue;
  final String dueLabel;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isCompleted': isCompleted,
        'isOverdue': isOverdue,
        'dueLabel': dueLabel,
      };

  @override
  List<Object?> get props => [id, title, isCompleted, isOverdue, dueLabel];
}

/// [HomeWidgetPayload] is everything the home screen widgets render
/// (Requirement 13).
///
/// **It is built pure and it ships formatted strings, both on purpose.**
///
/// Pure, because it is the same shape as Phase 4's `NotificationPlan`: a function
/// of the data and a clock, so what a widget will show is asserted in a unit test
/// rather than by putting a widget on a home screen and waiting half an hour.
///
/// Formatted, because the alternative is worse than it looks. If this shipped
/// `expenseMinor: 1500000`, then Kotlin and Swift would each have to reimplement
/// `Helpers.formatMoney` — minor-unit division, the `en_IN` lakh/crore grouping,
/// the currency symbol — and three implementations of one rule is three chances
/// for the home screen to disagree with the Finance tab about what the month
/// cost. The native side draws strings it is handed and owns no formatting rule
/// at all.
///
/// [maxTasks] is what is written, not what is drawn: the small widget shows three
/// rows and the large one shows eight, and which size the user placed is known
/// only to the native code. Writing the longest list once and letting each size
/// truncate is one write instead of three.
class HomeWidgetPayload extends Equatable {
  const HomeWidgetPayload({
    required this.tasks,
    required this.openCount,
    required this.completedCount,
    required this.overdueCount,
    required this.spentLabel,
    required this.spentCaption,
    required this.updatedAtLabel,
  });

  static const int maxTasks = 8;

  final List<HomeWidgetTask> tasks;
  final int openCount;
  final int completedCount;
  final int overdueCount;

  /// The month's spend, already formatted — `₹15,000`.
  final String spentLabel;

  /// What the figure is — `Spent in July`.
  final String spentCaption;

  /// When this was built, for the widget's footer — the honest answer to "is this
  /// stale?", which on a 30-minute refresh cycle the user genuinely needs.
  final String updatedAtLabel;

  /// [build] projects the app's data onto the home screen.
  ///
  /// [now] is injected rather than read, so "today" is a parameter and the tests
  /// do not depend on the day they run.
  factory HomeWidgetPayload.build({
    required List<Task> tasks,
    required int expenseMinor,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);

    final todays = [
      for (final task in tasks)
        if (_isForToday(task, today)) task,
    ]..sort((a, b) => _byUrgency(a, b, now));

    return HomeWidgetPayload(
      tasks: [
        for (final task in todays.take(maxTasks))
          HomeWidgetTask(
            id: task.id,
            title: task.title,
            isCompleted: task.isCompleted,
            isOverdue: _isOverdue(task, now),
            dueLabel: _dueLabelOf(task, now),
          ),
      ],
      openCount: todays.where((task) => !task.isCompleted).length,
      completedCount: todays.where((task) => task.isCompleted).length,
      overdueCount: tasks.where((task) => _isOverdue(task, now)).length,
      spentLabel: Helpers.formatMoney(expenseMinor, compact: true),
      spentCaption: 'Spent in ${DateFormat.MMMM().format(now)}',
      updatedAtLabel: DateFormat.jm().format(now),
    );
  }

  /// [_isOverdue] is [Task.isOverdue]'s rule, evaluated against [now].
  ///
  /// `Task.isOverdue` reads `DateTime.now()` itself, which is right for a widget
  /// on a screen — it is asking "is this late *right now*" — and wrong here.
  /// Calling it would make this "pure function of (tasks, now)" quietly read the
  /// wall clock, so the payload could not be asserted against an injected clock
  /// and a test written in the past would report every task overdue. This mirrors
  /// `NotificationPlan`, which compares against its injected `now` for the same
  /// reason.
  ///
  /// The condition is `pending`, not `!isCompleted`: a **cancelled** task is not
  /// late, it is abandoned, and Task's own rule says so.
  static bool _isOverdue(Task task, DateTime now) =>
      task.status == TaskStatus.pending &&
      task.dueDate != null &&
      task.dueDate!.isBefore(now);

  /// [_isForToday] is what the widget calls today's work: anything due today, and
  /// anything already overdue.
  ///
  /// Overdue tasks are included deliberately — a widget that showed only today's
  /// due items would go empty and calm on the exact day the user is furthest
  /// behind, which is when it most needs to say something.
  static bool _isForToday(Task task, DateTime today) {
    final due = task.dueDate;
    if (due == null) return false;

    final dueDay = DateTime(due.year, due.month, due.day);
    if (dueDay == today) return true;

    return dueDay.isBefore(today) && !task.isCompleted;
  }

  /// [_byUrgency] puts overdue first, then open, then what is already done —
  /// which is the order the list is useful in at a glance.
  static int _byUrgency(Task a, Task b, DateTime now) {
    if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;

    final aOverdue = _isOverdue(a, now);
    final bOverdue = _isOverdue(b, now);
    if (aOverdue != bOverdue) return aOverdue ? -1 : 1;

    final aDue = a.dueDate;
    final bDue = b.dueDate;
    if (aDue == null || bDue == null) return 0;
    return aDue.compareTo(bDue);
  }

  static String _dueLabelOf(Task task, DateTime now) {
    final due = task.dueDate;
    if (due == null) return '';
    if (_isOverdue(task, now)) return 'Overdue';

    // A due date with no time on it is a day, not a moment: showing "12:00 AM"
    // against it would be inventing a deadline the user never set.
    final hasTime = due.hour != 0 || due.minute != 0;
    return hasTime ? DateFormat.jm().format(due) : '';
  }

  /// [toWidgetData] is the flat key/value map `home_widget` writes.
  ///
  /// The task list goes over as one JSON string rather than as
  /// `task_0_title`, `task_1_title`, … because indexed keys have to be *cleared*
  /// when the list shrinks: go from five tasks to two, and rows three to five
  /// would still be sitting in the shared container for the native side to draw.
  /// One key that is rewritten in full each time cannot go stale in part.
  Map<String, String> toWidgetData() => {
        'tasks': jsonEncode([for (final task in tasks) task.toJson()]),
        'openCount': '$openCount',
        'completedCount': '$completedCount',
        'overdueCount': '$overdueCount',
        'spentLabel': spentLabel,
        'spentCaption': spentCaption,
        'updatedAtLabel': updatedAtLabel,
      };

  @override
  List<Object?> get props => [
        tasks,
        openCount,
        completedCount,
        overdueCount,
        spentLabel,
        spentCaption,
        updatedAtLabel,
      ];
}
