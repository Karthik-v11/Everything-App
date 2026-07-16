part of 'budget_bloc.dart';

/// [BudgetState] holds the budgets, the month being tracked, and what has been
/// spent against it.
///
/// [status] is where the two meet, and it is a pure [BudgetStatus] — every
/// percentage, progress bar and alert in the app is derived from that one value,
/// so the rule that decides them is stated once (Property 8).
class BudgetState extends Equatable {
  const BudgetState({
    required this.month,
    required this.year,
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.budgets = const <Budget>[],
    this.spentMinor = 0,
    this.spentByCategory = const <String, int>{},
    this.announced = const <String, BudgetAlertLevel>{},
    this.notifications,
  });

  /// [BudgetState.initial] tracks the current month until [FinanceBloc] says
  /// otherwise.
  factory BudgetState.initial() {
    final now = DateTime.now();
    return BudgetState(month: now.month, year: now.year);
  }

  final bool isLoading;
  final String error;
  final String message;

  /// Every month's budget, from the database.
  final List<Budget> budgets;

  /// The month the spending in this state belongs to.
  final int month;
  final int year;

  final int spentMinor;
  final Map<String, int> spentByCategory;

  /// The highest level already delivered for each alert key, so that an alert is
  /// announced when it escalates and not on every write afterwards.
  ///
  /// The only persisted field: the OS keeps no record of what it has shown, so
  /// without this a restart would re-announce every budget already over its limit.
  final Map<String, BudgetAlertLevel> announced;

  /// The notification configuration, as last reported by [SettingsBloc].
  ///
  /// Null until Settings reports in, and that null is load-bearing: it is what
  /// stops an alert being delivered to a user who has notifications switched off.
  final NotificationSettings? notifications;

  /// [budget] is the budget for the tracked month, or null when none is set.
  Budget? get budget {
    for (final value in budgets) {
      if (value.month == month && value.year == year) return value;
    }
    return null;
  }

  /// [status] is the tracked month's budget and spending together.
  BudgetStatus get status => statusFor(
        budget: budget,
        spentMinor: spentMinor,
        spentByCategory: spentByCategory,
      );

  static BudgetStatus statusFor({
    required Budget? budget,
    required int spentMinor,
    required Map<String, int> spentByCategory,
  }) =>
      BudgetStatus(
        budget: budget,
        spentMinor: spentMinor,
        spentByCategory: spentByCategory,
      );

  /// [budgetFor] is the budget of any month — the budgets screen edits a month
  /// that is not necessarily the one being tracked.
  Budget? budgetFor({required int month, required int year}) {
    for (final value in budgets) {
      if (value.month == month && value.year == year) return value;
    }
    return null;
  }

  BudgetState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    List<Budget>? budgets,
    int? month,
    int? year,
    int? spentMinor,
    Map<String, int>? spentByCategory,
    Map<String, BudgetAlertLevel>? announced,
    NotificationSettings? notifications,
  }) =>
      BudgetState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        budgets: budgets ?? this.budgets,
        month: month ?? this.month,
        year: year ?? this.year,
        spentMinor: spentMinor ?? this.spentMinor,
        spentByCategory: spentByCategory ?? this.spentByCategory,
        announced: announced ?? this.announced,
        notifications: notifications ?? this.notifications,
      );

  /// [fromJson] restores only what has already been announced. The budgets come
  /// from the database stream and the spending is pushed by [FinanceBloc], both
  /// within a frame of launch.
  factory BudgetState.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final announced = json['HydratedAnnounced'];

    return BudgetState(
      month: now.month,
      year: now.year,
      announced: announced is! Map
          ? const {}
          : {
              for (final entry in announced.entries)
                '${entry.key}': BudgetAlertLevel.fromName('${entry.value}'),
            },
    );
  }

  Map<String, dynamic> toJson() => {
        'HydratedAnnounced': {
          for (final entry in announced.entries) entry.key: entry.value.name,
        },
      };

  @override
  List<Object?> get props => [
        isLoading,
        error,
        message,
        budgets,
        month,
        year,
        spentMinor,
        spentByCategory,
        announced,
        notifications,
      ];
}
