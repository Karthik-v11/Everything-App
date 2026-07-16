part of 'budget_bloc.dart';

/// [BudgetEvent] is the base class for every Budget event.
abstract class BudgetEvent extends Equatable {
  const BudgetEvent();

  @override
  List<Object?> get props => [];
}

/// [WatchBudgetsEvent] subscribes to the budget stream.
///
/// Dispatched once, at bloc creation. Every later change arrives through the
/// stream rather than through another event.
class WatchBudgetsEvent extends BudgetEvent {
  const WatchBudgetsEvent();
}

/// [SetBudgetEvent] sets a month's limits (Requirements 14.1, 14.2).
/// [budget] carries the monthly limit and any per-category limits.
class SetBudgetEvent extends BudgetEvent {
  const SetBudgetEvent({required this.budget});

  final Budget budget;

  @override
  List<Object?> get props => [budget];
}

/// [UpdateSpendEvent] reports what has been spent in a month.
///
/// Dispatched by [FinanceBloc], which owns the transactions, whenever the list or
/// the selected month changes. It is the only way spending reaches this bloc — a
/// budget cannot read the transactions itself (CLAUDE.md §3.6).
class UpdateSpendEvent extends BudgetEvent {
  const UpdateSpendEvent({
    required this.month,
    required this.year,
    required this.spentMinor,
    required this.spentByCategory,
  });

  final int month;
  final int year;

  /// Total expenses for the month, in minor units.
  final int spentMinor;

  /// Expenses for the month, per category name.
  final Map<String, int> spentByCategory;

  @override
  List<Object?> get props => [month, year, spentMinor, spentByCategory];
}

/// [ConfigureBudgetAlertsEvent] reports the user's notification configuration.
///
/// Dispatched by [SettingsBloc], which owns it. Until it arrives, no budget alert
/// is delivered — the same guard [TasksBloc] applies to reminders.
class ConfigureBudgetAlertsEvent extends BudgetEvent {
  const ConfigureBudgetAlertsEvent({required this.settings});

  final NotificationSettings settings;

  @override
  List<Object?> get props => [settings];
}
