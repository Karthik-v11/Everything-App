import 'package:everything_app/bloc/budget/budget_bloc.dart';
import 'package:everything_app/bloc/finance/finance_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/budget.dart';
import 'package:everything_app/data/models/transaction.dart';
import 'package:everything_app/view/widgets/budget_bar.dart';
import 'package:everything_app/view/widgets/month_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [BudgetsPage] sets the month's limits and shows what is left of them
/// (Requirements 14.1, 14.2).
///
/// The month it edits is the month the Finance screen is showing — stepping it
/// here steps it there, because a budget the user set while looking at June and a
/// dashboard reporting July would be two screens disagreeing about the same
/// number.
class BudgetsPage extends StatelessWidget {
  const BudgetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: BlocBuilder<FinanceBloc, FinanceState>(
        builder: (context, finance) {
          return BlocConsumer<BudgetBloc, BudgetState>(
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
              final month = finance.selectedMonth;

              final budget = state.budgetFor(
                month: month.month,
                year: month.year,
              );

              final spend = FinanceState.spendFor(finance.transactions, month);

              final status = BudgetStatus(
                budget: budget,
                spentMinor: spend.totalMinor,
                spentByCategory: spend.byCategory,
              );

              return ListView(
                padding: responsivePadding(context).copyWith(bottom: 120),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Limits for the month',
                          style: context.texts.labelMedium,
                        ),
                      ),
                      MonthSelector(
                        month: month,
                        onChanged: (value) => context.read<FinanceBloc>().add(
                              SelectMonthEvent(month: value),
                            ),
                      ),
                    ],
                  ),
                  const Gap(8),
                  if (!status.isSet)
                    _NoBudget(
                      onSet: () => _editMonthlyLimit(
                        context,
                        month: month,
                        budget: budget,
                      ),
                    )
                  else ...[
                    BudgetProgressRow(label: 'Monthly', status: status),
                    const Gap(4),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _editMonthlyLimit(
                            context,
                            month: month,
                            budget: budget,
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Change limit'),
                        ),
                        const Gap(8),
                        OutlinedButton.icon(
                          onPressed: () => _editCategoryLimit(
                            context,
                            month: month,
                            budget: budget!,
                            categories: finance.categories,
                          ),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Category limit'),
                        ),
                      ],
                    ),
                    const Gap(20),
                    Text('By category', style: context.texts.labelMedium),
                    if (status.categories.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'No category has a limit of its own yet.',
                          style: context.texts.bodySmall,
                        ),
                      )
                    else
                      for (final category in status.categories)
                        Dismissible(
                          key: ValueKey(category.budget!.id),
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
                          onDismissed: (_) => _removeCategoryLimit(
                            context,
                            budget: budget!,
                            category: category.budget!.id,
                          ),
                          child: BudgetProgressRow(
                            // The synthetic budget in [BudgetStatus.categories]
                            // carries the category name as its id.
                            label: category.budget!.id,
                            status: category,
                          ),
                        ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _editMonthlyLimit(
    BuildContext context, {
    required DateTime month,
    required Budget? budget,
  }) async {
    final amountMinor = await _askAmount(
      context,
      title: 'Monthly budget',
      initialMinor: budget?.monthlyLimitMinor,
    );
    if (amountMinor == null || !context.mounted) return;

    context.read<BudgetBloc>().add(
          SetBudgetEvent(
            budget: Budget(
              id: budget?.id ?? '',
              monthlyLimitMinor: amountMinor,
              categoryLimits: budget?.categoryLimits ?? const {},
              month: month.month,
              year: month.year,
            ),
          ),
        );
  }

  Future<void> _editCategoryLimit(
    BuildContext context, {
    required DateTime month,
    required Budget budget,
    required List<String> categories,
  }) async {
    final category = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _CategoryPicker(categories: categories),
    );
    if (category == null || !context.mounted) return;

    final amountMinor = await _askAmount(
      context,
      title: '$category limit',
      initialMinor: budget.categoryLimits[category],
    );
    if (amountMinor == null || !context.mounted) return;

    context.read<BudgetBloc>().add(
          SetBudgetEvent(
            budget: budget.copyWith(
              categoryLimits: {
                ...budget.categoryLimits,
                category: amountMinor,
              },
            ),
          ),
        );
  }

  void _removeCategoryLimit(
    BuildContext context, {
    required Budget budget,
    required String category,
  }) {
    context.read<BudgetBloc>().add(
          SetBudgetEvent(
            budget: budget.copyWith(
              categoryLimits: {
                for (final entry in budget.categoryLimits.entries)
                  if (entry.key != category) entry.key: entry.value,
              },
            ),
          ),
        );
  }

  /// [_askAmount] returns the entered amount in minor units, or null if cancelled.
  Future<int?> _askAmount(
    BuildContext context, {
    required String title,
    int? initialMinor,
  }) {
    return showDialog<int>(
      context: context,
      builder: (_) => _AmountDialog(title: title, initialMinor: initialMinor),
    );
  }
}

/// [_AmountDialog] asks for a money amount and pops with it in minor units.
///
/// The controller is owned by the dialog rather than the caller: the future from
/// [showDialog] completes as soon as the route is popped, while the dialog keeps
/// painting through its exit transition, so disposing on completion would leave
/// the [TextField] holding a dead controller.
class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.title, this.initialMinor});

  final String title;
  final int? initialMinor;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialMinor == null || widget.initialMinor == 0
        ? ''
        : Helpers.toMajorUnits(widget.initialMinor!)
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'\.00$'), ''),
  );

  void _submit(String value) =>
      Navigator.of(context).pop(Helpers.parseMoney(value));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        decoration: const InputDecoration(prefixText: '₹ ', hintText: '0'),
        onSubmitted: _submit,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _submit(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _NoBudget extends StatelessWidget {
  const _NoBudget({required this.onSet});

  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text('No budget this month', style: context.texts.titleMedium),
          const Gap(6),
          Text(
            'Set a limit and this month’s spending is tracked against it. '
            'You are warned at 80% and told when it runs out.',
            style: context.texts.bodySmall,
            textAlign: TextAlign.center,
          ),
          const Gap(16),
          FilledButton.icon(
            onPressed: onSet,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Set a budget'),
          ),
        ],
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.categories});

  final List<String> categories;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final category in categories)
            ListTile(
              leading: Icon(
                categoryIcon(category),
                color: categoryColor(category),
              ),
              title: Text(category),
              onTap: () => Navigator.of(context).pop(category),
            ),
        ],
      ),
    );
  }
}
