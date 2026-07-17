import 'package:bloc_test/bloc_test.dart';
import 'package:everything_app/bloc/budget/budget_bloc.dart';
import 'package:everything_app/bloc/finance/finance_bloc.dart';
import 'package:everything_app/data/models/account.dart';
import 'package:everything_app/data/models/budget.dart';
import 'package:everything_app/data/models/transaction.dart';
import 'package:everything_app/view/screens/finance/finance_page.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

/// Every figure on the Finance dashboard is derived from one list of transactions
/// — the ring and its legend, the budget strip, the three totals, the six-month
/// trend, the preview — and the screen's whole claim is that no two of them can
/// disagree. It is also where the two blocs meet: the spend comes from
/// [FinanceBloc] while the limit comes from [BudgetBloc], and the strip looks the
/// limit up by the *selected* month rather than the month [BudgetBloc] happens to
/// be tracking.
///
/// A golden is the only thing that checks the assembled arithmetic. The fixture
/// is deliberately an over-budget month: ₹52,000 spent against a ₹45,000 limit,
/// so the strip renders its exceeded state and 'Saved' goes red and negative.
void main() {
  final month = DateTime(2026, 1);

  const accounts = [
    Account(id: 'a1', name: 'HDFC', type: AccountType.bank),
    Account(id: 'a2', name: 'Cash', type: AccountType.cash),
  ];

  Transaction expense({
    required String id,
    required String title,
    required int amountMinor,
    required String category,
    required int day,
    String accountId = 'a1',
  }) =>
      Transaction(
        id: id,
        title: title,
        amountMinor: amountMinor,
        date: DateTime(2026, 1, day, 12),
        accountId: accountId,
        category: category,
        createdAt: DateTime(2026, 1, day, 12),
      );

  final state = FinanceState(
    selectedMonth: month,
    accounts: accounts,
    transactions: [
      Transaction(
        id: 'i1',
        title: 'January salary',
        amountMinor: 4000000,
        date: DateTime(2026, 1, 1, 9),
        accountId: 'a1',
        type: TransactionType.income,
        category: 'Salary',
        createdAt: DateTime(2026, 1, 1, 9),
      ),
      expense(
        id: 'e1',
        title: 'Rent',
        amountMinor: 2500000,
        category: 'Bills',
        day: 2,
      ),
      expense(
        id: 'e2',
        title: 'Groceries',
        amountMinor: 1200000,
        category: 'Food',
        day: 6,
        accountId: 'a2',
      ),
      expense(
        id: 'e3',
        title: 'Flight to Delhi',
        amountMinor: 900000,
        category: 'Travel',
        day: 9,
      ),
      expense(
        id: 'e4',
        title: 'Winter jacket',
        amountMinor: 450000,
        category: 'Shopping',
        day: 11,
      ),
      expense(
        id: 'e5',
        title: 'Cinema',
        amountMinor: 150000,
        category: 'Entertainment',
        day: 14,
      ),
      // Investments are excluded from "spent" — a month that saved well must not
      // be told it overspent.
      Transaction(
        id: 'v1',
        title: 'Index fund SIP',
        amountMinor: 1000000,
        date: DateTime(2026, 1, 5, 10),
        accountId: 'a1',
        type: TransactionType.investment,
        category: 'Investment',
        createdAt: DateTime(2026, 1, 5, 10),
      ),
      // Earlier months, so the six-month trend is a line rather than a flat run
      // of zeroes ending in one spike.
      for (final (offset, spent) in const [(1, 3800000), (2, 4400000), (3, 3100000), (4, 3600000), (5, 2900000)])
        Transaction(
          id: 'p$offset',
          title: 'Living costs',
          amountMinor: spent,
          date: DateTime(2026, 1 - offset, 15, 12),
          accountId: 'a1',
          category: 'Bills',
          createdAt: DateTime(2026, 1 - offset, 15, 12),
        ),
      for (final offset in const [1, 2, 3, 4, 5])
        Transaction(
          id: 'ps$offset',
          title: 'Salary',
          amountMinor: 4000000,
          date: DateTime(2026, 1 - offset, 1, 9),
          accountId: 'a1',
          type: TransactionType.income,
          category: 'Salary',
          createdAt: DateTime(2026, 1 - offset, 1, 9),
        ),
    ],
  );

  const budget = BudgetState(
    month: 1,
    year: 2026,
    budgets: [
      Budget(
        id: 'b1',
        monthlyLimitMinor: 4500000,
        month: 1,
        year: 2026,
      ),
    ],
  );

  testWidgets('the Finance dashboard renders an over-budget month',
      (tester) async {
    await freeze(() async {
      final financeBloc = MockFinanceBloc();
      final budgetBloc = MockBudgetBloc();

      whenListen(financeBloc, const Stream<FinanceState>.empty(),
          initialState: state);
      whenListen(budgetBloc, const Stream<BudgetState>.empty(),
          initialState: budget);

      await pumpGolden(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider<FinanceBloc>.value(value: financeBloc),
            BlocProvider<BudgetBloc>.value(value: budgetBloc),
          ],
          child: const FinancePage(),
        ),
      );

      expect(find.text('January 2026'), findsOneWidget,
          reason: 'the selected month drives the header, not the real one');
      // ₹52,000 of expenses: the investment and the earlier months are excluded.
      expect(state.expenseMinor, 5200000);
      expect(state.savingsMinor, -1200000, reason: 'the month is short');

      await expectLater(
        find.byType(FinancePage),
        matchesGoldenFile('goldens/finance_page.png'),
      );
    });
  });
}
