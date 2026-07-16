import 'package:everything_app/core/utils/extensions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// [monthLabel] is `July 2026`.
String monthLabel(DateTime month) => DateFormat('MMMM yyyy').format(month);

/// [MonthSelector] steps the month every finance figure is about.
///
/// Forward is disabled once the selected month is the current one: there is
/// nothing recorded in the future, and a chevron that leads to a screen of zeroes
/// is a chevron that teaches the user it is broken.
class MonthSelector extends StatelessWidget {
  const MonthSelector({
    required this.month,
    required this.onChanged,
    super.key,
  });

  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.month == now.month && month.year == now.year;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
          icon: const Icon(Icons.chevron_left_rounded),
          visualDensity: VisualDensity.compact,
          tooltip: 'Previous month',
        ),
        Text(monthLabel(month), style: context.texts.labelMedium),
        IconButton(
          onPressed: isCurrent
              ? null
              : () => onChanged(DateTime(month.year, month.month + 1)),
          icon: const Icon(Icons.chevron_right_rounded),
          visualDensity: VisualDensity.compact,
          tooltip: 'Next month',
        ),
      ],
    );
  }
}
