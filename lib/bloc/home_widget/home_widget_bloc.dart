import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/data/models/home_widget_payload.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/data/models/transaction.dart';
import 'package:everything_app/data/models/widget_action.dart';
import 'package:everything_app/data/repositories/finance_repository.dart';
import 'package:everything_app/data/repositories/home_widget_repository.dart';
import 'package:everything_app/data/repositories/tasks_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'home_widget_event.dart';
part 'home_widget_state.dart';

/// [HomeWidgetBloc] keeps the home screen widgets in step with the app
/// (Requirement 13).
///
/// It is the same shape as Phase 4's reminder reconciliation, for the same
/// reason. The obvious implementation — push a new payload from every code path
/// that writes a task or a transaction — is a call site in the task form, the
/// checkbox, the delete, the recurrence rollover, the AI sheet, the share
/// chooser, and every future one; it takes exactly one forgotten call to leave a
/// widget showing yesterday's work. Instead this bloc **watches the same DAO
/// streams every screen reads**, so any write anywhere in the app — including
/// from code that does not exist yet — rebuilds and republishes the payload with
/// no push call anywhere.
///
/// It reads *repositories*, not other blocs. That keeps it clear of CLAUDE.md
/// §4.4 (no bloc reads another bloc's state) while still projecting two modules
/// onto one surface, which no single feature bloc could do: the widget needs
/// tasks and finance, and neither owns the other.
///
/// The widgets can be switched off, and [SettingsBloc] owns that switch and
/// pushes it here via [ConfigureHomeWidgetEvent] — the same event-dispatch rule
/// the notification configuration follows. When it is off, nothing is published
/// and the shared container is emptied (see [HomeWidgetService] on why that
/// matters).
///
/// Events:
/// 1) [WatchHomeWidgetEvent] — start both streams. Fired once, at launch.
/// 2) [SyncHomeWidgetEvent] — rebuild and publish. Coalesced; never called by a
///    feature directly.
/// 3) [ConfigureHomeWidgetEvent] — the user's switch, pushed by [SettingsBloc].
class HomeWidgetBloc extends Bloc<HomeWidgetEvent, HomeWidgetState> {
  HomeWidgetBloc({
    required this.repository,
    required this.tasksRepository,
    required this.financeRepository,
  }) : super(const HomeWidgetState()) {
    on<WatchHomeWidgetEvent>(_onWatchHomeWidgetEvent);
    on<WatchHomeWidgetFinanceEvent>(_onWatchHomeWidgetFinanceEvent);
    on<WatchHomeWidgetTapsEvent>(_onWatchHomeWidgetTapsEvent);
    on<SyncHomeWidgetEvent>(_onSyncHomeWidgetEvent);
    on<ConfigureHomeWidgetEvent>(_onConfigureHomeWidgetEvent);
    on<HomeWidgetTapHandled>(_onHomeWidgetTapHandled);
  }

  final HomeWidgetRepository repository;
  final TasksRepository tasksRepository;
  final FinanceRepository financeRepository;

  /// Coalesces a burst of writes into one publish, exactly as `TasksBloc` does
  /// for the notification schedule. A restore or a recurrence rollover can write
  /// a hundred rows; the home screen needs the end state, not a hundred redraws.
  bool _syncPending = false;

  FutureOr<void> _onWatchHomeWidgetEvent(
    WatchHomeWidgetEvent event,
    Emitter<HomeWidgetState> emit,
  ) async {
    await repository.initialize();

    // The finance and tap streams are started from here so that launch stays one
    // event. Each handler holds its own emitter, which is legal — they are
    // different event types, so bloc treats them as independent handlers.
    add(const WatchHomeWidgetFinanceEvent());
    add(const WatchHomeWidgetTapsEvent());

    await emit.forEach<List<Task>>(
      tasksRepository.watchAll(),
      onData: (tasks) {
        _queueSync();
        return state.copyWith(tasks: tasks);
      },
      onError: (error, stackTrace) =>
          state.copyWith(error: 'Could not read tasks for the widget.'),
    );
  }

  FutureOr<void> _onWatchHomeWidgetFinanceEvent(
    WatchHomeWidgetFinanceEvent event,
    Emitter<HomeWidgetState> emit,
  ) async {
    await emit.forEach<List<Transaction>>(
      financeRepository.watchTransactions(),
      onData: (transactions) {
        _queueSync();
        return state.copyWith(transactions: transactions);
      },
      onError: (error, stackTrace) =>
          state.copyWith(error: 'Could not read finance for the widget.'),
    );
  }

  /// [_onWatchHomeWidgetTapsEvent] wires both of the tap paths.
  ///
  /// A tap on a cold app arrives through [HomeWidgetRepository.initialTap]; a tap
  /// while it is running arrives on the stream. Both land in
  /// [HomeWidgetState.pendingAction], which the listener widget acts on and then
  /// clears — the bloc names the destination but never navigates, because a bloc
  /// that knows about routes is a bloc that cannot be tested without one.
  FutureOr<void> _onWatchHomeWidgetTapsEvent(
    WatchHomeWidgetTapsEvent event,
    Emitter<HomeWidgetState> emit,
  ) async {
    final initial = await repository.initialTap();
    if (initial.success) {
      final action = WidgetAction.fromUri(initial.data as Uri?);
      if (action != null) emit(state.copyWith(pendingAction: action));
    }

    await emit.forEach<Uri?>(
      repository.taps(),
      onData: (uri) {
        final action = WidgetAction.fromUri(uri);
        return action == null ? state : state.copyWith(pendingAction: action);
      },
      onError: (error, stackTrace) => state,
    );
  }

  /// [_onHomeWidgetTapHandled] clears the action once the app has acted on it, so
  /// a rebuild cannot open the same sheet twice.
  FutureOr<void> _onHomeWidgetTapHandled(
    HomeWidgetTapHandled event,
    Emitter<HomeWidgetState> emit,
  ) {
    emit(state.copyWith(clearPendingAction: true));
  }

  /// [_queueSync] asks for exactly one publish per burst.
  ///
  /// `onData` cannot await, so the work is queued as an event rather than done
  /// inline — the same reason `TasksBloc` queues its reschedule.
  void _queueSync() {
    if (_syncPending) return;
    _syncPending = true;
    add(const SyncHomeWidgetEvent());
  }

  FutureOr<void> _onSyncHomeWidgetEvent(
    SyncHomeWidgetEvent event,
    Emitter<HomeWidgetState> emit,
  ) async {
    // Cleared before the payload is built, so a write landing during the async
    // push below queues a fresh sync rather than being swallowed.
    _syncPending = false;

    // Nothing is known about the user's choice until Settings has spoken.
    // Publishing against the default first would put task titles into an
    // unencrypted container belonging to a user who had switched the widgets
    // off — briefly, and then withdraw them, which is not a defence.
    final isEnabled = state.isEnabled;
    if (isEnabled == null) return;

    if (!isEnabled) return;

    try {
      final now = DateTime.now();

      final payload = HomeWidgetPayload.build(
        tasks: state.tasks,
        expenseMinor: state.expenseMinorFor(now),
        now: now,
      );

      // Unchanged data is a redraw the home screen does not need. The widget is
      // republished on every write in the app, and most writes touch neither
      // today's tasks nor this month's spend.
      if (payload == state.payload) return;

      final response = await repository.push(payload);

      emit(
        response.success
            ? state.copyWith(payload: payload, error: '')
            : state.copyWith(error: response.message),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not update the home screen widgets.'));
    }
  }

  /// [_onConfigureHomeWidgetEvent] applies the user's switch.
  ///
  /// Turning them off clears the shared container rather than merely stopping
  /// future publishes: the point of the switch is that the data leaves the
  /// unencrypted store, not that it stops being refreshed.
  FutureOr<void> _onConfigureHomeWidgetEvent(
    ConfigureHomeWidgetEvent event,
    Emitter<HomeWidgetState> emit,
  ) async {
    final wasEnabled = state.isEnabled;
    emit(state.copyWith(isEnabled: event.isEnabled));

    if (event.isEnabled) {
      // Publish now rather than waiting for the next write: a user who has just
      // switched the widgets on is looking at their home screen.
      add(const SyncHomeWidgetEvent());
      return;
    }

    // Only when it is a change: `SettingsBloc` republishes its whole
    // configuration on every settings change, so an untouched "off" would
    // otherwise clear the container on every unrelated toggle.
    if (wasEnabled == false) return;

    try {
      final response = await repository.clear();
      emit(
        response.success
            ? state.copyWith(clearPayload: true, error: '')
            : state.copyWith(error: response.message),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not clear the home screen widgets.'));
    }
  }
}
