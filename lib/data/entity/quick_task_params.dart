import 'package:everything_app/data/models/category.dart';
import 'package:everything_app/data/models/task.dart';

/// [QuickTaskParams] is one parse of the quick-add input.
///
/// The quick-add field accepts a task in a single line, in the shorthand the user
/// already knows from Todoist:
///
/// * `#work` — category. Matched against the existing categories by name; an
///   unknown `#token` is left in the title rather than silently dropped, because
///   the app cannot create a category on the fly.
/// * `@errands` — tag. Any word is accepted; tags are free-form.
/// * `p1`…`p4` — priority, highest to lowest.
/// * `every day`, `every 2 weeks`, `weekly` — recurrence, optionally ended by
///   `until 25 dec`.
/// * `remind me 10 minutes before`, `remind me on time` — reminder, as a gap
///   before the due date.
/// * `today`, `tonight`, `tomorrow`, `friday`, `next week`, `in 3 days`,
///   `25 dec`, `12/03`, `5pm`, `at 17:30` — due date and time.
///
/// Every recognised token is stripped from [title]; what is left is the task
/// name. A token is only ever consumed once, and an earlier match wins over a
/// later overlapping one.
///
/// Fields are nullable to mean "not written": the caller decides what an absent
/// due date or priority falls back to, since a new task and an edited one have
/// different defaults.
class QuickTaskParams {
  QuickTaskParams({
    this.title = '',
    this.dueDate,
    this.priority,
    this.categoryId,
    this.recurrence,
    this.reminderOffset,
    List<String>? tags,
  }) : tags = tags ?? <String>[];

  String title;
  DateTime? dueDate;
  TaskPriority? priority;
  String? categoryId;
  RecurrenceRule? recurrence;
  List<String> tags;

  /// How long before the due date to be reminded. An offset rather than a moment
  /// because that is what the sheet edits, and because the phrasing the parser
  /// reads ("10 minutes before") is itself relative. Zero means on time.
  Duration? reminderOffset;

  /// [hasTokens] is true when the input carried anything beyond the title, which
  /// is what tells the sheet it has something to show as chips.
  bool get hasTokens =>
      dueDate != null ||
      priority != null ||
      categoryId != null ||
      recurrence != null ||
      reminderOffset != null ||
      tags.isNotEmpty;

  /// [QuickTaskParams.parse] reads [raw] into its parts.
  ///
  /// [categories] is what `#token` is resolved against. [now] is the anchor every
  /// relative date is measured from — injectable so the parse is testable.
  factory QuickTaskParams.parse(
    String raw, {
    List<Category> categories = const <Category>[],
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final params = QuickTaskParams();

    // Character ranges of [raw] already consumed by a token. A later pattern that
    // overlaps one of these is ignored, so `at 5pm` cannot also be read as a day.
    final claimed = <List<int>>[];

    bool isFree(RegExpMatch match) => claimed
        .every((span) => match.end <= span.first || match.start >= span.last);

    void claimRange(int start, int end) => claimed.add([start, end]);

    void claim(RegExpMatch match) => claimRange(match.start, match.end);

    // The day and the time are parsed by separate patterns and combined at the
    // end: `tomorrow 5pm` is two tokens, and either may appear without the other.
    DateTime? day;
    int? hour;
    int? minute;

    for (final match in _categoryPattern.allMatches(raw)) {
      if (!isFree(match)) continue;

      final category = _categoryNamed(match.group(1)!, categories);
      if (category == null) continue;

      params.categoryId = category.id;
      claim(match);
      break;
    }

    for (final match in _tagPattern.allMatches(raw)) {
      if (!isFree(match)) continue;

      final tag = match.group(1)!;
      if (!params.tags.contains(tag)) params.tags.add(tag);
      claim(match);
    }

    for (final match in _priorityPattern.allMatches(raw)) {
      if (!isFree(match)) continue;

      params.priority = _priorityOf(match.group(1)!);
      claim(match);
      break;
    }

    // Read before the dates so that the gap in `remind me 2 days before` cannot
    // also be read as a due date.
    for (final match in _reminderPattern.allMatches(raw)) {
      if (!isFree(match)) continue;

      final offset = _reminderOffsetOf(match);
      if (offset == null) continue;

      params.reminderOffset = offset;
      claim(match);
      break;
    }

    for (final match in _recurrencePattern.allMatches(raw)) {
      if (!isFree(match)) continue;

      // `until 25 dec` ends the series. It is claimed together with the rule so
      // the date it names is not also read as the task's due date.
      final until = _untilAfter(raw, match.end, reference);

      params.recurrence = _recurrenceOf(match, until?.date);
      claimRange(match.start, until?.end ?? match.end);
      break;
    }

    for (final pattern in _datePatterns) {
      if (day != null) break;

      for (final match in pattern.allMatches(raw)) {
        if (!isFree(match)) continue;

        final parsed = _dayOf(pattern, match, reference);
        if (parsed == null) continue;

        day = parsed;
        claim(match);
        break;
      }
    }

    for (final pattern in _timePatterns) {
      if (hour != null) break;

      for (final match in pattern.allMatches(raw)) {
        if (!isFree(match)) continue;

        final parsed = _timeOf(pattern, match);
        if (parsed == null) continue;

        hour = parsed.hour;
        minute = parsed.minute;
        claim(match);
        break;
      }
    }

    // A bare time means today; a bare day is due at the default hour.
    if (day != null || hour != null) {
      final base = day ?? DateTime(reference.year, reference.month, reference.day);
      params.dueDate = DateTime(
        base.year,
        base.month,
        base.day,
        hour ?? base.hour,
        minute ?? base.minute,
      );
    }

    params.title = _titleWithout(raw, claimed);

    return params;
  }

  /// [toTask] assembles the task to save.
  ///
  /// [original] is the task being edited, or null when creating: the fields the
  /// sheet does not expose (completion) are carried over from it rather than reset.
  /// The id is left empty on create — the service mints it.
  ///
  /// [projectId] is passed in rather than carried over from [original]: the sheet
  /// now exposes it, so a new task filed from a project is filed under it, and an
  /// edited task's project can be changed or cleared.
  ///
  /// [reminders] is passed in rather than carried over from [original], because
  /// the sheet edits it: carrying it over would make a reminder impossible to
  /// remove.
  Task toTask({
    Task? original,
    DateTime? dueDate,
    TaskPriority priority = TaskPriority.medium,
    String? categoryId,
    String? projectId,
    RecurrenceRule? recurrence,
    List<String> tags = const <String>[],
    List<SubTask> subtasks = const <SubTask>[],
    List<Reminder> reminders = const <Reminder>[],
    String? notes,
  }) {
    final now = DateTime.now();

    return Task(
      id: original?.id ?? '',
      title: title,
      dueDate: dueDate,
      priority: priority,
      status: original?.status ?? TaskStatus.pending,
      categoryId: categoryId,
      projectId: projectId,
      parentTaskId: original?.parentTaskId,
      notes: notes,
      recurrence: recurrence,
      tags: tags,
      reminders: reminders,
      subtasks: subtasks,
      completedAt: original?.completedAt,
      createdAt: original?.createdAt ?? now,
      updatedAt: now,
    );
  }

  QuickTaskParams copyWith({
    String? title,
    DateTime? dueDate,
    TaskPriority? priority,
    String? categoryId,
    RecurrenceRule? recurrence,
    Duration? reminderOffset,
    List<String>? tags,
  }) =>
      QuickTaskParams(
        title: title ?? this.title,
        dueDate: dueDate ?? this.dueDate,
        priority: priority ?? this.priority,
        categoryId: categoryId ?? this.categoryId,
        recurrence: recurrence ?? this.recurrence,
        reminderOffset: reminderOffset ?? this.reminderOffset,
        tags: tags ?? this.tags,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'dueDate': dueDate?.toIso8601String(),
        'priority': priority?.name,
        'categoryId': categoryId,
        'recurrence': recurrence?.toJson(),
        'reminderOffset': reminderOffset?.inMinutes,
        'tags': tags,
      };

  // ── Patterns ───────────────────────────────────────────────────────────────
  //
  // Every pattern is anchored to a token boundary — start of input or a space on
  // the left, a space or end of input on the right — so `p1` inside `p1000` and
  // `#` inside `c#` are not tokens.

  static final RegExp _categoryPattern =
      RegExp(r'(?<=^|\s)#([\p{L}\p{N}_-]+)', unicode: true);

  static final RegExp _tagPattern =
      RegExp(r'(?<=^|\s)@([\p{L}\p{N}_-]+)', unicode: true);

  static final RegExp _priorityPattern =
      RegExp(r'(?<=^|\s)!?p([1-4])(?=\s|$)', caseSensitive: false);

  static final RegExp _recurrencePattern = RegExp(
    r'(?<=^|\s)(?:every\s+(?:(\d+)\s+)?(day|week|month|year)s?'
    r'|(daily|weekly|monthly|yearly))(?=\s|$)',
    caseSensitive: false,
  );

  /// `until 25 dec`, matched immediately after a recurrence rule. The date that
  /// follows is read by the ordinary date patterns, so the series ends on the
  /// same days the due date understands.
  static final RegExp _untilPattern = RegExp(
    r'\s+(?:until|till|til)\s+',
    caseSensitive: false,
  );

  /// `remind me 10 minutes before`, `remind me on time`. The verb is required —
  /// a bare `10 minutes before` is far more likely to be part of the task name.
  static final RegExp _reminderPattern = RegExp(
    r'(?<=^|\s)(?:remind(?:er)?|alert|notify|ping)(?:\s+me)?\s+'
    r'(?:(\d+)\s*(m|mins?|minutes?|h|hrs?|hours?|d|days?|w|weeks?)'
    r'\s+(?:before|early|earlier|ahead|prior|in\s+advance)'
    r'|(?:at\s+)?(?:the\s+)?(on\s+time|at\s+the\s+time|when\s+due|at\s+due))'
    r'(?=\s|$)',
    caseSensitive: false,
  );

  static final RegExp _relativeDayPattern = RegExp(
    r'(?<=^|\s)(today|tonight|tomorrow|tmrw|tmr)(?=\s|$)',
    caseSensitive: false,
  );

  static final RegExp _whitespacePattern = RegExp(r'\s+');

  static final RegExp _inUnitsPattern = RegExp(
    r'(?<=^|\s)in\s+(\d+)\s+(day|week|month)s?(?=\s|$)',
    caseSensitive: false,
  );

  static final RegExp _nextUnitPattern = RegExp(
    r'(?<=^|\s)next\s+(week|month)(?=\s|$)',
    caseSensitive: false,
  );

  static final RegExp _weekdayPattern = RegExp(
    r'(?<=^|\s)(?:(next|this)\s+)?'
    r'(mon|monday|tue|tues|tuesday|wed|weds|wednesday|thu|thur|thurs|thursday'
    r'|fri|friday|sat|saturday|sun|sunday)(?=\s|$)',
    caseSensitive: false,
  );

  static final RegExp _dayMonthPattern = RegExp(
    r'(?<=^|\s)(\d{1,2})(?:st|nd|rd|th)?\s+'
    r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*'
    r'(?:\s+(\d{4}))?(?=\s|$)',
    caseSensitive: false,
  );

  static final RegExp _monthDayPattern = RegExp(
    r'(?<=^|\s)(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+'
    r'(\d{1,2})(?:st|nd|rd|th)?(?:\s+(\d{4}))?(?=\s|$)',
    caseSensitive: false,
  );

  /// Day first, as everywhere outside the United States: `12/03` is 12 March.
  static final RegExp _numericDatePattern = RegExp(
    r'(?<=^|\s)(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?(?=\s|$)',
  );

  static final RegExp _time12Pattern = RegExp(
    r'(?<=^|\s)(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)(?=\s|$)',
    caseSensitive: false,
  );

  /// A 24-hour time needs the colon, so a bare `5` is never read as five o'clock.
  static final RegExp _time24Pattern = RegExp(
    r'(?<=^|\s)(?:at\s+)?([01]?\d|2[0-3]):([0-5]\d)(?=\s|$)',
  );

  /// Tried in order; the first that yields a day wins. Relative words come before
  /// the numeric forms, which are the most likely to match something that was not
  /// meant as a date.
  static final List<RegExp> _datePatterns = [
    _relativeDayPattern,
    _inUnitsPattern,
    _nextUnitPattern,
    _weekdayPattern,
    _dayMonthPattern,
    _monthDayPattern,
    _numericDatePattern,
  ];

  static final List<RegExp> _timePatterns = [_time12Pattern, _time24Pattern];

  static const List<String> _monthNames = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  /// The hour a dated task with no stated time is due at.
  static const int _defaultHour = 9;

  /// [_categoryNamed] resolves `#token` to a category: an exact name first, then
  /// a unique prefix, so `#per` reaches Personal.
  static Category? _categoryNamed(String token, List<Category> categories) {
    final needle = token.toLowerCase();

    for (final category in categories) {
      if (category.name.toLowerCase() == needle) return category;
    }
    for (final category in categories) {
      if (category.name.toLowerCase().startsWith(needle)) return category;
    }
    return null;
  }

  /// p1 is the most urgent, as in Todoist — the inverse of [TaskPriority]'s own
  /// low-to-critical ordering.
  static TaskPriority _priorityOf(String digit) => switch (digit) {
        '1' => TaskPriority.critical,
        '2' => TaskPriority.high,
        '3' => TaskPriority.medium,
        _ => TaskPriority.low,
      };

  static RecurrenceRule _recurrenceOf(RegExpMatch match, DateTime? until) {
    final interval = int.tryParse(match.group(1) ?? '') ?? 1;
    final unit = (match.group(2) ?? match.group(3) ?? 'day').toLowerCase();

    final frequency = switch (unit) {
      'week' || 'weekly' => RecurrenceFrequency.weekly,
      'month' || 'monthly' => RecurrenceFrequency.monthly,
      'year' || 'yearly' => RecurrenceFrequency.yearly,
      _ => RecurrenceFrequency.daily,
    };

    // An interval of zero would make the series never advance; treat it as the
    // plain rule rather than dropping the recurrence the user clearly asked for.
    return RecurrenceRule(
      frequency: frequency,
      interval: interval < 1 ? 1 : interval,
      until: until,
    );
  }

  /// [_untilAfter] reads an `until <date>` clause sitting at [start].
  ///
  /// Returns the day the series ends on and the offset the clause runs to, so the
  /// caller can claim the whole phrase. Null when no clause is there, or when the
  /// words after `until` are not a date the parser knows — in which case the rule
  /// simply has no end, and the words stay in the title.
  static ({DateTime date, int end})? _untilAfter(
    String raw,
    int start,
    DateTime reference,
  ) {
    final keyword = _untilPattern.matchAsPrefix(raw, start);
    if (keyword == null) return null;

    for (final pattern in _datePatterns) {
      final match = pattern.matchAsPrefix(raw, keyword.end);
      if (match == null) continue;

      final day = _dayOf(pattern, match as RegExpMatch, reference);
      if (day == null) continue;

      // The end is a day, not a moment: the default hour would cut the last
      // occurrence off if it were due later than 09:00.
      return (
        date: DateTime(day.year, day.month, day.day, 23, 59),
        end: match.end,
      );
    }

    return null;
  }

  /// [_reminderOffsetOf] turns one reminder match into the gap before the due
  /// date. Zero for the `on time` wording. Null when the unit is unreadable, so
  /// the phrase stays in the title rather than becoming a wrong reminder.
  static Duration? _reminderOffsetOf(RegExpMatch match) {
    if (match.group(3) != null) return Duration.zero;

    final count = int.tryParse(match.group(1) ?? '');
    final unit = match.group(2)?.toLowerCase();
    if (count == null || unit == null) return null;

    if (unit.startsWith('mi') || unit == 'm') return Duration(minutes: count);
    if (unit.startsWith('h')) return Duration(hours: count);
    if (unit.startsWith('d')) return Duration(days: count);
    if (unit.startsWith('w')) return Duration(days: 7 * count);

    return null;
  }

  /// [_dayOf] turns one date match into a day at [_defaultHour]. Null when the
  /// text looked like a date but is not one — 31/02, say — so the words stay in
  /// the title instead of becoming a wrong due date.
  static DateTime? _dayOf(
    RegExp pattern,
    RegExpMatch match,
    DateTime reference,
  ) {
    final today = DateTime(reference.year, reference.month, reference.day);

    if (pattern == _relativeDayPattern) {
      final word = match.group(1)!.toLowerCase();

      // Tonight is today, in the evening — the only word that carries its hour.
      if (word == 'tonight') return today.add(const Duration(hours: 20));
      if (word == 'today') return today.add(const Duration(hours: _defaultHour));

      return today.add(const Duration(days: 1, hours: _defaultHour));
    }

    if (pattern == _inUnitsPattern) {
      final count = int.tryParse(match.group(1)!) ?? 0;
      if (count == 0) return null;

      final unit = match.group(2)!.toLowerCase();
      final target = switch (unit) {
        'week' => today.add(Duration(days: 7 * count)),
        'month' => DateTime(today.year, today.month + count, today.day),
        _ => today.add(Duration(days: count)),
      };

      return target.add(const Duration(hours: _defaultHour));
    }

    if (pattern == _nextUnitPattern) {
      final target = match.group(1)!.toLowerCase() == 'month'
          ? DateTime(today.year, today.month + 1, today.day)
          : today.add(const Duration(days: 7));

      return target.add(const Duration(hours: _defaultHour));
    }

    if (pattern == _weekdayPattern) {
      final weekday = _weekdayOf(match.group(2)!);
      if (weekday == null) return null;

      // A weekday always points forward: `friday` on a Friday means next Friday,
      // not today, which is what makes it useful as a shorthand.
      var ahead = (weekday - today.weekday) % 7;
      if (ahead == 0) ahead = 7;
      if (match.group(1)?.toLowerCase() == 'next' && ahead < 7) ahead += 7;

      return today.add(Duration(days: ahead, hours: _defaultHour));
    }

    if (pattern == _dayMonthPattern || pattern == _monthDayPattern) {
      final isDayFirst = pattern == _dayMonthPattern;
      final day = int.tryParse(match.group(isDayFirst ? 1 : 2)!);
      final month =
          _monthNames.indexOf(match.group(isDayFirst ? 2 : 1)!.toLowerCase()) + 1;
      if (day == null || month == 0) return null;

      final year = int.tryParse(match.group(3) ?? '') ?? reference.year;
      final candidate = _dateOrNull(year, month, day);
      if (candidate == null) return null;

      // A bare day and month with no year means the next one to come round.
      if (match.group(3) == null && candidate.isBefore(today)) {
        return _dateOrNull(year + 1, month, day)
            ?.add(const Duration(hours: _defaultHour));
      }

      return candidate.add(const Duration(hours: _defaultHour));
    }

    if (pattern == _numericDatePattern) {
      final day = int.tryParse(match.group(1)!);
      final month = int.tryParse(match.group(2)!);
      if (day == null || month == null) return null;

      final rawYear = int.tryParse(match.group(3) ?? '');
      final year = rawYear == null
          ? reference.year
          : rawYear < 100
              ? 2000 + rawYear
              : rawYear;

      final candidate = _dateOrNull(year, month, day);
      if (candidate == null) return null;

      if (match.group(3) == null && candidate.isBefore(today)) {
        return _dateOrNull(year + 1, month, day)
            ?.add(const Duration(hours: _defaultHour));
      }

      return candidate.add(const Duration(hours: _defaultHour));
    }

    return null;
  }

  static ({int hour, int minute})? _timeOf(RegExp pattern, RegExpMatch match) {
    if (pattern == _time12Pattern) {
      final hour = int.tryParse(match.group(1)!);
      if (hour == null || hour < 1 || hour > 12) return null;

      final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
      final isPm = match.group(3)!.toLowerCase() == 'pm';

      // 12am is midnight and 12pm is noon: the 12 does not roll over.
      final normalized = hour % 12 + (isPm ? 12 : 0);

      return (hour: normalized, minute: minute);
    }

    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;

    return (hour: hour, minute: minute);
  }

  static int? _weekdayOf(String token) {
    final word = token.toLowerCase();

    if (word.startsWith('mon')) return DateTime.monday;
    if (word.startsWith('tue')) return DateTime.tuesday;
    if (word.startsWith('wed')) return DateTime.wednesday;
    if (word.startsWith('thu')) return DateTime.thursday;
    if (word.startsWith('fri')) return DateTime.friday;
    if (word.startsWith('sat')) return DateTime.saturday;
    if (word.startsWith('sun')) return DateTime.sunday;
    return null;
  }

  /// [_dateOrNull] rejects a day that the month does not have. [DateTime] would
  /// roll 31 February forward into March instead of failing.
  static DateTime? _dateOrNull(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1) return null;

    final built = DateTime(year, month, day);
    if (built.month != month || built.day != day) return null;

    return built;
  }

  /// [_titleWithout] is [raw] with every claimed range cut out and the whitespace
  /// left behind collapsed.
  static String _titleWithout(String raw, List<List<int>> claimed) {
    if (claimed.isEmpty) return raw.trim();

    final spans = [...claimed]..sort((a, b) => a.first.compareTo(b.first));
    final buffer = StringBuffer();

    var cursor = 0;
    for (final span in spans) {
      if (span.first > cursor) buffer.write(raw.substring(cursor, span.first));
      cursor = span.last > cursor ? span.last : cursor;
    }
    if (cursor < raw.length) buffer.write(raw.substring(cursor));

    return buffer.toString().replaceAll(_whitespacePattern, ' ').trim();
  }
}
