import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/to_buy_item.dart';
import 'package:flutter/material.dart';

/// [ToBuyCard] is one thing to buy (Requirement 7).
///
/// The checkbox writes immediately and the strike-through follows the write rather
/// than anticipating it — the database is local, so the round trip is a millisecond
/// and an optimistic tick would only be able to lie.
class ToBuyCard extends StatelessWidget {
  const ToBuyCard({
    required this.item,
    required this.onToggle,
    required this.onTap,
    super.key,
  });

  final ToBuyItem item;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    final isPurchased = item.isPurchased;
    final price = item.estimatedPriceMinor;
    final reminder = item.reminderAt;

    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
          child: Row(
            children: [
              Checkbox(
                value: isPurchased,
                onChanged: (value) => onToggle(value ?? false),
                // The tap target the user actually aims at; the visual box is
                // smaller than the area that accepts the tap.
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
              const Gap(2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: texts.labelLarge?.copyWith(
                        decoration:
                            isPurchased ? TextDecoration.lineThrough : null,
                        color: isPurchased ? colors.onSurfaceVariant : null,
                      ),
                    ),
                    if (item.store != null || reminder != null) ...[
                      const Gap(4),
                      Row(
                        children: [
                          if (item.store != null) ...[
                            Icon(
                              Icons.storefront_outlined,
                              size: 12,
                              color: colors.onSurfaceVariant,
                            ),
                            const Gap(5),
                            Flexible(
                              child: Text(
                                item.store!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: texts.labelSmall,
                              ),
                            ),
                          ],
                          // The reminder is hidden once the item is bought: the
                          // alarm has already been withdrawn by the reconciliation,
                          // and a card still advertising it would be describing
                          // something that is no longer going to happen.
                          if (reminder != null && !isPurchased) ...[
                            if (item.store != null) const Gap(10),
                            Icon(
                              Icons.notifications_none_rounded,
                              size: 12,
                              color: colors.primary,
                            ),
                            const Gap(4),
                            Flexible(
                              child: Text(
                                reminder.shortDateTime,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: texts.labelSmall?.copyWith(
                                  color: colors.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Gap(10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (price != null)
                    Text(
                      Helpers.formatMoney(price, compact: true),
                      style: texts.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isPurchased ? colors.onSurfaceVariant : null,
                      ),
                    ),
                  if (!isPurchased) ...[
                    if (price != null) const Gap(5),
                    // The priority is a bar rather than a word: it is a rank, and a
                    // rank is read faster as a length than as a label.
                    Container(
                      width: 22,
                      height: 3,
                      decoration: BoxDecoration(
                        color: item.priority.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
