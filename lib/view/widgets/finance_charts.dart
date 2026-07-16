import 'package:everything_app/bloc/finance/finance_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// [TrendChart] is the monthly expense trend line (Requirement 13.2).
///
/// The y-axis is in **major units** — the chart is the one place in the app that
/// may leave minor units behind, because it is drawing a shape rather than
/// reporting a number, and a paise-accurate line looks exactly like a rupee-
/// accurate one.
class TrendChart extends StatelessWidget {
  const TrendChart({required this.trend, super.key});

  final List<MonthTotals> trend;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final spots = [
      for (var i = 0; i < trend.length; i++)
        FlSpot(i.toDouble(), Helpers.toMajorUnits(trend[i].expenseMinor)),
    ];

    return LineChart(
      LineChartData(
        minY: 0,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: colors.outlineVariant,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) =>
                  _MonthLabel(trend: trend, value: value),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => colors.surfaceContainerHighest,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  Helpers.formatMoney(
                    Helpers.toMinorUnits(spot.y),
                    compact: true,
                  ),
                  context.texts.labelSmall!.copyWith(color: colors.onSurface),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            // Without this the spline overshoots below zero between two months
            // that differ sharply, drawing a month of negative spending.
            preventCurveOverShooting: true,
            color: colors.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: colors.primary.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }
}

/// [_MonthLabel] is one `Jul` under the axis. The chart indexes its x-axis by
/// position in [MonthTotals], so the label is resolved by position too.
class _MonthLabel extends StatelessWidget {
  const _MonthLabel({required this.trend, required this.value});

  final List<MonthTotals> trend;
  final double value;

  @override
  Widget build(BuildContext context) {
    final index = value.round();
    if (index < 0 || index >= trend.length) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        DateFormat.MMM().format(trend[index].month),
        style: context.texts.labelSmall,
      ),
    );
  }
}
