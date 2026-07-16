part of 'home_widget_bloc.dart';

/// [HomeWidgetState] is what the home screen widgets are built from
/// (Requirement 13).
///
/// Style A: it accumulates two independent slices — the task list and the
/// transaction list — that arrive on separate streams and are projected together.
///
/// It is **not** hydrated. Everything here is a mirror of the database, which is
/// itself persisted; a second copy would be one more thing that can disagree with
/// it. [isEnabled] is the user's setting and is persisted by [SettingsBloc],
/// which owns it and pushes it here.
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

  /// Whether the user wants widgets at all.
  ///
  /// **Null until [SettingsBloc] says**, which is a third state that matters:
  /// `false` would be a guess, and a guess of `false` publishes nothing to a user
  /// who wants widgets, while a guess of `true` puts task titles into an
  /// unencrypted container belonging to a user who does not. Null means "not yet
  /// told", and nothing is published in that state.
  final bool? isEnabled;

  /// The last payload actually published, so an unchanged rebuild can skip the
  /// platform call.
  final HomeWidgetPayload? payload;

  /// Where a widget tap wants to go, until the app has taken it there.
  ///
  /// The bloc names the destination and the listener navigates: a bloc that knows
  /// about routes cannot be tested without a router, and this one is otherwise
  /// pure enough to test with two fake streams.
  final WidgetAction? pendingAction;

  /// [expenseMinorFor] is what was spent in [month] — the figure on the finance
  /// widget.
  ///
  /// Always *this* month, never a selected one: a home screen widget has no
  /// month selector, so it is always about now. `FinanceBloc.selectedMonth` is
  /// wherever the user last scrolled the Finance tab to, and reading that here
  /// would put February's spending on the home screen because someone was
  /// browsing February.
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
