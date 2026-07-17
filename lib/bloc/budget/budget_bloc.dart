import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/data/models/budget.dart';
import 'package:everything_app/data/models/notification_settings.dart';
import 'package:everything_app/data/models/scheduled_notification.dart';
import 'package:everything_app/data/repositories/finance_repository.dart';
import 'package:everything_app/data/repositories/notifications_repository.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'budget_event.dart';
part 'budget_state.dart';

/// [BudgetBloc] owns the monthly budget and its alerts (Requirement 14).
///
/// [FinanceBloc] owns the transactions and pushes the month's totals here via
/// [UpdateSpendEvent] — event dispatch, never a cross-bloc state read
/// (CLAUDE.md §3.6).
///
/// Alerts (Requirements 14.3–14.5) are delivered immediately rather than
/// scheduled: they describe something that has already happened, so
/// [NotificationPlan] does not know about them and reconciliation never sees
/// them. [BudgetState.announced] is hydrated to track what was already
/// delivered — without it, every write in a month already over budget would
/// re-fire the same notification.
class BudgetBloc extends HydratedBloc<BudgetEvent, BudgetState> {
  BudgetBloc({
    required this.repository,
    required this.notificationsRepository,
  }) : super(BudgetState.initial()) {
    on<WatchBudgetsEvent>(_onWatchBudgetsEvent);
    on<SetBudgetEvent>(_onSetBudgetEvent);
    on<UpdateSpendEvent>(_onUpdateSpendEvent);
    on<ConfigureBudgetAlertsEvent>(_onConfigureBudgetAlertsEvent);
  }

  final FinanceRepository repository;
  final NotificationsRepository notificationsRepository;

  FutureOr<void> _onWatchBudgetsEvent(
    WatchBudgetsEvent event,
    Emitter<BudgetState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: '', message: ''));

    await emit.forEach<List<Budget>>(
      repository.watchBudgets(),
      onData: (budgets) => state.copyWith(
        isLoading: false,
        budgets: budgets,
        error: '',
      ),
      onError: (_, _) => state.copyWith(
        isLoading: false,
        error: 'Could not load your budget.',
      ),
    );
  }

  /// [_onSetBudgetEvent] saves a month's limits.
  ///
  /// The alerts are re-evaluated afterwards against the spending already recorded,
  /// so lowering a limit below what has been spent announces it at once rather
  /// than waiting for the next transaction to notice.
  FutureOr<void> _onSetBudgetEvent(
    SetBudgetEvent event,
    Emitter<BudgetState> emit,
  ) async {
    try {
      emit(state.copyWith(isLoading: true, error: '', message: ''));

      final response = await repository.saveBudget(event.budget);

      if (!response.success) {
        emit(state.copyWith(isLoading: false, error: response.message));
        return;
      }

      // The budget list itself arrives through the stream; only the outcome is
      // emitted here.
      emit(state.copyWith(isLoading: false, message: response.message));

      await _announce(emit, budget: response.data! as Budget);
    } on Exception {
      emit(
        state.copyWith(isLoading: false, error: 'Could not save your budget.'),
      );
    }
  }

  /// [_onUpdateSpendEvent] takes the month's expenses from [FinanceBloc] and
  /// re-evaluates the alerts.
  FutureOr<void> _onUpdateSpendEvent(
    UpdateSpendEvent event,
    Emitter<BudgetState> emit,
  ) async {
    emit(
      state.copyWith(
        month: event.month,
        year: event.year,
        spentMinor: event.spentMinor,
        spentByCategory: event.spentByCategory,
      ),
    );

    await _announce(emit);
  }

  FutureOr<void> _onConfigureBudgetAlertsEvent(
    ConfigureBudgetAlertsEvent event,
    Emitter<BudgetState> emit,
  ) async {
    if (event.settings == state.notifications) return;

    emit(state.copyWith(notifications: event.settings));

    await _announce(emit);
  }

  /// [_announce] delivers every alert that has escalated since the last delivery
  /// (80% then 100% crossings only — never re-announced while already over), and
  /// forgets alerts that no longer hold so they can fire again later.
  ///
  /// [budget] overrides the one in state when the stream has not yet delivered a
  /// budget that was saved a moment ago.
  Future<void> _announce(Emitter<BudgetState> emit, {Budget? budget}) async {
    final settings = state.notifications;

    // Nothing is delivered until Settings reports the user's configuration:
    // falling back to defaults would notify a user who turned notifications off.
    if (settings == null) return;

    final status = budget == null
        ? state.status
        : BudgetState.statusFor(
            budget: budget,
            spentMinor: state.spentMinor,
            spentByCategory: state.spentByCategory,
          );

    final alerts = status.alerts;
    final announced = <String, BudgetAlertLevel>{};

    for (final alert in alerts) {
      final key = alert.key(state.year, state.month);
      announced[key] = alert.level;

      final delivered = state.announced[key] ?? BudgetAlertLevel.none;
      if (!alert.level.isAbove(delivered)) continue;
      if (!settings.allows(alert.kind)) continue;

      // Keyed on what the alert is *about*, not on its level, so a budget that
      // goes on to be exceeded replaces its own warning in the tray instead of
      // sitting beside it.
      await notificationsRepository.show(
        id: ScheduledNotification.idFor('budget:$key'),
        kind: alert.kind,
        title: alert.title,
        body: alert.body,
      );
    }

    // Replace only the tracked month's keys; other months are carried over
    // untouched since this evaluation says nothing about them.
    final period = '${state.year}-${state.month.toString().padLeft(2, '0')}';

    emit(
      state.copyWith(
        announced: {
          for (final entry in state.announced.entries)
            if (!entry.key.startsWith('$period:')) entry.key: entry.value,
          ...announced,
        },
      ),
    );
  }

  /// Only [BudgetState.announced] is persisted. Budgets come from the database
  /// stream, and the spending is pushed by [FinanceBloc] on every launch.
  @override
  BudgetState? fromJson(Map<String, dynamic> json) => BudgetState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(BudgetState state) => state.toJson();
}
