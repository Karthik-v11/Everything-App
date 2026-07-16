import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/data/models/account.dart';
import 'package:everything_app/data/models/transaction.dart';
import 'package:flutter/material.dart';

/// [TransactionCard] is one row of the transaction list.
///
/// The amount is the row's headline, so it is the only thing on the right and it
/// is signed: income reads `+₹4,000` in the success colour, an expense `-₹250`.
/// Money is stored unsigned with a [TransactionType] beside it, so the sign shown
/// here is a rendering of the type and never of the stored number.
///
/// [account] is the resolved account, or null when it has been deleted out from
/// under the row.
class TransactionCard extends StatelessWidget {
  const TransactionCard({
    required this.transaction,
    required this.onTap,
    this.account,
    super.key,
  });

  final Transaction transaction;
  final Account? account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    final isIncome = transaction.isIncome;
    final amountColor = switch (transaction.type) {
      TransactionType.income => colors.tertiary,
      TransactionType.transfer => colors.onSurfaceVariant,
      _ => colors.onSurface,
    };

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            _CategoryBadge(category: transaction.category),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    transaction.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: texts.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      transaction.category,
                      if (account != null) account!.name,
                      transaction.date.shortDate,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: texts.labelSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${isIncome ? '+' : '-'}'
              '${Helpers.formatMoney(transaction.amountMinor, compact: true)}',
              style: texts.labelLarge?.copyWith(
                color: amountColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [_CategoryBadge] is the coloured glyph that opens the row. Its colour is the
/// same one the category takes in the donut, which is what lets the chart's legend
/// be read against the list without a second lookup.
class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(category);

    return Container(
      height: 38,
      width: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(categoryIcon(category), size: 18, color: color),
    );
  }
}
