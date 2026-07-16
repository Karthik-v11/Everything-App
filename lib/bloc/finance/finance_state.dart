part of 'finance_bloc.dart';

/// How many months the trend chart looks back over, the selected month included.
const int kTrendMonths = 6;

/// [CategorySpend] is one slice of the donut: a category and what it took
/// (Requirement 13.2).
class CategorySpend extends Equatable {
  const CategorySpend({
    required this.category,
    required this.amountMinor,
    required this.share,
  });

  final String category;
  final int amountMinor;

  /// The 0–1 share of the month's expenses, which is the slice's angle.
  final double share;

  Color get color => categoryColor(category);

  @override
  List<Object?> get props => [category, amountMinor, share];
}

/// [MonthTotals] is one column of the trend and bar charts.
class MonthTotals extends Equatable {
  const MonthTotals({
    required this.month,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  final DateTime month;
  final int incomeMinor;
  final int expenseMinor;

  /// What was earned and not spent. Negative in a month that spent more than it
  /// earned, which is exactly what the user needs to see.
  int get savingsMinor => incomeMinor - expenseMinor;

  @override
  List<Object?> get props => [month, incomeMinor, expenseMinor];
}

/// [FinanceState] holds everything the Finance module renders.
///
/// [transactions] is the complete list from the database. **Every** other figure
/// on the screen — the month's totals, the donut, the trend, the account
/// balances, the filtered list — is derived from it here, so changing the month
/// or a filter is a recomputation rather than a database round trip, and no two
/// figures can disagree about what was spent.
class FinanceState extends Equatable {
  const FinanceState({
    required this.selectedMonth,
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.transactions = const <Transaction>[],
    this.accounts = const <Account>[],
    this.type,
    this.category,
    this.accountId,
    this.query = '',
  });

  /// [FinanceState.initial] starts on the current month.
  factory FinanceState.initial() =>
      FinanceState(selectedMonth: DateTime.now().startOfMonth);

  final bool isLoading;
  final String error;
  final String message;
  final List<Transaction> transactions;
  final List<Account> accounts;

  /// The first day of the month every summary figure is about.
  final DateTime selectedMonth;

  final TransactionType? type;
  final String? category;
  final String? accountId;
  final String query;

  // ── The selected month ─────────────────────────────────────────────────────

  /// [monthTransactions] is every transaction dated within [selectedMonth].
  List<Transaction> get monthTransactions => [
        for (final transaction in transactions)
          if (transaction.date.month == selectedMonth.month &&
              transaction.date.year == selectedMonth.year)
            transaction,
      ];

  /// [visibleTransactions] is [monthTransactions] under the active filters and
  /// the search query, newest first.
  List<Transaction> get visibleTransactions {
    final matched = [
      for (final transaction in monthTransactions)
        if (_matches(transaction)) transaction,
    ];

    matched.sort((a, b) => b.date.compareTo(a.date));

    return matched;
  }

  /// [incomeMinor] is the month's income (Requirement 13.1).
  int get incomeMinor => _sum(
        monthTransactions.where((t) => t.type == TransactionType.income),
      );

  /// [expenseMinor] is the month's expenses — the figure the budget is tracked
  /// against (Requirement 14.1) and the one Property 7 is about.
  ///
  /// Investments are excluded: money moved into an investment has not been spent,
  /// and counting it as spending would tell a user who saved well that they
  /// overspent.
  int get expenseMinor => _sum(
        monthTransactions.where((t) => t.type == TransactionType.expense),
      );

  int get investedMinor => _sum(
        monthTransactions.where((t) => t.type == TransactionType.investment),
      );

  /// [savingsMinor] is what was earned and not spent. It is negative in a month
  /// that spent more than it earned, which is exactly what the user needs to see.
  int get savingsMinor => incomeMinor - expenseMinor;

  /// [expenseByCategory] is the month's expenses per category, largest first —
  /// the donut and its legend (Requirement 13.2).
  List<CategorySpend> get expenseByCategory {
    final total = expenseMinor;
    if (total == 0) return const [];

    final byCategory = <String, int>{};
    for (final transaction in monthTransactions) {
      if (!transaction.isExpense) continue;
      byCategory.update(
        transaction.category,
        (amount) => amount + transaction.amountMinor,
        ifAbsent: () => transaction.amountMinor,
      );
    }

    return [
      for (final entry in byCategory.entries)
        CategorySpend(
          category: entry.key,
          amountMinor: entry.value,
          share: entry.value / total,
        ),
    ]..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
  }

  /// [trend] is the last [kTrendMonths] months ending at [selectedMonth], oldest
  /// first — the trend line and the income-versus-expense bars (Requirement 13.2).
  ///
  /// A month with nothing in it is still a column: dropping it would draw a line
  /// straight from March to June and call it continuous.
  List<MonthTotals> get trend {
    final months = [
      for (var offset = kTrendMonths - 1; offset >= 0; offset--)
        DateTime(selectedMonth.year, selectedMonth.month - offset),
    ];

    final income = <DateTime, int>{for (final month in months) month: 0};
    final expense = <DateTime, int>{for (final month in months) month: 0};

    for (final transaction in transactions) {
      final month = transaction.date.startOfMonth;
      if (!income.containsKey(month)) continue;

      if (transaction.type == TransactionType.income) {
        income[month] = income[month]! + transaction.amountMinor;
      } else if (transaction.isExpense) {
        expense[month] = expense[month]! + transaction.amountMinor;
      }
    }

    return [
      for (final month in months)
        MonthTotals(
          month: month,
          incomeMinor: income[month]!,
          expenseMinor: expense[month]!,
        ),
    ];
  }

  /// [totalsFor] is any month's income and expenses, whichever month is selected.
  ///
  /// The Dashboard needs it: it is always about *this* month, while
  /// [selectedMonth] is wherever the user last scrolled the Finance tab to. It
  /// goes through the same summing rule as every other figure here, so the two
  /// screens cannot disagree about what a month cost.
  MonthTotals totalsFor(DateTime month) {
    final dated = [
      for (final transaction in transactions)
        if (transaction.date.month == month.month &&
            transaction.date.year == month.year)
          transaction,
    ];

    return MonthTotals(
      month: month.startOfMonth,
      incomeMinor: _sum(dated.where((t) => t.type == TransactionType.income)),
      expenseMinor: _sum(dated.where((t) => t.type == TransactionType.expense)),
    );
  }

  // ── Accounts ───────────────────────────────────────────────────────────────

  /// [activeAccounts] is the accounts a new transaction may be filed under.
  List<Account> get activeAccounts => [
        for (final account in accounts)
          if (!account.isArchived) account,
      ];

  /// [balanceOf] is an account's balance: its opening balance plus every
  /// transaction ever filed against it.
  ///
  /// Derived rather than stored, so it cannot drift from the transactions that
  /// produced it — a stored running balance needs every write to update two rows,
  /// and one missed update is a number that nothing on the screen can explain.
  int balanceOf(Account account) {
    var balance = account.openingBalanceMinor;

    for (final transaction in transactions) {
      if (transaction.accountId != account.id) continue;
      balance += transaction.signedMinor;
    }

    return balance;
  }

  /// [netWorthMinor] is every active account's balance, together.
  int get netWorthMinor {
    var total = 0;
    for (final account in activeAccounts) {
      total += balanceOf(account);
    }
    return total;
  }

  Account? accountOf(Transaction transaction) {
    for (final account in accounts) {
      if (account.id == transaction.accountId) return account;
    }
    return null;
  }

  // ── Spend, for the budget ──────────────────────────────────────────────────

  /// [spendFor] is a month's expenses, in total and per category.
  ///
  /// Static, and the only figure this bloc hands to [BudgetBloc]. It reads the
  /// same `type == expense` rule as [expenseMinor] — the budget and the summary
  /// must agree on what "spent" means, or the bar will say 80% while the card
  /// says something else.
  static ({int totalMinor, Map<String, int> byCategory}) spendFor(
    List<Transaction> transactions,
    DateTime month,
  ) {
    var total = 0;
    final byCategory = <String, int>{};

    for (final transaction in transactions) {
      if (!transaction.isExpense) continue;
      if (transaction.date.month != month.month) continue;
      if (transaction.date.year != month.year) continue;

      total += transaction.amountMinor;
      byCategory.update(
        transaction.category,
        (amount) => amount + transaction.amountMinor,
        ifAbsent: () => transaction.amountMinor,
      );
    }

    return (totalMinor: total, byCategory: byCategory);
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  bool _matches(Transaction transaction) {
    if (type != null && transaction.type != type) return false;
    if (category != null && transaction.category != category) return false;
    if (accountId != null && transaction.accountId != accountId) return false;
    if (query.isNotBlank && !transaction.matches(query)) return false;
    return true;
  }

  /// [isFiltered] is true when anything is narrowing the list. The empty state
  /// uses it to tell "nothing this month" from "nothing matched".
  bool get isFiltered =>
      type != null ||
      category != null ||
      accountId != null ||
      query.isNotBlank;

  /// [categories] is every category the user has actually used, plus the starter
  /// set — what the pickers and the filters offer.
  List<String> get categories {
    final used = {for (final transaction in transactions) transaction.category};

    return [
      for (final known in kTransactionCategories)
        if (known.name != kDefaultTransactionCategory) known.name,
      ...used.where(
        (category) => !kTransactionCategories.any((k) => k.name == category),
      ),
      kDefaultTransactionCategory,
    ];
  }

  static int _sum(Iterable<Transaction> transactions) {
    var total = 0;
    for (final transaction in transactions) {
      total += transaction.amountMinor;
    }
    return total;
  }

  FinanceState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    List<Transaction>? transactions,
    List<Account>? accounts,
    DateTime? selectedMonth,
    TransactionType? type,
    bool clearType = false,
    String? category,
    bool clearCategory = false,
    String? accountId,
    bool clearAccountId = false,
    String? query,
  }) =>
      FinanceState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        transactions: transactions ?? this.transactions,
        accounts: accounts ?? this.accounts,
        selectedMonth: selectedMonth ?? this.selectedMonth,
        type: clearType ? null : (type ?? this.type),
        category: clearCategory ? null : (category ?? this.category),
        accountId: clearAccountId ? null : (accountId ?? this.accountId),
        query: query ?? this.query,
      );

  @override
  List<Object?> get props => [
        isLoading,
        error,
        message,
        transactions,
        accounts,
        selectedMonth,
        type,
        category,
        accountId,
        query,
      ];
}
