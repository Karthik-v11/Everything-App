import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Dart / Flutter extensions used across the app.
///
/// DO NOT MODIFY.

/// [ThemeContext] gives widgets a terse, correct way to reach the theme so that
/// nobody is tempted to hardcode a colour or a [TextStyle].
extension ThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
  Size get screenSize => MediaQuery.sizeOf(this);
  EdgeInsets get viewPadding => MediaQuery.viewPaddingOf(this);
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// [showSnack] shows a transient message. Errors must pass [isError] so they
  /// pick up the error colour (CLAUDE.md §12).
  void showSnack(String message, {bool isError = false}) {
    if (message.isEmpty) return;
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Theme.of(this).colorScheme.error : null,
        ),
      );
  }
}

extension DateTimeX on DateTime {
  /// [dateOnly] strips the time so two days can be compared for equality.
  DateTime get dateOnly => DateTime(year, month, day);

  bool get isToday => dateOnly == DateTime.now().dateOnly;

  bool get isTomorrow =>
      dateOnly ==
      DateTime.now().add(const Duration(days: 1)).dateOnly;

  bool get isYesterday =>
      dateOnly ==
      DateTime.now().subtract(const Duration(days: 1)).dateOnly;

  bool isSameDayAs(DateTime other) => dateOnly == other.dateOnly;

  /// [isPast] is true once the moment has elapsed — used to derive Overdue.
  bool get isPast => isBefore(DateTime.now());

  /// [startOfWeek] is the Monday of this date's week.
  DateTime get startOfWeek =>
      dateOnly.subtract(Duration(days: weekday - DateTime.monday));

  DateTime get startOfMonth => DateTime(year, month);

  DateTime get endOfMonth =>
      DateTime(year, month + 1).subtract(const Duration(microseconds: 1));

  /// `3rd July, Thursday` — the Dashboard date line.
  String get dashboardDate =>
      '${day.ordinal} ${DateFormat.MMMM().format(this)}, '
      '${DateFormat.EEEE().format(this)}';

  /// `03` — the calendar strip date number.
  String get dayNumber => DateFormat('dd').format(this);

  /// `M` — the calendar strip weekday initial.
  String get weekdayInitial => DateFormat.E().format(this)[0].toUpperCase();

  String get shortDate => DateFormat('d MMM').format(this);

  String get shortDateTime => DateFormat('d MMM, h:mm a').format(this);

  /// [relativeLabel] prefers a human word over a date where one exists.
  String get relativeLabel {
    if (isToday) return 'Today';
    if (isTomorrow) return 'Tomorrow';
    if (isYesterday) return 'Yesterday';
    return shortDate;
  }
}

extension IntX on int {
  /// [ordinal] renders `1st`, `2nd`, `3rd`, `4th`.
  String get ordinal {
    if (this >= 11 && this <= 13) return '${this}th';
    return switch (this % 10) {
      1 => '${this}st',
      2 => '${this}nd',
      3 => '${this}rd',
      _ => '${this}th',
    };
  }
}

extension StringX on String {
  bool get isBlank => trim().isEmpty;

  bool get isNotBlank => trim().isNotEmpty;

  String get capitalized =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';

  /// [containsIgnoreCase] is the comparison used by in-memory filtering.
  bool containsIgnoreCase(String other) =>
      toLowerCase().contains(other.toLowerCase());
}

extension WidgetListX on List<Widget> {
  /// [separatedBy] interleaves [separator] between every pair of children —
  /// avoids the deeply nested `Column(children: [a, gap, b, gap, c])` pattern.
  List<Widget> separatedBy(Widget separator) {
    if (length < 2) return this;
    return [
      for (var i = 0; i < length; i++) ...[
        this[i],
        if (i != length - 1) separator,
      ],
    ];
  }
}
