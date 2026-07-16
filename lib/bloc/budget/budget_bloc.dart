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
/// Style A: it holds the budgets, the month being tracked, and what has been
/// spent against it.
///
/// It is deliberately **not** the owner of the transactions. [FinanceBloc] holds
/// those, and pushes the month's totals here with [UpdateSpendEvent] — an event
/// dispatch, never a cross-bloc state read (CLAUDE.md §3.6). The same shape as
/// Settings → Tasks in Phase 4, and for the same reason: neither bloc alone knows
/// enough to decide anything. Spending without a limit is a number, a limit
/// without spending is a wish.
///
/// The alerts (Requirements 14.3–14.5) are delivered from here rather than
/// scheduled, because unlike every notification in Phase 4 they are about
/// something that has *already* happened: the transaction the user just saved is
/// what made them true. There is no future moment to plan them into, so
/// [NotificationPlan] does not know about them and reconciliation never sees them.
///
/// That leaves this bloc holding the one thing the OS queue cannot: whether an
/// alert has already been delivered. [BudgetState.announced] is that memory, and
/// it is hydrated — without it, every write in a month already over budget would
/// fire the same notification again.
///
/// Events:
/// 1) [WatchBudgetsEvent] — subscribe to the budget stream. Fired once at start.
/// 2) [SetBudgetEvent] — set a month's limits (Requirements 14.1, 14.2).
/// 3) [UpdateSpendEvent] — the month's expenses, pushed by [FinanceBloc].
/// 4) [ConfigureBudgetAlertsEvent] — the notification settings, pushed by
///    [SettingsBloc].
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

  /// [_announce] delivers every alert that has escalated since the last time it
  /// was delivered, and forgets the ones that no longer hold.
  ///
  /// Escalation is the whole rule. An alert is news the first time a budget
  /// crosses 80%, and again when it crosses 100% — but a fifth transaction in a
  /// month that was already over budget is not news, and re-announcing it is how
  /// an app gets its notifications switched off. Equally, a budget the user then
  /// *raises* back out of trouble drops out of [BudgetState.announced], so if
  /// spending climbs into it again it is announced again.
  ///
  /// [budget] overrides the one in state for the case where the stream has not yet
  /// delivered a budget that was saved a moment ago.
  Future<void> _announce(Emitter<BudgetState> emit, {Budget? budget}) async {
    final settings = state.notifications;

    // Nothing is delivered until Settings has reported the user's configuration —
    // the same guard as TasksBloc, and for the same reason: scheduling against
    // the defaults would notify a user who had turned notifications off.
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

    // Every key for the tracked month is replaced by what the evaluation just
    // found — an alert that no longer holds is *forgotten*, so that spending
    // climbing back into it later is announced again. Other months are carried
    // over untouched: this evaluation says nothing about a month it was not about.
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
