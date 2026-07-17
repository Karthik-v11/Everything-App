import 'dart:async';

import 'package:everything_app/bloc/to_buy/to_buy_bloc.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/data/models/to_buy_item.dart';
import 'package:everything_app/view/screens/library/to_buy_sheet.dart';
import 'package:everything_app/view/widgets/app_choice_chip.dart';
import 'package:everything_app/view/widgets/to_buy_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// One row of the flattened list: the wishlist is two sections and a header, and
/// `ListView.builder` needs a single index space over them.
sealed class _Row {
  const _Row();
}

class _ItemRow extends _Row {
  const _ItemRow(this.item);

  final ToBuyItem item;
}

class _HeaderRow extends _Row {
  const _HeaderRow(this.count);

  final int count;
}

List<_Row> _rowsOf(ToBuyState state) => [
      for (final item in state.pending) _ItemRow(item),
      if (state.purchased.isNotEmpty) ...[
        _HeaderRow(state.purchased.length),
        if (state.showPurchased)
          for (final item in state.purchased) _ItemRow(item),
      ],
    ];

/// [ToBuyPage] is the shopping wishlist (Requirement 7).
class ToBuyPage extends StatefulWidget {
  const ToBuyPage({super.key});

  @override
  State<ToBuyPage> createState() => _ToBuyPageState();
}

class _ToBuyPageState extends State<ToBuyPage> {
  final _search = TextEditingController();

  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(kSearchDebounce, () {
      if (!mounted) return;
      context.read<ToBuyBloc>().add(SearchToBuyEvent(query: query));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('To Buy'),
        actions: [
          IconButton(
            onPressed: () => showToBuySheet(context),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add an item',
                                  color: context.colors.primary,

          ),
        ],
      ),
      body: BlocConsumer<ToBuyBloc, ToBuyState>(
        listenWhen: (previous, current) =>
            previous.error != current.error ||
            previous.message != current.message,
        listener: (context, state) {
          if (state.error.isNotEmpty) {
            context.showSnack(state.error, isError: true);
          } else if (state.message.isNotEmpty) {
            context.showSnack(state.message);
          }
        },
        builder: (context, state) {
          if (state.isLoading && state.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final pending = state.pending;
          final purchased = state.purchased;

          return Column(
            children: [
              Padding(
                padding: responsivePadding(context).copyWith(top: 4, bottom: 8),
                child: TextField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Search item, store or note',
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    isDense: true,
                  ),
                ),
              ),
              if (state.pendingPricedCount > 0)
                Padding(
                  padding: responsivePadding(context),
                  child: _Total(state: state),
                ),
              _Filters(state: state),
              Expanded(
                child: pending.isEmpty && purchased.isEmpty
                    ? _Empty(isFiltered: state.isFiltered)
                    : _ItemList(state: state, rows: _rowsOf(state)),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// [_Total] is what the unbought list would cost.
///
/// It says how many items it is a total *of*, because plenty of things go on a
/// wishlist before their price is known — and a total that quietly ignored them
/// would be a number the user could not act on.
class _Total extends StatelessWidget {
  const _Total({required this.state});

  final ToBuyState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final priced = state.pendingPricedCount;
    final total = state.pending.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              priced == total
                  ? 'Everything on the list'
                  : '$priced of $total items priced',
              style: context.texts.labelSmall,
            ),
          ),
          Text(
            Helpers.formatMoney(state.pendingTotalMinor, compact: true),
            style: context.texts.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.state});

  final ToBuyState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: responsivePadding(context),
        children: [
          for (final priority in TaskPriority.values.reversed) ...[
            AppChoiceChip(
              label: priority.name.capitalized,
              isSelected: state.priority == priority,
              avatarColor: priority.color,
              onSelected: (isSelected) => context.read<ToBuyBloc>().add(
                    FilterToBuyEvent(
                      showPurchased: state.showPurchased,
                      priority: isSelected ? priority : null,
                    ),
                  ),
            ),
            const Gap(8),
          ],
        ],
      ),
    );
  }
}

/// [_BoughtHeader] is the disclosure for the purchased items.
class _ItemList extends StatelessWidget {
  const _ItemList({required this.state, required this.rows});

  final ToBuyState state;
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: responsivePadding(context).copyWith(top: 8, bottom: 120),
      itemCount: rows.length,
      // The bought header gets a wider gap, setting the section apart.
      separatorBuilder: (context, index) =>
          rows[index + 1] is _HeaderRow ? const Gap(16) : const Gap(8),
      itemBuilder: (context, index) {
        final row = rows[index];

        return switch (row) {
          _ItemRow(:final item) => ToBuyCard(
              key: ValueKey(item.id),
              item: item,
              onToggle: (isPurchased) => context.read<ToBuyBloc>().add(
                    ToggleToBuyPurchasedEvent(
                      item: item,
                      isPurchased: isPurchased,
                    ),
                  ),
              onTap: () => showToBuySheet(context, item: item),
            ),
          _HeaderRow(:final count) => _BoughtHeader(
              count: count,
              isExpanded: state.showPurchased,
              onToggle: () => context.read<ToBuyBloc>().add(
                    FilterToBuyEvent(
                      showPurchased: !state.showPurchased,
                      priority: state.priority,
                    ),
                  ),
            ),
        };
      },
    );
  }
}

class _BoughtHeader extends StatelessWidget {
  const _BoughtHeader({
    required this.count,
    required this.isExpanded,
    required this.onToggle,
  });

  final int count;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(
              isExpanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
            const Gap(8),
            Text(
              count == 1 ? '1 bought' : '$count bought',
              style: context.texts.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.isFiltered});

  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isFiltered ? 'Nothing matched' : 'Nothing on the list',
              style: context.texts.titleMedium,
            ),
            const Gap(6),
            Text(
              isFiltered
                  ? 'Try a different search or clear the filters.'
                  : 'Add what you mean to buy, with a price, a store '
                      'and a reminder.',
              textAlign: TextAlign.center,
              style: context.texts.bodySmall,
            ),
            if (!isFiltered) ...[
              const Gap(16),
              FilledButton.icon(
                onPressed: () => showToBuySheet(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add an item'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
