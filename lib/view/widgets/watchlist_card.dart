import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/watchlist_item.dart';
import 'package:flutter/material.dart';

/// [WatchlistCard] is one tracked title (Requirement 8).
///
/// The `+1` button is the whole point of the card. Watching an episode is the thing
/// the user does over and over, and it should cost one tap from the list — not a
/// tap into a sheet, a field, a number and a save.
///
/// It disappears at the total, because [WatchlistItem.withProgress] completes the
/// entry when progress reaches it: a button that could only ever be a no-op is worse
/// than no button.
class WatchlistCard extends StatelessWidget {
  const WatchlistCard({
    required this.item,
    required this.onTap,
    required this.onIncrement,
    super.key,
  });

  final WatchlistItem item;
  final VoidCallback onTap;
  final VoidCallback onIncrement;

  /// Whether one more episode is a thing that can happen: the entry counts progress,
  /// it is not finished with, and it is not already at its total.
  bool get _canIncrement {
    if (!item.mediaType.hasProgress) return false;
    if (item.status == WatchStatus.completed) return false;
    if (item.status == WatchStatus.dropped) return false;

    final total = item.total;
    final current = item.currentProgress ?? 0;

    return total == null || current < total;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    final fraction = item.progressFraction;
    final progress = item.progressLabel;

    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Icon(
                item.mediaType.icon,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: texts.labelLarge?.copyWith(
                              color: item.status == WatchStatus.dropped
                                  ? colors.onSurfaceVariant
                                  : null,
                            ),
                          ),
                        ),
                        if (item.rating != null) ...[
                          const Gap(8),
                          Icon(
                            Icons.star_rounded,
                            size: 13,
                            color: colors.primary,
                          ),
                          const Gap(3),
                          Text(
                            item.rating!.toStringAsFixed(1),
                            style: texts.labelSmall?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const Gap(5),
                    Row(
                      children: [
                        _StatusDot(status: item.status),
                        const Gap(6),
                        Text(item.status.label, style: texts.labelSmall),
                        if (progress != null) ...[
                          const Gap(8),
                          Text('·', style: texts.labelSmall),
                          const Gap(8),
                          Flexible(
                            child: Text(
                              progress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: texts.labelSmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (fraction != null) ...[
                      const Gap(8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 3,
                          backgroundColor: colors.surfaceContainerHighest,
                          color: item.isCompleted
                              ? colors.onSurfaceVariant
                              : colors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_canIncrement) ...[
                const Gap(6),
                IconButton(
                  onPressed: onIncrement,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  color: colors.primary,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'One more ${item.mediaType.unit}',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// [_StatusDot] is the entry's status as a colour, next to the word.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final WatchStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final color = switch (status) {
      WatchStatus.watching => colors.primary,
      WatchStatus.completed => colors.onSurfaceVariant,
      WatchStatus.dropped => colors.error,
      WatchStatus.wishlist => colors.outline,
    };

    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
