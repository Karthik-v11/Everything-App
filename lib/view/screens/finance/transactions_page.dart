import 'dart:async';

import 'package:everything_app/bloc/finance/finance_bloc.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/transaction.dart';
import 'package:everything_app/view/screens/finance/transaction_sheet.dart';
import 'package:everything_app/view/widgets/app_choice_chip.dart';
import 'package:everything_app/view/widgets/month_selector.dart';
import 'package:everything_app/view/widgets/transaction_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [TransactionsPage] is the full transaction list (Requirements 12.1, 12.4).
///
/// It is also where a tapped chart segment lands (Requirement 13.3): the filter is
/// already on the bloc by the time this screen builds, so the list opens narrowed
/// to that category with the chip that says so already selected — and clearing it
/// is the same one tap.
///
/// Rows are grouped by day. A flat list of forty rows dated `12 Jul` over and over
/// is a list nobody reads.
class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  final _search = TextEditingController();

  Timer? _debounce;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();

    // A query left on the bloc from a previous visit would silently narrow the
    // list, so the field and the bloc are re-synced on the way in.
    _search.text = context.read<FinanceBloc>().state.query;
    _isSearching = _search.text.isNotEmpty;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(kSearchDebounce, () {
      if (!mounted) return;
      context.read<FinanceBloc>().add(SearchTransactionsEvent(query: query));
    });
  }

  void _toggleSearch() {
    setState(() => _isSearching = !_isSearching);

    if (!_isSearching) {
      _search.clear();
      context.read<FinanceBloc>().add(const SearchTransactionsEvent(query: ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            onPressed: _toggleSearch,
            icon: Icon(
              _isSearching ? Icons.close_rounded : Icons.search_rounded,
            ),
            tooltip: _isSearching ? 'Close search' : 'Search transactions',
          ),
          IconButton(
            onPressed: () => showTransactionSheet(context),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add transaction',
                                  color: context.colors.primary,

          ),
        ],
      ),
      body: BlocConsumer<FinanceBloc, FinanceState>(
        listenWhen: (previous, current) => previous.error != current.error,
        listener: (context, state) {
          if (state.error.isNotEmpty) {
            context.showSnack(state.error, isError: true);
          }
        },
        builder: (context, state) {
          final groups = _groupByDay(state.visibleTransactions);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isSearching)
                Padding(
                  padding: responsivePadding(context),
                  child: TextField(
                    controller: _search,
                    autofocus: true,
                    onChanged: _onQueryChanged,
                    decoration: const InputDecoration(
                      hintText: 'Search title, category, tags…',
                      isDense: true,
                    ),
                  ),
                ),
              Padding(
                padding: responsivePadding(context),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${state.visibleTransactions.length} '
                        '${state.visibleTransactions.length == 1 ? 'entry' : 'entries'}',
                        style: context.texts.labelSmall,
                      ),
                    ),
                    MonthSelector(
                      month: state.selectedMonth,
                      onChanged: (month) => context.read<FinanceBloc>().add(
                            SelectMonthEvent(month: month),
                          ),
                    ),
                  ],
                ),
              ),
              _FilterRow(state: state),
              Expanded(
                child: groups.isEmpty
                    ? _EmptyState(isFiltered: state.isFiltered)
                    : ListView.builder(
                        padding: responsivePadding(context)
                            .copyWith(bottom: 120, top: 4),
                        itemCount: groups.length,
                        itemBuilder: (context, index) => _DayGroup(
                          group: groups[index],
                          state: state,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// [_groupByDay] splits the list into day sections. The list arrives newest
  /// first, so the sections come out in that order without a second sort.
  List<_DayTransactions> _groupByDay(List<Transaction> transactions) {
    final groups = <_DayTransactions>[];

    for (final transaction in transactions) {
      final day = transaction.date.dateOnly;

      if (groups.isNotEmpty && groups.last.day == day) {
        groups.last.transactions.add(transaction);
        continue;
      }

      groups.add(_DayTransactions(day: day, transactions: [transaction]));
    }

    return groups;
  }
}

class _DayTransactions {
  _DayTransactions({required this.day, required this.transactions});

  final DateTime day;
  final List<Transaction> transactions;

  /// What the day cost, net: income in, expenses out. It is the figure that makes
  /// the header worth having.
  int get netMinor {
    var total = 0;
    for (final transaction in transactions) {
      total += transaction.signedMinor;
    }
    return total;
  }
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({required this.group, required this.state});

  final _DayTransactions group;
  final FinanceState state;

  @override
  Widget build(BuildContext context) {
    final net = group.netMinor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  group.day.relativeLabel,
                  style: context.texts.labelMedium,
                ),
              ),
              Text(
                '${net >= 0 ? '+' : '-'}'
                '${Helpers.formatMoney(net.abs(), compact: true)}',
                style: context.texts.labelSmall,
              ),
            ],
          ),
        ),
        for (final transaction in group.transactions)
          Dismissible(
            key: ValueKey(transaction.id),
            direction: DismissDirection.endToStart,
            background: ColoredBox(
              color: context.colors.error,
              child: const Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            onDismissed: (_) => context.read<FinanceBloc>().add(
                  DeleteTransactionEvent(id: transaction.id),
                ),
            child: TransactionCard(
              transaction: transaction,
              account: state.accountOf(transaction),
              onTap: () =>
                  showTransactionSheet(context, transaction: transaction),
            ),
          ),
      ],
    );
  }
}

/// [_FilterRow] is the type and category narrowing.
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.state});

  final FinanceState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: responsivePadding(context),
        children: [
          Center(
            child: AppChoiceChip(
              label: 'All',
              isSelected: state.type == null && state.category == null,
              onSelected: (_) => context.read<FinanceBloc>().add(
                    const FilterTransactionsEvent(),
                  ),
            ),
          ),
          for (final type in TransactionType.values) ...[
            const Gap(8),
            Center(
              child: AppChoiceChip(
                label: type.label,
                isSelected: state.type == type,
                onSelected: (isSelected) => context.read<FinanceBloc>().add(
                      FilterTransactionsEvent(
                        // Selecting the type already selected clears it, so the
                        // chip is its own off switch.
                        type: isSelected ? type : null,
                        category: state.category,
                      ),
                    ),
              ),
            ),
          ],
          if (state.category != null) ...[
            const Gap(8),
            Center(
              child: AppChoiceChip(
                label: state.category!,
                isSelected: true,
                avatarColor: categoryColor(state.category!),
                onSelected: (_) => context.read<FinanceBloc>().add(
                      FilterTransactionsEvent(type: state.type),
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isFiltered});

  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: responsivePadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFiltered
                  ? Icons.filter_alt_off_rounded
                  : Icons.receipt_long_rounded,
              size: 40,
              color: context.colors.onSurfaceVariant,
            ),
            const Gap(12),
            Text(
              isFiltered ? 'Nothing matches' : 'Nothing this month',
              style: context.texts.titleMedium,
            ),
            const Gap(6),
            Text(
              isFiltered
                  ? 'Try a different filter or search.'
                  : 'Log what you spend and it shows up here.',
              style: context.texts.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (!isFiltered) ...[
              const Gap(16),
              FilledButton.icon(
                onPressed: () => showTransactionSheet(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add transaction'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
