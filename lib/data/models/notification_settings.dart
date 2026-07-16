import 'package:equatable/equatable.dart';

/// [NotificationKind] is every notification the app can deliver (Requirement 5).
///
/// Each kind is independently switchable in Settings, so the enum is also the key
/// of the toggle map the user sees.
enum NotificationKind {
  /// A reminder the user set on a task (Requirement 5.1).
  reminder,

  /// The task's due date itself (Requirement 5.2).
  deadline,

  /// A task still pending after its due date passed (Requirement 5.4).
  missed,

  /// The count of tasks due today (Requirement 5.5).
  dailySummary,

  /// The week's completed and pending counts (Requirement 5.6).
  weeklySummary,

  /// Monthly expenses have reached 80% of the budget (Requirement 14.3).
  budgetWarning,

  /// Monthly expenses have passed the budget (Requirement 14.4).
  budgetExceeded,

  /// A category has passed its own limit (Requirement 14.5).
  categoryBudgetExceeded,

  /// A reminder the user set on a to-buy item (Requirement 7.3).
  toBuyReminder;

  String get label => switch (this) {
        NotificationKind.reminder => 'Task reminders',
        NotificationKind.deadline => 'Deadline alerts',
        NotificationKind.missed => 'Missed task alerts',
        NotificationKind.dailySummary => 'Daily summary',
        NotificationKind.weeklySummary => 'Weekly summary',
        NotificationKind.budgetWarning => 'Budget warnings',
        NotificationKind.budgetExceeded => 'Budget exceeded',
        NotificationKind.categoryBudgetExceeded => 'Category budget exceeded',
        NotificationKind.toBuyReminder => 'To-buy reminders',
      };

  String get description => switch (this) {
        NotificationKind.reminder => 'At the time you set on a task.',
        NotificationKind.deadline => 'When a task is due.',
        NotificationKind.missed => 'An hour after a task was due and still open.',
        NotificationKind.dailySummary => "What's due today.",
        NotificationKind.weeklySummary => 'What you finished and what is left.',
        NotificationKind.budgetWarning =>
          'When 80% of the month’s budget is gone.',
        NotificationKind.budgetExceeded => 'When the month’s budget runs out.',
        NotificationKind.categoryBudgetExceeded =>
          'When one category passes its own limit.',
        NotificationKind.toBuyReminder =>
          'At the time you set on something you want to buy.',
      };

  /// [taskKinds] is the slice of the OS queue the Tasks module owns.
  ///
  /// [NotificationService.applyPlan] reconciles by *cancelling anything pending
  /// that its plan does not contain*, which is what stops a reminder outliving
  /// the task it belongs to. That rule only holds if each reconciler is told which
  /// notifications are its to cancel: without this partition, the Tasks sync would
  /// cancel every to-buy reminder the moment it ran, the To-Buy sync would cancel
  /// every task reminder back, and the two would erase each other's alarms on
  /// every write. A module reconciles its own kinds and leaves the rest alone.
  static const Set<NotificationKind> taskKinds = {
    NotificationKind.reminder,
    NotificationKind.deadline,
    NotificationKind.missed,
    NotificationKind.dailySummary,
    NotificationKind.weeklySummary,
  };

  /// [toBuyKinds] is the slice the To-Buy list owns (Requirement 7.3).
  static const Set<NotificationKind> toBuyKinds = {
    NotificationKind.toBuyReminder,
  };

  /// [isSummary] separates the two scheduled digests from the per-task alerts.
  /// They live on different Android channels so the OS can silence one without
  /// the other.
  bool get isSummary =>
      this == NotificationKind.dailySummary ||
      this == NotificationKind.weeklySummary;

  /// [isBudget] is the third channel (Requirement 14).
  ///
  /// The budget alerts are the only kinds that are **not** scheduled: the moment
  /// they become true is the moment the user writes the transaction that makes
  /// them true, so they are delivered immediately rather than planned into the OS
  /// queue. That is why they never appear in [NotificationPlan].
  bool get isBudget =>
      this == NotificationKind.budgetWarning ||
      this == NotificationKind.budgetExceeded ||
      this == NotificationKind.categoryBudgetExceeded;

  static NotificationKind fromName(String? name) =>
      NotificationKind.values.firstWhere(
        (value) => value.name == name,
        orElse: () => NotificationKind.reminder,
      );
}

/// [NotificationSettings] is the user's notification configuration
/// (Requirements 5, 25.2).
///
/// [isEnabled] is the master switch: off means nothing is scheduled at all,
/// whatever the individual kinds say.
///
/// Times are stored as **minutes past midnight** rather than a `TimeOfDay`, which
/// is a Flutter widget type and has no place in the data layer, and rather than a
/// `DateTime`, which would carry a meaningless date.
class NotificationSettings extends Equatable {
  const NotificationSettings({
    this.enabledKinds = const {
      NotificationKind.reminder,
      NotificationKind.deadline,
      NotificationKind.missed,
      NotificationKind.dailySummary,
      NotificationKind.weeklySummary,
      NotificationKind.budgetWarning,
      NotificationKind.budgetExceeded,
      NotificationKind.categoryBudgetExceeded,
      NotificationKind.toBuyReminder,
    },
    this.isEnabled = true,
    this.dailySummaryMinutes = 8 * 60,
    this.weeklySummaryMinutes = 9 * 60,
    this.weeklySummaryWeekday = DateTime.monday,
  });

  final bool isEnabled;
  final Set<NotificationKind> enabledKinds;

  /// Minutes past midnight at which the daily digest fires. Default 08:00.
  final int dailySummaryMinutes;

  /// Minutes past midnight at which the weekly digest fires. Default 09:00.
  final int weeklySummaryMinutes;

  /// `DateTime.monday` … `DateTime.sunday`.
  final int weeklySummaryWeekday;

  /// [allows] is the only check the planner makes: the master switch and the
  /// individual kind, together.
  bool allows(NotificationKind kind) =>
      isEnabled && enabledKinds.contains(kind);

  int get dailySummaryHour => dailySummaryMinutes ~/ 60;

  int get dailySummaryMinute => dailySummaryMinutes % 60;

  int get weeklySummaryHour => weeklySummaryMinutes ~/ 60;

  int get weeklySummaryMinute => weeklySummaryMinutes % 60;

  /// [fromJson] restores the configuration, and switches **on** any kind that did
  /// not exist when it was written.
  ///
  /// Only the kinds that were switchable at write time are recorded in
  /// [_knownKindsKey]. Without it, every kind absent from `enabledKinds` would
  /// look like one the user had turned off — so a kind added in a later build
  /// (the budget alerts, in Phase 5) would arrive silently disabled for everyone
  /// who already had settings on disk, and no toggle in Settings would explain
  /// why nothing was being delivered.
  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    final enabled = {
      for (final name in (json['enabledKinds'] as List?) ?? const [])
        NotificationKind.fromName(name?.toString()),
    };

    final known = json[_knownKindsKey] == null
        ? _kindsBeforeBudgetAlerts
        : {
            for (final name in json[_knownKindsKey] as List)
              NotificationKind.fromName(name?.toString()),
          };

    return NotificationSettings(
      isEnabled: json['isEnabled'] != false,
      enabledKinds: {
        ...enabled,
        for (final kind in NotificationKind.values)
          if (!known.contains(kind)) kind,
      },
      dailySummaryMinutes:
          int.tryParse('${json['dailySummaryMinutes']}') ?? 8 * 60,
      weeklySummaryMinutes:
          int.tryParse('${json['weeklySummaryMinutes']}') ?? 9 * 60,
      weeklySummaryWeekday:
          int.tryParse('${json['weeklySummaryWeekday']}') ?? DateTime.monday,
    );
  }

  Map<String, dynamic> toJson() => {
        'isEnabled': isEnabled,
        'enabledKinds': [for (final kind in enabledKinds) kind.name],
        _knownKindsKey: [for (final kind in NotificationKind.values) kind.name],
        'dailySummaryMinutes': dailySummaryMinutes,
        'weeklySummaryMinutes': weeklySummaryMinutes,
        'weeklySummaryWeekday': weeklySummaryWeekday,
      };

  static const String _knownKindsKey = 'knownKinds';

  /// The kinds that existed before the budget alerts, and therefore the ones a
  /// settings blob with no [_knownKindsKey] was able to switch off.
  static const Set<NotificationKind> _kindsBeforeBudgetAlerts = {
    NotificationKind.reminder,
    NotificationKind.deadline,
    NotificationKind.missed,
    NotificationKind.dailySummary,
    NotificationKind.weeklySummary,
  };

  NotificationSettings copyWith({
    bool? isEnabled,
    Set<NotificationKind>? enabledKinds,
    int? dailySummaryMinutes,
    int? weeklySummaryMinutes,
    int? weeklySummaryWeekday,
  }) =>
      NotificationSettings(
        isEnabled: isEnabled ?? this.isEnabled,
        enabledKinds: enabledKinds ?? this.enabledKinds,
        dailySummaryMinutes: dailySummaryMinutes ?? this.dailySummaryMinutes,
        weeklySummaryMinutes: weeklySummaryMinutes ?? this.weeklySummaryMinutes,
        weeklySummaryWeekday: weeklySummaryWeekday ?? this.weeklySummaryWeekday,
      );

  /// [withKind] switches one kind on or off.
  NotificationSettings withKind(NotificationKind kind, {required bool isOn}) =>
      copyWith(
        enabledKinds: {
          for (final value in enabledKinds)
            if (value != kind) value,
          if (isOn) kind,
        },
      );

  @override
  List<Object?> get props => [
        isEnabled,
        enabledKinds,
        dailySummaryMinutes,
        weeklySummaryMinutes,
        weeklySummaryWeekday,
      ];
}
