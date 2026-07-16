import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/daos/tasks_dao.dart';
import 'package:everything_app/data/models/category.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:uuid/uuid.dart';

/// [TasksService] is the Tasks module's persistence layer.
///
/// Drift-backed rather than Dio-backed, but keeps the standard service
/// contract: every method returns [JsonResponse] and nothing throws past this
/// layer, so callers cannot distinguish local storage from a network source.
class TasksService {
  TasksService({required this.dao});

  final TasksDao dao;

  static const Uuid _uuid = Uuid();

  // ── Streams ────────────────────────────────────────────────────────────────
  //
  // These return raw streams rather than JsonResponse. Failures surface as
  // stream errors, which the bloc's emit.forEach catches.

  Stream<List<Task>> watchAll() =>
      dao.watchAll().map((rows) => rows.map(Task.fromEntry).toList());

  Stream<List<Category>> watchCategories() => dao
      .watchCategories()
      .map((rows) => rows.map(Category.fromEntry).toList());

  // ── Reads ──────────────────────────────────────────────────────────────────

  Future<JsonResponse> categories() async {
    try {
      final rows = await dao.allCategories();
      return JsonResponse.success(
        message: 'Loaded successfully.',
        data: rows.map(Category.fromEntry).toList(),
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not load categories.',
      );
    }
  }

  /// [seedDefaultCategories] installs the starter categories on first launch.
  Future<JsonResponse> seedDefaultCategories() async {
    try {
      await dao.seedCategoriesIfEmpty([
        for (final category in kDefaultCategories)
          Category(
            id: _uuid.v4(),
            name: category.name,
            colorValue: category.color,
            iconName: category.icon,
            isDefault: true,
          ).toCompanion(),
      ]);

      return JsonResponse.success(message: 'Categories ready.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not prepare categories.',
      );
    }
  }

  // ── Writes ─────────────────────────────────────────────────────────────────

  /// [create] inserts a new task.
  ///
  /// Validation lives here rather than in the bloc, so every caller is subject
  /// to it regardless of entry point (Property 2).
  Future<JsonResponse> create(Task task) async {
    try {
      if (task.title.isBlank) {
        return JsonResponse.failure(
          statusCode: 400,
          message: 'A task needs a title.',
        );
      }

      final now = DateTime.now();
      final prepared = task.copyWith(
        id: task.id.isBlank ? _uuid.v4() : task.id,
        title: task.title.trim(),
        createdAt: now,
        updatedAt: now,
      );

      await dao.upsert(prepared.toCompanion());

      return JsonResponse.created(message: 'Task added.', data: prepared);
} on Exception catch (e) {
  return JsonResponse.failure(statusCode: 500, message: 'DEBUG: $e');
}
  }

  /// [update] saves an edited task.
  Future<JsonResponse> update(Task task) async {
    try {
      if (task.title.isBlank) {
        return JsonResponse.failure(
          statusCode: 400,
          message: 'A task needs a title.',
        );
      }

      final prepared = task.copyWith(
        title: task.title.trim(),
        updatedAt: DateTime.now(),
      );

      await dao.upsert(prepared.toCompanion());

      return JsonResponse.success(message: 'Task updated.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not update the task.',
      );
    }
  }

  /// [setCompleted] completes or re-opens a task, rolling a recurring series
  /// forward when it is completed (Requirement 4.8, Property 4).
  ///
  /// The completion and the successor insert go through [TasksDao.upsertAll] in
  /// a single transaction, so a crash between the two writes cannot lose the
  /// next occurrence or leave a completed task with no successor.
  Future<JsonResponse> setCompleted({
    required Task task,
    required bool isCompleted,
  }) async {
    try {
      final now = DateTime.now();

      if (!isCompleted) {
        final reopened = task.copyWith(
          status: TaskStatus.pending,
          clearCompletedAt: true,
          updatedAt: now,
        );
        await dao.upsert(reopened.toCompanion());
        return JsonResponse.success(message: 'Task reopened.', data: reopened);
      }

      final completed = task.copyWith(
        status: TaskStatus.completed,
        completedAt: now,
        updatedAt: now,
      );

      final next = _nextOccurrenceOf(completed);

      if (next == null) {
        await dao.upsert(completed.toCompanion());
        return JsonResponse.success(message: 'Task completed.', data: completed);
      }

      await dao.upsertAll([completed.toCompanion(), next.toCompanion()]);

      return JsonResponse.success(
        message: 'Task completed. Next one scheduled.',
        data: completed,
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not update the task.',
      );
    }
  }

  Future<JsonResponse> delete(String id) async {
    try {
      final removed = await dao.deleteById(id);

      return removed == 0
          ? JsonResponse.failure(
              statusCode: 404,
              message: 'That task no longer exists.',
            )
          : JsonResponse.success(message: 'Task deleted.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not delete the task.',
      );
    }
  }

  /// [_nextOccurrenceOf] builds the successor of a completed recurring task.
  ///
  /// Returns null when the task does not recur, has no due date to advance from,
  /// or the series has ended.
  ///
  /// The successor is a **fresh, pending task**: new id, cleared completion, and
  /// subtasks reset to undone. Everything else (title, priority, category, tags,
  /// notes, the rule itself) carries over, as required by Property 4.
  Task? _nextOccurrenceOf(Task task) {
    final rule = task.recurrence;
    final dueDate = task.dueDate;
    if (rule == null || dueDate == null) return null;

    final nextDue = rule.nextOccurrenceAfter(dueDate);
    if (nextDue == null) return null;

    final now = DateTime.now();
    final shift = nextDue.difference(dueDate);

    return task.copyWith(
      id: _uuid.v4(),
      // Chains the series so it can be traced or bulk-edited later.
      parentTaskId: task.parentTaskId ?? task.id,
      dueDate: nextDue,
      status: TaskStatus.pending,
      clearCompletedAt: true,
      subtasks: [
        for (final subtask in task.subtasks) subtask.copyWith(isDone: false),
      ],
      // Reminders move with the due date, keeping their offset — "30 minutes
      // before" stays 30 minutes before (Requirement 5.3). Copying the absolute
      // times over would hand the new occurrence a set of reminders that have
      // already passed, and it would never be announced.
      //
      // Each gets a fresh id: the notification id is derived from it, and reusing
      // it would let the successor's reminder collide with the one still queued
      // for the occurrence just completed.
      reminders: [
        for (final reminder in task.reminders)
          Reminder(id: _uuid.v4(), at: reminder.at.add(shift)),
      ],
      createdAt: now,
      updatedAt: now,
    );
  }
}
