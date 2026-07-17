import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/models/notification_settings.dart';

/// The share of the monthly limit at which the warning fires (Requirement 14.3).
const double kBudgetWarningRatio = 0.8;

/// [BudgetAlertLevel] is how far into the budget the spending has gone.
///
/// Ordered: a level only ever escalates within a month, which is what
/// [BudgetBloc] uses to decide whether an alert is news or a repeat.
enum BudgetAlertLevel {
  none,
  warning,
  exceeded;

  bool isAbove(BudgetAlertLevel other) => index > other.index;

  static BudgetAlertLevel fromName(String? name) =>
      BudgetAlertLevel.values.firstWhere(
        (value) => value.name == name,
        orElse: () => BudgetAlertLevel.none,
      );
}

/// [Budget] is the user's limit for one month (Requirement 14).
///
/// [categoryLimits] maps a category name to its own limit in minor units. A
/// category with no entry is unlimited — it still counts against the monthly
/// limit, it simply has no ceiling of its own.
class Budget extends Equatable {
  const Budget({
    required this.id,
    required this.monthlyLimitMinor,
    required this.month,
    required this.year,
    this.categoryLimits = const <String, int>{},
  });

  final String id;
  final int monthlyLimitMinor;
  final Map<String, int> categoryLimits;
  final int month;
  final int year;

  /// [isSet] is false for a month the user has not budgeted. A zero limit is not
  /// a budget of nothing — it is the absence of one, and nothing is tracked
  /// against it (Requirement 14.1, Property 8's "positive monthly limit").
  bool get isSet => monthlyLimitMinor > 0;

  bool isFor(DateTime date) => date.month == month && date.year == year;

  factory Budget.fromEntry(BudgetEntry entry) => Budget(
        id: entry.id,
        monthlyLimitMinor: entry.monthlyLimitMinor,
        categoryLimits: _decodeLimits(entry.categoryLimitsJson),
        month: entry.month,
        year: entry.year,
      );

  BudgetsTableCompanion toCompanion() => BudgetsTableCompanion.insert(
        id: id,
        monthlyLimitMinor: monthlyLimitMinor,
        categoryLimitsJson: Value(jsonEncode(categoryLimits)),
        month: month,
        year: year,
      );

  Budget copyWith({
    String? id,
    int? monthlyLimitMinor,
    Map<String, int>? categoryLimits,
    int? month,
    int? year,
  }) =>
      Budget(
        id: id ?? this.id,
        monthlyLimitMinor: monthlyLimitMinor ?? this.monthlyLimitMinor,
        categoryLimits: categoryLimits ?? this.categoryLimits,
        month: month ?? this.month,
        year: year ?? this.year,
      );

  static Map<String, int> _decodeLimits(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};

      return {
        for (final entry in decoded.entries)
          if (int.tryParse('${entry.value}') case final int limit)
            '${entry.key}': limit,
      };
    } on FormatException {
      return const {};
    }
  }

  @override
  List<Object?> get props => [id, monthlyLimitMinor, categoryLimits, month, year];
}

/// [BudgetAlert] is one thing the user needs to be told about their budget
/// (Requirements 14.3, 14.4, 14.5).
///
/// [category] is null for the two alerts about the monthly limit as a whole, and
/// the category name for a category that has passed its own limit.
class BudgetAlert extends Equatable {
  const BudgetAlert({
    required this.level,
    required this.spentMinor,
    required this.limitMinor,
    this.category,
  });

  final BudgetAlertLevel level;
  final int spentMinor;
  final int limitMinor;
  final String? category;

  bool get isCategoryAlert => category != null;

  /// [kind] is the notification this alert is delivered as.
  NotificationKind get kind {
    if (isCategoryAlert) return NotificationKind.categoryBudgetExceeded;

    return level == BudgetAlertLevel.exceeded
        ? NotificationKind.budgetExceeded
        : NotificationKind.budgetWarning;
  }

  /// [key] identifies *what* this alert is about, independently of its level, so
  /// that a warning already delivered can be recognised when the same budget
  /// later goes on to be exceeded.
  String key(int year, int month) {
    final period = '$year-${month.toString().padLeft(2, '0')}';
    return isCategoryAlert ? '$period:category:$category' : '$period:monthly';
  }

  String get title => switch ((isCategoryAlert, level)) {
        (true, _) => '$category is over budget',
        (false, BudgetAlertLevel.exceeded) => 'Over budget',
        (false, _) => 'Close to your budget',
      };

  String get body {
    final spent = Helpers.formatMoney(spentMinor, compact: true);
    final limit = Helpers.formatMoney(limitMinor, compact: true);
    final percent = Helpers.percentOf(spentMinor, limitMinor).round();

    if (isCategoryAlert) return '$spent spent of the $limit $category limit.';

    return level == BudgetAlertLevel.exceeded
        ? "$spent spent of your $limit budget — that's $percent%."
        : '$spent of your $limit budget is gone — $percent%.';
  }

  @override
  List<Object?> get props => [level, spentMinor, limitMinor, category];
}

/// [BudgetStatus] is a budget, what has been spent against it, and everything
/// that follows from the two.
///
/// A pure value: no repository, no clock, no bloc — so Property 8's threshold
/// rule is stated once here rather than by the progress bar, the alert and the
/// test separately.
class BudgetStatus extends Equatable {
  const BudgetStatus({
    required this.budget,
    required this.spentMinor,
    this.spentByCategory = const <String, int>{},
  });

  final Budget? budget;

  /// Total expenses for the budget's month, in minor units.
  final int spentMinor;

  /// Expenses for the month, per category name.
  final Map<String, int> spentByCategory;

  bool get isSet => budget?.isSet ?? false;

  int get limitMinor => budget?.monthlyLimitMinor ?? 0;

  int get remainingMinor => limitMinor - spentMinor;

  /// [percentUsed] is 0–100+ — deliberately not clamped, because a bar that stops
  /// at 100% cannot show *how far* past the limit the user is.
  double get percentUsed => Helpers.percentOf(spentMinor, limitMinor);

  /// [ratio] is [percentUsed] as the 0–1 fraction a progress bar wants, clamped
  /// so an overspend fills the bar rather than overflowing it.
  double get ratio => (percentUsed / 100).clamp(0.0, 1.0);

  /// [level] is the threshold rule of Property 8, and the only statement of it in
  /// the app.
  ///
  /// Warning **iff** spending is at or past 80% of the limit and below 100%;
  /// exceeded **iff** at or past 100%. A limit of zero or less is not a budget,
  /// so nothing is triggered against it.
  BudgetAlertLevel get level => levelFor(spentMinor: spentMinor, limitMinor: limitMinor);

  /// [levelFor] is [level] as a free function, for a category's own limit.
  static BudgetAlertLevel levelFor({
    required int spentMinor,
    required int limitMinor,
  }) {
    if (limitMinor <= 0) return BudgetAlertLevel.none;
    if (spentMinor >= limitMinor) return BudgetAlertLevel.exceeded;

    // Compared as integers — `spent / limit >= 0.8` in floating point is false
    // for spends that are exactly 80% of certain limits.
    final isWarning = spentMinor * 5 >= limitMinor * 4;

    return isWarning ? BudgetAlertLevel.warning : BudgetAlertLevel.none;
  }

  /// [categories] is every category with a limit of its own, with what it has
  /// spent — the per-category progress bars (Requirement 14.2).
  List<BudgetStatus> get categories {
    final limits = budget?.categoryLimits ?? const <String, int>{};

    return [
      for (final entry in limits.entries)
        BudgetStatus(
          budget: Budget(
            id: entry.key,
            monthlyLimitMinor: entry.value,
            month: budget!.month,
            year: budget!.year,
          ),
          spentMinor: spentByCategory[entry.key] ?? 0,
        ),
    ]..sort((a, b) => b.percentUsed.compareTo(a.percentUsed));
  }

  /// [alerts] is everything the user should be told right now (Requirements 14.3,
  /// 14.4, 14.5).
  ///
  /// The monthly budget contributes at most one — an exceeded budget is not also
  /// warned about. Category limits contribute one each, on exceeding only
  /// (Requirement 14.5 asks for no category warning).
  List<BudgetAlert> get alerts {
    final monthly = level;

    return [
      if (monthly != BudgetAlertLevel.none)
        BudgetAlert(
          level: monthly,
          spentMinor: spentMinor,
          limitMinor: limitMinor,
        ),
      for (final category in categories)
        if (category.level == BudgetAlertLevel.exceeded)
          BudgetAlert(
            level: BudgetAlertLevel.exceeded,
            spentMinor: category.spentMinor,
            limitMinor: category.limitMinor,
            // The synthetic budget in [categories] carries the category name as
            // its id.
            category: category.budget!.id,
          ),
    ];
  }

  @override
  List<Object?> get props => [budget, spentMinor, spentByCategory];
}
