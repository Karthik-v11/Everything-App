import 'package:everything_app/core/utils/app_colors.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/data/models/budget.dart';
import 'package:flutter/material.dart';

/// [BudgetBar] is the strip along the bottom of the finance card in the reference
/// screen: what the budget is, how much of it is gone, and a bar.
///
/// The bar's colour *is* the alert level — amber at 80%, red past 100% — so the
/// screen and the notification can never disagree about where the spending stands.
/// Both read [BudgetStatus.level], which is the one place the rule is written
/// (Property 8).
///
/// With no budget set it becomes an invitation to set one rather than disappearing:
/// a card that silently omits the row is a card the user never learns has a
/// budget feature.
class BudgetBar extends StatelessWidget {
  const BudgetBar({
    required this.status,
    required this.onTap,
    super.key,
  });

  final BudgetStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: status.isSet
            ? _SetBudget(status: status)
            : Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Set a budget for the month',
                      style: texts.labelSmall,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
      ),
    );
  }
}

/// [_SetBudget] stacks the strip rather than lining it up: the limit, the amount
/// spent and the percentage never fit on one row at any real budget, and the row
/// that tried ellipsed the one number the strip exists to show.
class _SetBudget extends StatelessWidget {
  const _SetBudget({required this.status});

  final BudgetStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    final accent = switch (status.level) {
      BudgetAlertLevel.exceeded => colors.error,
      BudgetAlertLevel.warning => AppColors.warning,
      BudgetAlertLevel.none => colors.primary,
    };

    final remaining = status.remainingMinor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Budget this month', style: texts.labelSmall)),
            const SizedBox(width: 8),
            Text(
              '${Helpers.formatMoney(status.spentMinor, compact: true)}'
              ' / ${Helpers.formatMoney(status.limitMinor, compact: true)}',
              style: texts.labelMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: status.ratio),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: colors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                '${status.percentUsed.round()}% used',
                style: texts.labelSmall?.copyWith(color: accent),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              remaining >= 0
                  ? '${Helpers.formatMoney(remaining, compact: true)} left'
                  : '${Helpers.formatMoney(-remaining, compact: true)} over',
              style: texts.labelSmall?.copyWith(
                color: remaining >= 0 ? colors.onSurfaceVariant : colors.error,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// [BudgetProgressRow] is one budget on the Budgets screen — the monthly limit or
/// a single category's.
class BudgetProgressRow extends StatelessWidget {
  const BudgetProgressRow({
    required this.label,
    required this.status,
    super.key,
  });

  final String label;
  final BudgetStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    final accent = switch (status.level) {
      BudgetAlertLevel.exceeded => colors.error,
      BudgetAlertLevel.warning => AppColors.warning,
      BudgetAlertLevel.none => colors.primary,
    };

    final remaining = status.remainingMinor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: texts.titleMedium)),
              Text(
                '${Helpers.formatMoney(status.spentMinor, compact: true)}'
                ' / ${Helpers.formatMoney(status.limitMinor, compact: true)}',
                style: texts.labelMedium?.copyWith(color: accent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: status.ratio),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: colors.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            remaining >= 0
                ? '${Helpers.formatMoney(remaining, compact: true)} left'
                : '${Helpers.formatMoney(-remaining, compact: true)} over',
            style: texts.labelSmall?.copyWith(
              color: remaining >= 0 ? colors.onSurfaceVariant : colors.error,
            ),
          ),
        ],
      ),
    );
  }
}
