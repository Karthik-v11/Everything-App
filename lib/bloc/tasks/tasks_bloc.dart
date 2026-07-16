import 'dart:async';
import 'dart:collection';

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
/// Style A: it holds the task list, the selected date, the active filter and the
/// search query.
///
/// It subscribes once to the DAO stream via [WatchTasksEvent] and never re-reads.
/// Every write — a completion, an edit, a recurrence rollover — goes to the
/// database and returns through that stream, so no screen needs a reload event
/// and none can drift out of sync with the database.
///
/// Filtering and searching are applied in memory over the streamed list, which
/// keeps the stream as the single source of truth.
///
/// Notifications (Requirement 5) are scheduled from here for the same reason.
/// The bloc already holds the database's own view of every task, so the schedule
/// is derived from that view rather than written alongside each task edit. A
/// reminder therefore cannot outlive the task it belongs to: whatever the stream
/// says, the OS queue is made to match (see [SyncRemindersEvent]).
///
/// Events:
/// 1) [WatchTasksEvent] — subscribe to tasks and categories. Fired once at start.
/// 2) [SelectDateEvent] — the calendar strip.
/// 3) [ChangeFilterEvent] — Today / Tomorrow / Upcoming / Completed / Overdue.
/// 4) [SearchTasksEvent] — in-module search (Requirement 4.10).
/// 5) [ToggleTaskCompletionEvent] — the checkbox (Requirement 4.6).
/// 6) [DeleteTaskEvent] — remove a task.
/// 7) [SyncRemindersEvent] — rebuild the notification schedule (Requirement 5).
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
  /// One user action can write several tasks at once — a recurrence rollover
  /// completes one task and inserts its successor, a future bulk edit touches
  /// many — and each write comes back through [watchAll]'s stream. Rebuilding the
  /// whole [NotificationPlan] and diffing it against the OS queue once per write
  /// in that burst is wasted work on the UI isolate. This coalesces the burst:
  /// the first write queues the sync, the rest are skipped, and the single run
  /// sees every task the burst wrote. It gates only the stream path — a
  /// settings-carrying [SyncRemindersEvent] from [SettingsBloc] never sets it and
  /// so is never skipped.
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
        // Every write in the app — from this bloc, from the form, from anything
        // added later — comes back through this stream, so this is the one place
        // that has to ask for a reschedule. onData cannot await, so the work is
        // queued as an event rather than done inline. A burst of writes queues
        // exactly one sync (see [_reschedulePending]).
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
  /// It runs on every change to the task list and on every settings change, and
  /// it is idempotent: the plan is the desired end state, and the service cancels
  /// or schedules only the difference. Running it more often than necessary costs
  /// one query of the pending queue and nothing else.
  ///
  /// It does nothing until [SettingsBloc] has reported the user's configuration.
  /// Scheduling against the defaults first would fire a burst of reminders at a
  /// user who had switched them off, and cancel them a moment later.
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
