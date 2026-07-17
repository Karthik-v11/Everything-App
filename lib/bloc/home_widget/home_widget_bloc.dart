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
/// It watches the same DAO streams every screen reads, so any write anywhere in
/// the app republishes the payload with no push call at the write site.
///
/// It reads repositories, not other blocs (CLAUDE.md §4.4), which is what lets
/// it project tasks and finance onto one surface when neither module owns the
/// other. [SettingsBloc] owns the on/off switch and pushes it via
/// [ConfigureHomeWidgetEvent]; off empties the shared container rather than
/// merely stopping publishes.
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

  /// Coalesces a burst of writes into one publish: a restore or recurrence
  /// rollover can write a hundred rows, and the home screen needs only the end
  /// state.
  bool _syncPending = false;

  FutureOr<void> _onWatchHomeWidgetEvent(
    WatchHomeWidgetEvent event,
    Emitter<HomeWidgetState> emit,
  ) async {
    await repository.initialize();

    // Separate events so each stream gets its own handler and emitter; launch
    // stays a single dispatch.
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

  /// [_onWatchHomeWidgetTapsEvent] wires both tap paths: a cold-start tap via
  /// [HomeWidgetRepository.initialTap] and a warm one on the stream. Both land in
  /// [HomeWidgetState.pendingAction]; the listener widget navigates and clears it.
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

  /// [_queueSync] asks for exactly one publish per burst. Queued as an event
  /// because `onData` cannot await.
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

    // Null until Settings reports the switch: defaulting would publish task
    // titles to an unencrypted container belonging to a user who turned widgets
    // off.
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

      // Every write in the app reaches here, but most touch neither today's
      // tasks nor this month's spend; skip the platform call when unchanged.
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

  /// [_onConfigureHomeWidgetEvent] applies the user's switch. Off clears the
  /// shared container — the point is that the data leaves the unencrypted store,
  /// not that it stops being refreshed.
  FutureOr<void> _onConfigureHomeWidgetEvent(
    ConfigureHomeWidgetEvent event,
    Emitter<HomeWidgetState> emit,
  ) async {
    final wasEnabled = state.isEnabled;
    emit(state.copyWith(isEnabled: event.isEnabled));

    if (event.isEnabled) {
      // Publish now rather than on the next write — the user is looking at their
      // home screen.
      add(const SyncHomeWidgetEvent());
      return;
    }

    // `SettingsBloc` republishes its whole configuration on every change, so
    // clear only on an actual on→off transition.
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
