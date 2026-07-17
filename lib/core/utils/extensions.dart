import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Dart / Flutter extensions used across the app.
///
/// DO NOT MODIFY.

/// Built once rather than per call: the getters below run from list-item
/// builders, so a fresh `DateFormat` would be parsed per visible row per frame.
/// Safe to cache because the app is single-locale.
final _monthName = DateFormat.MMMM();
final _weekdayName = DateFormat.EEEE();
final _dayNumber = DateFormat('dd');
final _weekdayShort = DateFormat.E();
final _shortDate = DateFormat('d MMM');
final _shortDateTime = DateFormat('d MMM, h:mm a');
final _timeLabel = DateFormat('h:mma');

/// [ThemeContext] gives widgets a terse, correct way to reach the theme so that
/// nobody is tempted to hardcode a colour or a [TextStyle].
extension ThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
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
      '${day.ordinal} ${_monthName.format(this)}, '
      '${_weekdayName.format(this)}';

  /// `03` — the calendar strip date number.
  String get dayNumber => _dayNumber.format(this);

  /// `M` — the calendar strip weekday initial.
  String get weekdayInitial => _weekdayShort.format(this)[0].toUpperCase();

  String get shortDate => _shortDate.format(this);

  String get shortDateTime => _shortDateTime.format(this);

  /// [relativeLabel] prefers a human word over a date where one exists.
  String get relativeLabel {
    if (isToday) return 'Today';
    if (isTomorrow) return 'Tomorrow';
    if (isYesterday) return 'Yesterday';
    return shortDate;
  }

  /// [dueStatus] is the task row's status line: `Overdue by 2 days`, `Due Today`,
  /// `Due in 3 days`.
  ///
  /// Per-**day**, like [TasksState.overdueCount] and the "By date" grouping: a
  /// task due at 09:00 reads `Due Today` for the rest of that day rather than
  /// flipping to overdue over lunch.
  ///
  /// Reads [clock], not [DateTime.now]: the count above these rows is derived
  /// from the same injectable clock, and a row that disagreed with its own
  /// heading under test would disagree with it in production too.
  String get dueStatus {
    final days = dateOnly.difference(clock.now().dateOnly).inDays;

    if (days == 0) return 'Due Today';
    if (days == 1) return 'Due Tomorrow';
    if (days > 1) return 'Due in $days days';

    final late = -days;
    return late == 1 ? 'Overdue by 1 day' : 'Overdue by $late days';
  }

  /// [countdown] is `in 10 mins` — how long until this moment, for the
  /// Dashboard's Upcoming panel. Past moments give an empty string; the panel
  /// only ever holds a future one.
  String get countdown {
    final left = difference(clock.now());
    if (left.isNegative) return '';

    if (left.inMinutes < 1) return 'in under a min';
    if (left.inMinutes == 1) return 'in 1 min';
    if (left.inMinutes < 60) return 'in ${left.inMinutes} mins';
    if (left.inHours == 1) return 'in 1 hr';
    return 'in ${left.inHours} hrs';
  }

  /// `10:30AM` — the clock reading beside a task's `Due Today`.
  String get timeLabel => _timeLabel.format(this);
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
