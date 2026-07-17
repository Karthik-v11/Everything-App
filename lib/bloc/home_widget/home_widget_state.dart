part of 'home_widget_bloc.dart';

/// [HomeWidgetState] is what the home screen widgets are built from
/// (Requirement 13).
///
/// Not hydrated: everything here mirrors the database, which is already
/// persisted. [isEnabled] is persisted by [SettingsBloc], which owns it and
/// pushes it here.
class HomeWidgetState extends Equatable {
  const HomeWidgetState({
    this.error = '',
    this.tasks = const <Task>[],
    this.transactions = const <Transaction>[],
    this.isEnabled,
    this.payload,
    this.pendingAction,
  });

  final String error;

  final List<Task> tasks;
  final List<Transaction> transactions;

  /// Whether the user wants widgets at all. Null until [SettingsBloc] says, and
  /// nothing is published while null — a default of either value would guess
  /// wrong for half the users.
  final bool? isEnabled;

  /// The last payload actually published, so an unchanged rebuild can skip the
  /// platform call.
  final HomeWidgetPayload? payload;

  /// Where a widget tap wants to go, until the app has taken it there. The bloc
  /// names the destination; the listener navigates, so the bloc stays testable
  /// without a router.
  final WidgetAction? pendingAction;

  /// [expenseMinorFor] is what was spent in [month] — the figure on the finance
  /// widget. Callers must pass the current month, never
  /// `FinanceBloc.selectedMonth`: the widget has no month selector, so it is
  /// always about now.
  int expenseMinorFor(DateTime month) {
    var total = 0;
    for (final transaction in transactions) {
      if (transaction.type != TransactionType.expense) continue;
      if (transaction.date.month != month.month) continue;
      if (transaction.date.year != month.year) continue;
      total += transaction.amountMinor;
    }
    return total;
  }

  HomeWidgetState copyWith({
    String? error,
    List<Task>? tasks,
    List<Transaction>? transactions,
    bool? isEnabled,
    HomeWidgetPayload? payload,
    bool clearPayload = false,
    WidgetAction? pendingAction,
    bool clearPendingAction = false,
  }) =>
      HomeWidgetState(
        error: error ?? this.error,
        tasks: tasks ?? this.tasks,
        transactions: transactions ?? this.transactions,
        isEnabled: isEnabled ?? this.isEnabled,
        payload: clearPayload ? null : (payload ?? this.payload),
        pendingAction:
            clearPendingAction ? null : (pendingAction ?? this.pendingAction),
      );

  @override
  List<Object?> get props =>
      [error, tasks, transactions, isEnabled, payload, pendingAction];
}
