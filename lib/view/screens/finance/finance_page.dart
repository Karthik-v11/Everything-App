import 'package:everything_app/bloc/budget/budget_bloc.dart';
import 'package:everything_app/bloc/finance/finance_bloc.dart';
import 'package:everything_app/core/route/routes.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/budget.dart';
import 'package:everything_app/view/screens/finance/transaction_sheet.dart';
import 'package:everything_app/view/widgets/budget_bar.dart';
import 'package:everything_app/view/widgets/category_donut.dart';
import 'package:everything_app/view/widgets/finance_charts.dart';
import 'package:everything_app/view/widgets/module_app_bar.dart';
import 'package:everything_app/view/widgets/month_selector.dart';
import 'package:everything_app/view/widgets/transaction_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// How many transactions the dashboard previews before "See All".
const int _kPreviewCount = 5;

/// [FinancePage] is the Finance dashboard (Requirements 12–14).
///
/// One question per block, in the order they are asked: what went out this month
/// and on what (the ring), how that sits against the budget, what came in and what
/// was kept, how the month compares to the ones before it, and what the month is
/// actually made of.
///
/// There is one chart besides the ring. The bar chart that used to sit behind a
/// toggle beside the trend line answered the same question the trend line and the
/// totals row already answer, and a screen that says a thing three times is a
/// screen the user has to read three times to be sure it isn't saying something
/// new.
///
/// Two blocs feed it, and neither could do the job alone: [FinanceBloc] owns the
/// transactions and therefore every total, and [BudgetBloc] owns the limits and
/// therefore the strip. Their only contact is [FinanceBloc] pushing the month's
/// spending across — the screen is where the two are put side by side, which is
/// the only place they belong together.
class FinancePage extends StatelessWidget {
  const FinancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: BlocConsumer<FinanceBloc, FinanceState>(
        listenWhen: (previous, current) => previous.error != current.error,
        listener: (context, state) {
          if (state.error.isNotEmpty) {
            context.showSnack(state.error, isError: true);
          }
        },
        // Every block on this screen — the ring, the totals, the trend, the
        // preview — is derived from the month's transactions, the accounts, the
        // selected month and the highlighted category. The search query, the
        // type/account filters and the transient message belong to the
        // transactions route pushed on top of this one; a keystroke there must
        // not re-run this page's six derivations and re-animate both charts.
        buildWhen: (previous, current) =>
            previous.transactions != current.transactions ||
            previous.accounts != current.accounts ||
            previous.selectedMonth != current.selectedMonth ||
            previous.category != current.category ||
            previous.isLoading != current.isLoading,
        builder: (context, state) {
          final isEmpty = state.isLoading && state.transactions.isEmpty;

          return Column(
            children: [
              // Outside the list, so the header stays put while the month scrolls
              // under it — and so it is still there during the first load, which
              // is what the other three tabs do.
              Padding(
                padding: responsivePadding(context),
                child: _Header(
                  month: state.selectedMonth,
                  onMonthChanged: (month) => context.read<FinanceBloc>().add(
                        SelectMonthEvent(month: month),
                      ),
                ),
              ),
              if (isEmpty)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else
                Expanded(child: _Body(state: state)),
            ],
          );
        },
      ),
    );
  }
}

/// [_Body] is everything under the header: the month, block by block.
class _Body extends StatelessWidget {
  const _Body({required this.state});

  final FinanceState state;

  /// [_openCategory] shows the transactions behind a slice of the ring
  /// (Requirement 13.3).
  void _openCategory(BuildContext context, String category) {
    context.read<FinanceBloc>().add(
          FilterTransactionsEvent(category: category),
        );
    context.pushNamed(transactionsRoute);
  }

  void _openTransactions(BuildContext context) {
    // Any filter left over from a chart tap would silently narrow a list the user
    // asked to see all of.
    context.read<FinanceBloc>().add(const FilterTransactionsEvent());
    context.pushNamed(transactionsRoute);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: responsivePadding(context).copyWith(bottom: 140),
      children: [
        const Gap(8),
        _SpendCard(
          state: state,
          onSelectCategory: (category) => _openCategory(context, category),
        ),
        const Gap(12),
        _BudgetStrip(state: state),
        const Gap(12),
        _Totals(state: state),
        const Gap(12),
        _TransactionsSection(
          state: state,
          onSeeAll: () => _openTransactions(context),
        ),
        const Gap(16),

                _TrendSection(state: state),
                                const Gap(28),
                        _NavRow(
          icon: Icons.pie_chart_outline_rounded,
          label: 'Budgets',
          onTap: () => context.pushNamed(budgetsRoute),
        ),
        _NavRow(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Accounts',
          onTap: () => context.pushNamed(accountsRoute),
        ),


      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.month, required this.onMonthChanged});

  final DateTime month;
  final ValueChanged<DateTime> onMonthChanged;

  @override
  Widget build(BuildContext context) {
    return ModuleAppBar(
      title: 'Finance',
      actions: [
        MonthSelector(month: month, onChanged: onMonthChanged),
        IconButton(
          onPressed: () => showTransactionSheet(context),
          icon: const Icon(Icons.add_rounded),
          color: context.colors.primary,
          tooltip: 'Add transaction',
        ),
      ],
    );
  }
}

/// [_SpendCard] is the ring, what it adds up to, and the legend beside it.
///
/// The budget used to live along the bottom of this card. It is its own strip now:
/// the two say different things — what was spent, and whether that was too much —
/// and a card that answered both had to shrink each answer to fit.
class _SpendCard extends StatelessWidget {
  const _SpendCard({required this.state, required this.onSelectCategory});

  final FinanceState state;
  final ValueChanged<String> onSelectCategory;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    final spend = state.expenseByCategory;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CategoryDonut(
            spend: spend,
            selected: state.category,
            onSelect: onSelectCategory,
            size: 132,
          ),
          const Gap(20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Spent this month', style: texts.labelSmall),
                const Gap(4),
                Text(
                  Helpers.formatMoney(state.expenseMinor, compact: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: texts.labelLarge?.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const Gap(14),
                CategoryLegend(
                  spend: spend,
                  selected: state.category,
                  onSelect: onSelectCategory,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// [_BudgetStrip] is the month's budget, under the ring it is measured against.
class _BudgetStrip extends StatelessWidget {
  const _BudgetStrip({required this.state});

  final FinanceState state;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BudgetBloc, BudgetState>(
      // The strip's spend comes from [FinanceState]; from [BudgetBloc] it takes
      // only the month's limit. So it rebuilds when the limits change, not on
      // the spend-and-alert emissions FinanceBloc drives into BudgetBloc after
      // every transaction write.
      buildWhen: (previous, current) => previous.budgets != current.budgets,
      builder: (context, budget) {
        // The bar renders the budget for the month *the finance screen* is
        // showing. BudgetBloc tracks whichever month it was last told about, and
        // on the frame after the month is stepped that is still the old one — so
        // the budget is looked up by the selected month here rather than taken
        // from `budget.status`, which would flash the previous month's limit
        // against this month's spending.
        final status = BudgetStatus(
          budget: budget.budgetFor(
            month: state.selectedMonth.month,
            year: state.selectedMonth.year,
          ),
          spentMinor: state.expenseMinor,
          spentByCategory: FinanceState.spendFor(
            state.transactions,
            state.selectedMonth,
          ).byCategory,
        );

        return BudgetBar(
          status: status,
          onTap: () => context.pushNamed(budgetsRoute),
        );
      },
    );
  }
}

/// [_Totals] is the month's income, expense and savings (Requirement 13.1).
///
/// The three are one card rather than three bare columns on the page background:
/// they are a single sentence about the month — this came in, that went out, this
/// is what is left — and the arithmetic between them is only legible if they are
/// visibly one thing. The rules between them carry that; the icons carry the
/// direction, so the numbers do not have to be read to see which way the month
/// went.
///
/// Income is the accent, not a green: the app's [ColorScheme] has no success
/// colour, and `tertiary` — which this used to ask for — is not defined in
/// `AppTheme`, so it silently resolved to the grey of `secondary`.
class _Totals extends StatelessWidget {
  const _Totals({required this.state});

  final FinanceState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final savings = state.savingsMinor;
    final isShort = savings < 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      // The rules are drawn the full height of the tallest cell, which is what
      // IntrinsicHeight is for — a Row alone would give them no height to take.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Total(
                icon: Icons.south_west_rounded,
                label: 'Income',
                amountMinor: state.incomeMinor,
                color: colors.primary,
              ),
            ),
            _TotalsRule(color: colors.outline),
            Expanded(
              child: _Total(
                icon: Icons.north_east_rounded,
                label: 'Spent',
                amountMinor: state.expenseMinor,
                color: colors.error,
              ),
            ),
            _TotalsRule(color: colors.outline),
            Expanded(
              child: _Total(
                // A month that spent more than it earned is the one case worth
                // calling out, so it changes the icon as well as the colour.
                icon: isShort
                    ? Icons.trending_down_rounded
                    : Icons.savings_outlined,
                label: 'Saved',
                amountMinor: savings,
                color: isShort ? colors.error : colors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [_TotalsRule] is the hairline between two totals.
class _TotalsRule extends StatelessWidget {
  const _TotalsRule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: 2),
        color: color,
      );
}

/// [_Total] is one cell of [_Totals]: which way the money moved, what it is
/// called, and how much of it there was.
class _Total extends StatelessWidget {
  const _Total({
    required this.icon,
    required this.label,
    required this.amountMinor,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int amountMinor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    // Centred in its cell, so the three read as columns of a table rather than as
    // three left-aligned blocks drifting away from their rules.
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: color),
            const Gap(5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: texts.labelSmall,
              ),
            ),
          ],
        ),
        const Gap(8),
        Padding(
          // The amount is the widest thing in the cell; this keeps it off the rule
          // when it runs long.
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            Helpers.formatMoney(amountMinor, compact: true),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: texts.labelLarge?.copyWith(
              fontSize: 19,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// [_TrendSection] is the spending trend (Requirement 13.2) — the one chart on the
/// screen besides the ring.
class _TrendSection extends StatelessWidget {
  const _TrendSection({required this.state});

  final FinanceState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Spending', style: context.texts.titleMedium),
        const Gap(2),
        Text(
          'Last $kTrendMonths months',
          style: context.texts.labelSmall,
        ),
        const Gap(16),
        SizedBox(height: 150, child: TrendChart(trend: state.trend)),
      ],
    );
  }
}

class _TransactionsSection extends StatelessWidget {
  const _TransactionsSection({required this.state, required this.onSeeAll});

  final FinanceState state;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final transactions = state.monthTransactions;
    final preview = transactions.take(_kPreviewCount).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'This month',
                style: context.texts.titleMedium,
              ),
            ),
            TextButton(
              onPressed: onSeeAll,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('See All', style: context.texts.labelMedium),
                  const Icon(Icons.chevron_right_rounded, size: 16),
                ],
              ),
            ),
          ],
        ),
        const Gap(4),
        if (preview.isEmpty)
          const _EmptyTransactions()
        else
          for (final transaction in preview)
            TransactionCard(
              transaction: transaction,
              account: state.accountOf(transaction),
              onTap: () =>
                  showTransactionSheet(context, transaction: transaction),
            ),
      ],
    );
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text('Nothing this month', style: context.texts.titleMedium),
          const Gap(6),
          Text(
            'Log what you spend and it shows up here.',
            style: context.texts.bodySmall,
          ),
          const Gap(14),
          FilledButton.icon(
            onPressed: () => showTransactionSheet(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add transaction'),
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.onSurfaceVariant),
            const Gap(12),
            Expanded(child: Text(label, style: context.texts.titleMedium)),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
