import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:intl/intl.dart';

/// [HomeWidgetTask] is one row on the tasks widget.
///
/// A thin projection of [Task]: carrying the whole task would put notes,
/// subtasks and reminders into a shared container another process can read.
class HomeWidgetTask extends Equatable {
  const HomeWidgetTask({
    required this.id,
    required this.title,
    required this.isOverdue,
    required this.priority,
    this.dueLabel = '',
  });

  final String id;
  final String title;
  final bool isOverdue;

  /// The task's priority as its enum name — `low`, `medium`, `high`,
  /// `critical` — which the native side maps to a marker colour.
  ///
  /// The name rather than the colour: a hex string here would mean the widget's
  /// palette were decided in Dart and the rest of it in `widget_colors.xml`, and
  /// the native side cannot read `AppColors` anyway (see
  /// `EverythingWidgetProvider`). An unrecognised name draws the medium marker
  /// rather than nothing.
  final String priority;

  final String dueLabel;

  /// There is no `isCompleted`: [HomeWidgetPayload.build] no longer publishes
  /// completed tasks, so the field could only ever be `false`.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isOverdue': isOverdue,
        'priority': priority,
        'dueLabel': dueLabel,
      };

  @override
  List<Object?> get props => [id, title, isOverdue, priority, dueLabel];
}

/// [HomeWidgetPayload] is everything the home screen widgets render
/// (Requirement 13).
///
/// Built pure — a function of the data and a clock, like `NotificationPlan` — so
/// what a widget will show is assertable without putting one on a home screen.
///
/// It ships **formatted** strings so the money rule lives in one place: shipping
/// `expenseMinor` would make Kotlin and Swift each reimplement
/// `Helpers.formatMoney` (minor units, `en_IN` lakh/crore grouping, symbol), and
/// the home screen could then disagree with the Finance tab.
///
/// [maxTasks] is what is written, not what is drawn: which widget size the user
/// placed is known only to the native code, so the longest list is written once
/// and each size truncates it.
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

  /// Today's open work, most urgent first. Completed tasks are never in here —
  /// see [_isForToday].
  final List<HomeWidgetTask> tasks;

  /// How many tasks are in [tasks] before the [maxTasks] cap — the widget's
  /// title counts all of today's open work, not the rows that fit.
  final int openCount;

  final int completedCount;
  final int overdueCount;

  /// The month's spend, already formatted — `₹15,000`.
  final String spentLabel;

  /// What the figure is — `Spent in July`.
  final String spentCaption;

  /// When this was built, for the widget's footer — the refresh cycle is 30
  /// minutes, so the user needs to know how stale the figures are.
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
            isOverdue: _isOverdue(task, now),
            priority: task.priority.name,
            dueLabel: _dueLabelOf(task, now),
          ),
      ],
      openCount: todays.length,
      completedCount: _completedToday(tasks, today).length,
      overdueCount: tasks.where((task) => _isOverdue(task, now)).length,
      spentLabel: Helpers.formatMoney(expenseMinor, compact: true),
      spentCaption: 'Spent in ${DateFormat.MMMM().format(now)}',
      updatedAtLabel: DateFormat.jm().format(now),
    );
  }

  /// [_isOverdue] is [Task.isOverdue]'s rule against [now], not `Task.isOverdue`
  /// itself: that getter reads the wall clock, which would stop this being a pure
  /// function of (tasks, now) and make it unassertable against an injected clock.
  ///
  /// The condition is `pending`, not `!isCompleted`: a cancelled task is not late.
  static bool _isOverdue(Task task, DateTime now) =>
      task.status == TaskStatus.pending &&
      task.dueDate != null &&
      task.dueDate!.isBefore(now);

  /// [_isForToday] is what the widget calls today's work: anything still open and
  /// due today, and anything already overdue — a widget showing only today's due
  /// items would go empty on the day the user is furthest behind.
  ///
  /// Completed tasks are **not** today's work. The widget is a list of what is
  /// left, and a finished task sitting in four rows of a home screen is four rows
  /// not showing the next thing. What was done today is still counted, in
  /// [completedCount], because a count is a fact about the day rather than a row
  /// competing for the space.
  static bool _isForToday(Task task, DateTime today) {
    if (task.isCompleted) return false;

    final due = task.dueDate;
    if (due == null) return false;

    final dueDay = DateTime(due.year, due.month, due.day);
    return dueDay == today || dueDay.isBefore(today);
  }

  /// [_completedToday] is what [_isForToday] filtered out, kept for the count.
  ///
  /// A task completed today is one whose due day was today — the model has no
  /// completion timestamp, so the due date is the only day it can be attributed
  /// to, and reading it any other way would be inventing data.
  static Iterable<Task> _completedToday(List<Task> tasks, DateTime today) => [
        for (final task in tasks)
          if (task.isCompleted &&
              task.dueDate != null &&
              DateTime(
                    task.dueDate!.year,
                    task.dueDate!.month,
                    task.dueDate!.day,
                  ) ==
                  today)
            task,
      ];

  /// [_byUrgency] puts overdue first, then the rest by when they are due — which
  /// is the order the list is useful in at a glance. Completion no longer sorts
  /// anything: [_isForToday] has already dropped every completed task.
  static int _byUrgency(Task a, Task b, DateTime now) {
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
  /// The task list goes over as one JSON string rather than indexed keys
  /// (`task_0_title`, …), which would have to be cleared when the list shrinks or
  /// the native side would draw rows left over from a longer list.
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
