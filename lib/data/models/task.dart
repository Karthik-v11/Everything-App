import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/app_colors.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:flutter/material.dart';

/// [TaskPriority] is the urgency of a task (Requirement 4.4).
enum TaskPriority {
  low(AppColors.priorityLow),
  medium(AppColors.priorityMedium),
  high(AppColors.priorityHigh),
  critical(AppColors.priorityCritical);

  const TaskPriority(this.color);

  final Color color;

  static TaskPriority fromName(String? name) => TaskPriority.values.firstWhere(
        (value) => value.name == name,
        orElse: () => TaskPriority.medium,
      );
}

/// [TaskStatus] is the stored lifecycle state of a task.
///
/// `overdue` is not a member: it is a function of the due date and the current
/// time, so it is derived on read (see [Task.isOverdue], Requirement 4.7) rather
/// than stored and swept at midnight.
enum TaskStatus {
  pending,
  completed,
  cancelled;

  static TaskStatus fromName(String? name) => TaskStatus.values.firstWhere(
        (value) => value.name == name,
        orElse: () => TaskStatus.pending,
      );
}

/// [RecurrenceFrequency] is the repeat unit of a recurring task.
enum RecurrenceFrequency {
  daily,
  weekly,
  monthly,
  yearly;

  static RecurrenceFrequency fromName(String? name) =>
      RecurrenceFrequency.values.firstWhere(
        (value) => value.name == name,
        orElse: () => RecurrenceFrequency.daily,
      );
}

/// [RecurrenceRule] describes how a task repeats (Requirement 4.8).
///
/// [interval] is the multiplier — every 2 weeks is `weekly` with interval 2.
/// [until] optionally ends the series.
class RecurrenceRule extends Equatable {
  const RecurrenceRule({
    required this.frequency,
    this.interval = 1,
    this.until,
  });

  final RecurrenceFrequency frequency;
  final int interval;
  final DateTime? until;

  factory RecurrenceRule.fromJson(Map<String, dynamic> json) => RecurrenceRule(
        frequency: RecurrenceFrequency.fromName(json['frequency']?.toString()),
        interval: int.tryParse('${json['interval']}') ?? 1,
        until: DateTime.tryParse('${json['until']}'),
      );

  Map<String, dynamic> toJson() => {
        'frequency': frequency.name,
        'interval': interval,
        'until': until?.toIso8601String(),
      };

  /// [nextOccurrenceAfter] is the due date of the occurrence following [from].
  ///
  /// Returns null once the series has passed [until].
  ///
  /// Month and year steps go through [_addMonths], which clamps to the last day
  /// of a short month. [DateTime]'s own arithmetic overflows instead, rolling
  /// 31 January + 1 month into early March.
  DateTime? nextOccurrenceAfter(DateTime from) {
    final next = switch (frequency) {
      RecurrenceFrequency.daily => from.add(Duration(days: interval)),
      RecurrenceFrequency.weekly => from.add(Duration(days: 7 * interval)),
      RecurrenceFrequency.monthly => _addMonths(from, interval),
      RecurrenceFrequency.yearly => _addMonths(from, 12 * interval),
    };

    if (until != null && next.isAfter(until!)) return null;
    return next;
  }

  static DateTime _addMonths(DateTime from, int months) {
    final targetYear = from.year + ((from.month - 1 + months) ~/ 12);
    final targetMonth = ((from.month - 1 + months) % 12) + 1;

    // Day 0 of the following month is the last day of the target month.
    final daysInTargetMonth = DateTime(targetYear, targetMonth + 1, 0).day;

    return DateTime(
      targetYear,
      targetMonth,
      from.day.clamp(1, daysInTargetMonth),
      from.hour,
      from.minute,
    );
  }

  @override
  List<Object?> get props => [frequency, interval, until];
}

/// [SubTask] is one step within a task (Requirement 4.11).
class SubTask extends Equatable {
  const SubTask({
    required this.id,
    required this.title,
    this.isDone = false,
  });

  final String id;
  final String title;
  final bool isDone;

  factory SubTask.fromJson(Map<String, dynamic> json) => SubTask(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        isDone: json['isDone'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isDone': isDone,
      };

  SubTask copyWith({String? id, String? title, bool? isDone}) => SubTask(
        id: id ?? this.id,
        title: title ?? this.title,
        isDone: isDone ?? this.isDone,
      );

  @override
  List<Object?> get props => [id, title, isDone];
}

/// [Reminder] is a scheduled notification for a task (Requirement 5).
///
/// Phase 4 consumes these; Phase 3 only stores them.
class Reminder extends Equatable {
  const Reminder({required this.id, required this.at});

  final String id;
  final DateTime at;

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: json['id']?.toString() ?? '',
        at: DateTime.tryParse('${json['at']}') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
      };

  @override
  List<Object?> get props => [id, at];
}

/// [Task] is a unit of work (Requirement 4).
class Task extends Equatable {
  const Task({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.dueDate,
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.pending,
    this.categoryId,
    this.projectId,
    this.parentTaskId,
    this.notes,
    this.recurrence,
    this.tags = const <String>[],
    this.reminders = const <Reminder>[],
    this.subtasks = const <SubTask>[],
    this.completedAt,
  });

  final String id;
  final String title;
  final DateTime? dueDate;
  final TaskPriority priority;
  final TaskStatus status;
  final String? categoryId;
  final String? projectId;
  final String? parentTaskId;
  final String? notes;
  final RecurrenceRule? recurrence;
  final List<String> tags;
  final List<Reminder> reminders;
  final List<SubTask> subtasks;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCompleted => status == TaskStatus.completed;

  bool get isRecurring => recurrence != null;

  /// [isOverdue] is true when the due date has passed and the task is still open
  /// (Requirement 4.7). Derived, never stored — see [TaskStatus].
  bool get isOverdue =>
      status == TaskStatus.pending &&
      dueDate != null &&
      dueDate!.isBefore(DateTime.now());

  int get completedSubtaskCount =>
      subtasks.where((subtask) => subtask.isDone).length;

  /// [subtaskProgress] is "2/5" (Requirement 4.11), or null when there are none.
  String? get subtaskProgress => subtasks.isEmpty
      ? null
      : '$completedSubtaskCount/${subtasks.length}';

  /// [Task.fromEntry] maps a Drift row to the domain model.
  factory Task.fromEntry(TaskEntry entry) => Task(
        id: entry.id,
        title: entry.title,
        dueDate: entry.dueDate,
        priority: TaskPriority.fromName(entry.priority),
        status: TaskStatus.fromName(entry.status),
        categoryId: entry.categoryId,
        projectId: entry.projectId,
        parentTaskId: entry.parentTaskId,
        notes: entry.notes,
        recurrence: entry.recurrenceJson == null
            ? null
            : RecurrenceRule.fromJson(
                jsonDecode(entry.recurrenceJson!) as Map<String, dynamic>,
              ),
        tags: _decodeList(entry.tagsJson).cast<String>(),
        reminders: _decodeList(entry.remindersJson)
            .map((e) => Reminder.fromJson(e as Map<String, dynamic>))
            .toList(),
        subtasks: _decodeList(entry.subtasksJson)
            .map((e) => SubTask.fromJson(e as Map<String, dynamic>))
            .toList(),
        completedAt: entry.completedAt,
        createdAt: entry.createdAt,
        updatedAt: entry.updatedAt,
      );

  /// [toCompanion] maps the domain model back to a Drift row.
  TasksTableCompanion toCompanion() => TasksTableCompanion.insert(
        id: id,
        title: title,
        dueDate: Value(dueDate),
        priority: Value(priority.name),
        status: Value(status.name),
        categoryId: Value(categoryId),
        projectId: Value(projectId),
        parentTaskId: Value(parentTaskId),
        notes: Value(notes),
        recurrenceJson: Value(
          recurrence == null ? null : jsonEncode(recurrence!.toJson()),
        ),
        tagsJson: Value(jsonEncode(tags)),
        remindersJson: Value(
          jsonEncode(reminders.map((e) => e.toJson()).toList()),
        ),
        subtasksJson: Value(
          jsonEncode(subtasks.map((e) => e.toJson()).toList()),
        ),
        completedAt: Value(completedAt),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Task copyWith({
    String? id,
    String? title,
    DateTime? dueDate,
    bool clearDueDate = false,
    TaskPriority? priority,
    TaskStatus? status,
    String? categoryId,
    bool clearCategoryId = false,
    String? projectId,
    String? parentTaskId,
    String? notes,
    RecurrenceRule? recurrence,
    bool clearRecurrence = false,
    List<String>? tags,
    List<Reminder>? reminders,
    List<SubTask>? subtasks,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Task(
        id: id ?? this.id,
        title: title ?? this.title,
        dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
        priority: priority ?? this.priority,
        status: status ?? this.status,
        categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
        projectId: projectId ?? this.projectId,
        parentTaskId: parentTaskId ?? this.parentTaskId,
        notes: notes ?? this.notes,
        recurrence:
            clearRecurrence ? null : (recurrence ?? this.recurrence),
        tags: tags ?? this.tags,
        reminders: reminders ?? this.reminders,
        subtasks: subtasks ?? this.subtasks,
        completedAt:
            clearCompletedAt ? null : (completedAt ?? this.completedAt),
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// [matches] is the in-memory search predicate used by the Tasks module
  /// (Requirement 4.10): title, tags, notes.
  ///
  /// Category is matched by the caller, which is the only place that can resolve
  /// a category id to its name.
  bool matches(String query) {
    if (query.isBlank) return true;
    return title.containsIgnoreCase(query) ||
        (notes?.containsIgnoreCase(query) ?? false) ||
        tags.any((tag) => tag.containsIgnoreCase(query));
  }

  static List<dynamic> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } on FormatException {
      // A corrupt JSON blob must not take down the whole task list.
      return const [];
    }
  }

  @override
  List<Object?> get props => [
        id,
        title,
        dueDate,
        priority,
        status,
        categoryId,
        projectId,
        parentTaskId,
        notes,
        recurrence,
        tags,
        reminders,
        subtasks,
        completedAt,
        createdAt,
        updatedAt,
      ];
}
