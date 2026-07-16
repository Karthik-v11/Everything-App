import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/models/notification_settings.dart';
import 'package:everything_app/data/models/task.dart';

/// [ScheduledNotification] is one notification the OS has been asked to deliver
/// at a future moment.
///
/// It is the unit of comparison for reconciliation, so **every field that decides
/// what the user sees is in [props]**: two notifications with the same [id] but a
/// different [body] are not equal, and the stale one is replaced.
///
/// The whole object is serialised into the notification's payload. The OS can
/// report back what is pending, but not when it was scheduled for or why, so the
/// payload is what makes an already-scheduled notification comparable to a freshly
/// planned one without keeping a second copy of the schedule on disk that could
/// drift from the OS's.
class ScheduledNotification extends Equatable {
  const ScheduledNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.at,
    this.taskId,
  });

  final int id;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime at;

  /// The task this notification is about, or null for the two summaries.
  final String? taskId;

  factory ScheduledNotification.fromJson(Map<String, dynamic> json) =>
      ScheduledNotification(
        id: int.tryParse('${json['id']}') ?? 0,
        kind: NotificationKind.fromName(json['kind']?.toString()),
        title: json['title']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        at: DateTime.tryParse('${json['at']}') ?? DateTime.now(),
        taskId: json['taskId']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'body': body,
        'at': at.toIso8601String(),
        'taskId': taskId,
      };

  /// [payload] is what is handed to the OS and read back on reconciliation and on
  /// tap.
  String get payload => jsonEncode(toJson());

  /// [decode] reads a payload back. Returns null when the payload is not ours or
  /// is from an incompatible older build — the caller cancels those rather than
  /// leaving an orphan the app can no longer reason about.
  static ScheduledNotification? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['id'] == null || decoded['at'] == null) return null;
      return ScheduledNotification.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  ScheduledNotification copyWith({
    int? id,
    NotificationKind? kind,
    String? title,
    String? body,
    DateTime? at,
    String? taskId,
  }) =>
      ScheduledNotification(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        title: title ?? this.title,
        body: body ?? this.body,
        at: at ?? this.at,
        taskId: taskId ?? this.taskId,
      );

  /// [idFor] hashes a seed to the 31-bit integer the platforms use as a
  /// notification id.
  ///
  /// FNV-1a rather than [Object.hashCode]: the id has to survive an app restart
  /// so that yesterday's schedule can be matched against today's plan, and Dart's
  /// string hash is not contractually stable across runs or platforms. A drifting
  /// id would orphan every notification already sitting in the OS queue.
  static int idFor(String seed) {
    var hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  @override
  List<Object?> get props => [id, kind, title, body, at, taskId];
}

/// [NotificationPlan] turns the task list and the user's settings into the exact
/// set of notifications that should be pending right now (Requirement 5).
///
/// It is a pure function of `(tasks, settings, now)`. Nothing here touches the OS,
/// which is what makes every delivery rule in Requirement 5 unit-testable without
/// a device.
///
/// The plan is **declarative**: it describes the desired end state, not the writes
/// needed to reach it. [NotificationService] diffs it against what the OS actually
/// holds. That is why a task edited, completed or deleted anywhere in the app
/// cannot leave a stale reminder behind — the next plan simply does not contain
/// it, and reconciliation cancels it.
class NotificationPlan {
  const NotificationPlan._();

  /// How long a task may sit past its due date before it counts as missed
  /// (Requirement 5.4). Firing the instant the deadline passes would collide with
  /// the deadline notification itself.
  static const Duration missedGrace = Duration(hours: 1);

  /// How many days of daily summaries to queue ahead.
  ///
  /// The plan is rebuilt on every task change and on every launch, so one day
  /// would normally be enough — the horizon is what keeps the digests coming if
  /// the app is not opened for a week.
  static const int dailySummaryHorizonDays = 7;

  /// iOS drops everything past 64 pending notifications, and drops it silently.
  /// The cap is below that so the two summaries always have room.
  static const int maxScheduled = 60;

  /// [build] is the complete set of notifications that should be pending.
  ///
  /// Ordered by time and truncated to [maxScheduled], so if a user with hundreds
  /// of tasks exceeds the platform ceiling, what survives is the soonest — never
  /// an arbitrary slice.
  static List<ScheduledNotification> build({
    required List<Task> tasks,
    required NotificationSettings settings,
    required DateTime now,
  }) {
    if (!settings.isEnabled) return const [];

    final planned = <ScheduledNotification>[
      for (final task in tasks) ..._forTask(task, settings),
      ..._dailySummaries(tasks, settings, now),
      ..._weeklySummary(tasks, settings, now),
    ];

    // A notification whose moment has passed is not scheduled: the OS would
    // either fire it immediately or reject it, and neither is what the user asked
    // for.
    final upcoming = [
      for (final notification in planned)
        if (notification.at.isAfter(now)) notification,
    ]..sort((a, b) => a.at.compareTo(b.at));

    // Two rules can land on the same id only if they describe the same event, so
    // the first (soonest) wins.
    final byId = <int, ScheduledNotification>{};
    for (final notification in upcoming) {
      byId.putIfAbsent(notification.id, () => notification);
      if (byId.length == maxScheduled) break;
    }

    return byId.values.toList();
  }

  /// [_forTask] is every notification a single task generates: its reminders, its
  /// deadline, and the missed-task alert that follows the deadline.
  ///
  /// A completed or cancelled task generates none — which is what silences a
  /// reminder the moment the task is ticked off, with no explicit cancel call
  /// anywhere in the app.
  static List<ScheduledNotification> _forTask(
    Task task,
    NotificationSettings settings,
  ) {
    if (task.status != TaskStatus.pending) return const [];

    final dueDate = task.dueDate;

    return [
      if (settings.allows(NotificationKind.reminder))
        for (final reminder in task.reminders)
          ScheduledNotification(
            id: ScheduledNotification.idFor(
              'reminder:${task.id}:${reminder.id}',
            ),
            kind: NotificationKind.reminder,
            title: task.title,
            body: dueDate == null
                ? 'Reminder'
                : 'Due ${dueDate.relativeLabel.toLowerCase()} at '
                    '${_clock(dueDate)}',
            at: reminder.at,
            taskId: task.id,
          ),
      if (dueDate != null) ...[
        if (settings.allows(NotificationKind.deadline))
          ScheduledNotification(
            id: ScheduledNotification.idFor('deadline:${task.id}'),
            kind: NotificationKind.deadline,
            title: task.title,
            body: 'Due now.',
            at: dueDate,
            taskId: task.id,
          ),
        if (settings.allows(NotificationKind.missed))
          ScheduledNotification(
            id: ScheduledNotification.idFor('missed:${task.id}'),
            kind: NotificationKind.missed,
            title: task.title,
            body: 'Still not done — it was due at ${_clock(dueDate)}.',
            at: dueDate.add(missedGrace),
            taskId: task.id,
          ),
      ],
    ];
  }

  /// [_dailySummaries] queues one digest per day for the next
  /// [dailySummaryHorizonDays] (Requirement 5.5).
  ///
  /// A day with nothing due gets no notification. A digest that says "0 tasks
  /// today" is noise, and noise is what gets an app's notifications turned off.
  static List<ScheduledNotification> _dailySummaries(
    List<Task> tasks,
    NotificationSettings settings,
    DateTime now,
  ) {
    if (!settings.allows(NotificationKind.dailySummary)) return const [];

    final summaries = <ScheduledNotification>[];

    for (var offset = 0; offset < dailySummaryHorizonDays; offset++) {
      final day = now.dateOnly.add(Duration(days: offset));
      final at = DateTime(
        day.year,
        day.month,
        day.day,
        settings.dailySummaryHour,
        settings.dailySummaryMinute,
      );

      if (!at.isAfter(now)) continue;

      final count = tasks
          .where(
            (task) =>
                task.status == TaskStatus.pending &&
                task.dueDate != null &&
                task.dueDate!.isSameDayAs(day),
          )
          .length;

      if (count == 0) continue;

      summaries.add(
        ScheduledNotification(
          id: ScheduledNotification.idFor('daily:${day.toIso8601String()}'),
          kind: NotificationKind.dailySummary,
          title: 'Today',
          body: count == 1 ? '1 task due today.' : '$count tasks due today.',
          at: at,
        ),
      );
    }

    return summaries;
  }

  /// [_weeklySummary] queues the next weekly digest (Requirement 5.6).
  ///
  /// Only the next one. Its body counts what was completed in the seven days
  /// before it fires, and no count of a future week's completions can be known
  /// now. Scheduling a month of them would be scheduling a month of wrong
  /// numbers; the plan is rebuilt on every task change and every launch, so the
  /// one that is queued is always current.
  static List<ScheduledNotification> _weeklySummary(
    List<Task> tasks,
    NotificationSettings settings,
    DateTime now,
  ) {
    if (!settings.allows(NotificationKind.weeklySummary)) return const [];

    final at = _nextWeekday(
      after: now,
      weekday: settings.weeklySummaryWeekday,
      hour: settings.weeklySummaryHour,
      minute: settings.weeklySummaryMinute,
    );

    final weekStart = at.subtract(const Duration(days: 7));
    final weekEnd = at.add(const Duration(days: 7));

    final completed = tasks
        .where(
          (task) =>
              task.completedAt != null &&
              !task.completedAt!.isBefore(weekStart) &&
              task.completedAt!.isBefore(at),
        )
        .length;

    final pending = tasks
        .where(
          (task) =>
              task.status == TaskStatus.pending &&
              task.dueDate != null &&
              !task.dueDate!.isBefore(at) &&
              task.dueDate!.isBefore(weekEnd),
        )
        .length;

    return [
      ScheduledNotification(
        id: ScheduledNotification.idFor('weekly:${at.toIso8601String()}'),
        kind: NotificationKind.weeklySummary,
        title: 'Your week',
        body: '$completed done last week, $pending due this week.',
        at: at,
      ),
    ];
  }

  /// [_nextWeekday] is the next [weekday] strictly after [after], at the given
  /// time. Today counts only if the time has not passed yet.
  static DateTime _nextWeekday({
    required DateTime after,
    required int weekday,
    required int hour,
    required int minute,
  }) {
    final today = after.dateOnly;
    final daysAhead = (weekday - today.weekday + 7) % 7;

    final candidate = DateTime(
      today.year,
      today.month,
      today.day + daysAhead,
      hour,
      minute,
    );

    return candidate.isAfter(after)
        ? candidate
        : candidate.add(const Duration(days: 7));
  }

  /// [_clock] is `5:30 pm`, built without `intl` so the planner stays pure Dart
  /// and testable with no locale set up.
  static String _clock(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final meridiem = date.hour < 12 ? 'am' : 'pm';

    return '$hour:$minute $meridiem';
  }
}
