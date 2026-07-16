import 'package:everything_app/bloc/finance/finance_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// [CategoryDonut] is the spend-by-category ring from the reference screen
/// (Requirement 13.2).
///
/// [onSelect] fires with the category of the slice that was tapped, which is what
/// takes the user to the transactions behind it (Requirement 13.3).
///
/// [selected] draws that slice proud of the others. A tapped slice has to *look*
/// tapped, or the filtered list it opens reads as the app having lost the rest of
/// the data.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({
    required this.spend,
    required this.onSelect,
    this.selected,
    this.size = 148,
    super.key,
  });

  final List<CategorySpend> spend;
  final ValueChanged<String> onSelect;
  final String? selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (spend.isEmpty) return _EmptyDonut(size: size);

    return SizedBox.square(
      dimension: size,
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: size * 0.26,
          startDegreeOffset: -90,
          pieTouchData: PieTouchData(
            touchCallback: (event, response) {
              // Only a completed tap selects. Every drag and hover frame arrives
              // here too, and acting on those would fire the callback dozens of
              // times as a finger crossed the ring.
              if (event is! FlTapUpEvent) return;

              final index = response?.touchedSection?.touchedSectionIndex ?? -1;
              if (index < 0 || index >= spend.length) return;

              onSelect(spend[index].category);
            },
          ),
          sections: [
            for (final slice in spend)
              PieChartSectionData(
                value: slice.amountMinor.toDouble(),
                color: slice.color,
                radius: slice.category == selected ? size * 0.30 : size * 0.24,
                showTitle: false,
              ),
          ],
        ),
        // The ring is a readout, not an entrance animation: it redraws on every
        // transaction, and a spin each time would make saving one feel slow.
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

/// [_EmptyDonut] is the ring with nothing in it — drawn rather than omitted, so
/// the card does not change height the moment the first transaction lands.
class _EmptyDonut extends StatelessWidget {
  const _EmptyDonut({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: Container(
          height: size * 0.96,
          width: size * 0.96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: context.colors.outlineVariant,
              width: size * 0.11,
            ),
          ),
        ),
      ),
    );
  }
}

/// [CategoryLegend] is the list beside the ring: a dot, the category and what it
/// took, largest first.
class CategoryLegend extends StatelessWidget {
  const CategoryLegend({
    required this.spend,
    required this.onSelect,
    this.selected,
    this.maxRows = 3,
    super.key,
  });

  final List<CategorySpend> spend;
  final ValueChanged<String> onSelect;
  final String? selected;

  /// Rows past this are collapsed into a single "+N more". Three is what the card
  /// can show without the legend becoming a list — the rest of the breakdown lives
  /// on the transactions screen, which is one tap away.
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;
    final colors = context.colors;

    final shown = spend.take(maxRows).toList();
    final hidden = spend.length - shown.length;

    if (spend.isEmpty) {
      return Text('Nothing spent yet.', style: texts.labelMedium);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final slice in shown)
          InkWell(
            onTap: () => onSelect(slice.category),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 10,
                    width: 10,
                    decoration: BoxDecoration(
                      color: slice.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${slice.category} - '
                      '${Helpers.formatMoney(slice.amountMinor, compact: true)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: texts.labelSmall?.copyWith(
                        color: slice.category == selected
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                        fontWeight: slice.category == selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('+$hidden more', style: texts.labelSmall),
          ),
      ],
    );
  }
}
