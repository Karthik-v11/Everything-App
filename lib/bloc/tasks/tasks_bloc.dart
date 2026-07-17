import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:everything_app/bloc/event_transformers.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/models/category.dart';
import 'package:everything_app/data/models/notification_settings.dart';
import 'package:everything_app/data/models/scheduled_notification.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/data/repositories/notifications_repository.dart';
import 'package:everything_app/data/repositories/tasks_repository.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'tasks_event.dart';
part 'tasks_state.dart';

/// [TasksBloc] owns the Tasks module (Requirement 4).
///
/// It subscribes once to the DAO stream via [WatchTasksEvent] and never re-reads:
/// every write returns through that stream, so no screen needs a reload event and
/// none can drift from the database. Filtering and searching run in memory over
/// the streamed list, keeping the stream the single source of truth.
///
/// Notifications (Requirement 5) are scheduled from here because this bloc already
/// holds the database's view of every task, so the OS queue is made to match the
/// stream and a reminder cannot outlive its task (see [SyncRemindersEvent]).
class TasksBloc extends HydratedBloc<TasksEvent, TasksState> {
  TasksBloc({
    required this.repository,
    required this.notificationsRepository,
  }) : super(TasksState.initial()) {
    on<WatchTasksEvent>(_onWatchTasksEvent);
    on<SelectDateEvent>(_onSelectDateEvent);
    on<ChangeFilterEvent>(_onChangeFilterEvent);
    on<SearchTasksEvent>(
      _onSearchTasksEvent,
      transformer: debounce(const Duration(milliseconds: 250)),
    );
    on<ToggleTaskCompletionEvent>(_onToggleTaskCompletionEvent);
    on<DeleteTaskEvent>(_onDeleteTaskEvent);
    on<SyncRemindersEvent>(_onSyncRemindersEvent);
  }

  final TasksRepository repository;
  final NotificationsRepository notificationsRepository;

  /// True while a stream-triggered reschedule is already queued but has not run.
  ///
  /// One user action can write several tasks at once (a recurrence rollover
  /// completes one and inserts its successor), and each write returns through
  /// [watchAll]'s stream. This coalesces the burst — the first write queues the
  /// sync, the rest are skipped, and the single run sees every task the burst
  /// wrote — rather than rebuilding and diffing the whole [NotificationPlan] once
  /// per write on the UI isolate. It gates only the stream path: a
  /// settings-carrying [SyncRemindersEvent] never sets it and is never skipped.
  bool _reschedulePending = false;

  FutureOr<void> _onWatchTasksEvent(
    WatchTasksEvent event,
    Emitter<TasksState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: '', message: ''));

    await repository.seedDefaultCategories();

    // Categories first: a task list rendered before its categories arrive would
    // show unlabelled cards for a frame.
    final categories = await repository.categories();
    if (categories.success) {
      emit(
        state.copyWith(categories: categories.data! as List<Category>),
      );
    }

    // emit.forEach holds the subscription for the life of the bloc and cancels it
    // on close.
    await emit.forEach<List<Task>>(
      repository.watchAll(),
      onData: (tasks) {
        // Every write in the app comes back through this stream, so this is the
        // one place that asks for a reschedule. onData cannot await, so the work
        // is queued as an event. A burst queues exactly one sync
        // (see [_reschedulePending]).
        if (!_reschedulePending) {
          _reschedulePending = true;
          add(const SyncRemindersEvent());
        }

        return state.copyWith(isLoading: false, tasks: tasks, error: '');
      },
      onError: (_, _) => state.copyWith(
        isLoading: false,
        error: 'Could not load your tasks.',
      ),
    );
  }

  FutureOr<void> _onSelectDateEvent(
    SelectDateEvent event,
    Emitter<TasksState> emit,
  ) {
    // A date is only meaningful in the date view, so picking one switches to it.
    emit(
      state.copyWith(
        selectedDate: event.date.dateOnly,
        filter: TaskFilter.date,
      ),
    );
  }

  FutureOr<void> _onChangeFilterEvent(
    ChangeFilterEvent event,
    Emitter<TasksState> emit,
  ) {
    emit(
      state.copyWith(
        filter: event.filter,
        categoryId: event.categoryId,
        clearCategoryId: event.categoryId == null,
        priority: event.priority,
        clearPriority: event.priority == null,
      ),
    );
  }

  FutureOr<void> _onSearchTasksEvent(
    SearchTasksEvent event,
    Emitter<TasksState> emit,
  ) {
    emit(state.copyWith(query: event.query));
  }

  FutureOr<void> _onToggleTaskCompletionEvent(
    ToggleTaskCompletionEvent event,
    Emitter<TasksState> emit,
  ) async {
    try {
      // No isLoading: the stream returns the updated list within milliseconds, and
      // a spinner over the whole list for a local write would flicker.
      final response = await repository.setCompleted(
        task: event.task,
        isCompleted: event.isCompleted,
      );

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not update the task.'));
    }
  }

  FutureOr<void> _onDeleteTaskEvent(
    DeleteTaskEvent event,
    Emitter<TasksState> emit,
  ) async {
    try {
      final response = await repository.delete(event.id);

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not delete the task.'));
    }
  }

  /// [_onSyncRemindersEvent] rebuilds the OS notification schedule from the task
  /// list and the user's settings (Requirement 5).
  ///
  /// Idempotent: the plan is the desired end state and the service cancels or
  /// schedules only the difference, so an extra run costs one queue query.
  ///
  /// Does nothing until [SettingsBloc] has reported the user's configuration —
  /// scheduling against the defaults first would fire a burst of reminders at a
  /// user who had switched them off.
  FutureOr<void> _onSyncRemindersEvent(
    SyncRemindersEvent event,
    Emitter<TasksState> emit,
  ) async {
    // Cleared before the plan is built, so a write that lands during the async
    // applyPlan below queues a fresh sync rather than being swallowed.
    _reschedulePending = false;

    final settings = event.settings ?? state.notificationSettings;
    if (settings == null) return;

    if (settings != state.notificationSettings) {
      emit(state.copyWith(notificationSettings: settings));
    }

    try {
      final plan = NotificationPlan.build(
        tasks: state.tasks,
        settings: settings,
        now: DateTime.now(),
      );

      // Only the task kinds: the To-Buy list reconciles its own reminders against
      // the same queue, and a reconciler that claimed everything would cancel
      // them (see NotificationService.applyPlan).
      final response = await notificationsRepository.applyPlan(
        plan,
        owns: NotificationKind.taskKinds,
      );

      if (!response.success) emit(state.copyWith(error: response.message));
    } on Exception {
      emit(state.copyWith(error: 'Could not update your reminders.'));
    }
  }

  /// Only the filter choices are persisted. A rehydrated task list would race the
  /// database stream on launch, and a rehydrated date would restore a stale day.
  @override
  TasksState? fromJson(Map<String, dynamic> json) => TasksState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(TasksState state) => state.toJson();
}
