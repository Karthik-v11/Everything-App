part of 'tasks_bloc.dart';

/// [TasksEvent] is the base class for every Tasks module event.
abstract class TasksEvent extends Equatable {
  const TasksEvent();

  @override
  List<Object?> get props => [];
}

/// [WatchTasksEvent] subscribes to the task and category streams.
///
/// Dispatched once, at bloc creation. Every later change arrives through the
/// stream rather than through another event.
class WatchTasksEvent extends TasksEvent {
  const WatchTasksEvent();
}

/// [SelectDateEvent] picks a day on the calendar strip (Requirement 4.2).
/// [date] is the newly selected day.
class SelectDateEvent extends TasksEvent {
  const SelectDateEvent({required this.date});

  final DateTime date;

  @override
  List<Object?> get props => [date];
}

/// [ChangeFilterEvent] sets the active filter (Requirement 4.9).
///
/// [categoryId] and [priority] narrow the result further, and null clears them.
class ChangeFilterEvent extends TasksEvent {
  const ChangeFilterEvent({
    required this.filter,
    this.categoryId,
    this.priority,
  });

  final TaskFilter filter;
  final String? categoryId;
  final TaskPriority? priority;

  @override
  List<Object?> get props => [filter, categoryId, priority];
}

/// [SearchTasksEvent] filters by title, tags and notes (Requirement 4.10).
/// [query] is the search text; empty clears the search.
class SearchTasksEvent extends TasksEvent {
  const SearchTasksEvent({required this.query});

  final String query;

  @override
  List<Object?> get props => [query];
}

/// [ToggleTaskCompletionEvent] ticks or unticks a task (Requirement 4.6).
///
/// Completing a recurring task also generates its next occurrence
/// (Requirement 4.8) — handled in the service, transactionally.
class ToggleTaskCompletionEvent extends TasksEvent {
  const ToggleTaskCompletionEvent({
    required this.task,
    required this.isCompleted,
  });

  final Task task;
  final bool isCompleted;

  @override
  List<Object?> get props => [task, isCompleted];
}

/// [DeleteTaskEvent] permanently removes a task.
/// [id] is the task to delete.
class DeleteTaskEvent extends TasksEvent {
  const DeleteTaskEvent({required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}

/// [SyncRemindersEvent] rebuilds the OS notification schedule (Requirement 5).
///
/// Dispatched from two places: the task stream, whenever the list changes, and
/// [SettingsBloc], whenever the user changes a notification setting.
///
/// [settings] is non-null only on the second — the task stream has no opinion on
/// the configuration and passes null, which means "reuse what Settings last
/// said". Until Settings has said anything, nothing is scheduled.
class SyncRemindersEvent extends TasksEvent {
  const SyncRemindersEvent({this.settings});

  final NotificationSettings? settings;

  @override
  List<Object?> get props => [settings];
}
