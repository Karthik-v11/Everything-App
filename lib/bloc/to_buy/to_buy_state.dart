part of 'to_buy_bloc.dart';

/// [ToBuyState] holds everything the To Buy screen renders.
///
/// [items] is the complete list, purchased entries included — the reminder plan
/// needs to see a purchased item to know its alarm should be withdrawn, and the
/// screen groups them rather than hiding them. What the user sees is
/// [visibleItems], derived from it.
class ToBuyState extends Equatable {
  const ToBuyState({
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.items = const <ToBuyItem>[],
    this.showPurchased = false,
    this.priority,
    this.query = '',
    this.notificationSettings,
  });

  final bool isLoading;
  final String error;
  final String message;
  final List<ToBuyItem> items;

  final bool showPurchased;
  final TaskPriority? priority;
  final String query;

  /// The user's notification configuration, pushed in by [SettingsBloc]. Null until
  /// it has reported, which is what stops a reminder being armed against defaults
  /// the user may have turned off.
  final NotificationSettings? notificationSettings;

  /// [pending] is what is still to be bought — the list's actual subject.
  List<ToBuyItem> get pending => [
        for (final item in items)
          if (!item.isPurchased && _matches(item)) item,
      ];

  /// [purchased] is what has been bought, most recent first.
  List<ToBuyItem> get purchased => [
        for (final item in items)
          if (item.isPurchased && _matches(item)) item,
      ];

  /// [visibleItems] is what the screen lists: the pending items, highest priority
  /// first, and the purchased ones after them when the user asks to see them.
  List<ToBuyItem> get visibleItems => [
        ...pending..sort(_byPriority),
        if (showPurchased) ...purchased,
      ];

  /// Higher priority first; within a priority, most recently added first.
  static int _byPriority(ToBuyItem a, ToBuyItem b) {
    final priority = b.priority.index.compareTo(a.priority.index);
    if (priority != 0) return priority;
    return b.createdAt.compareTo(a.createdAt);
  }

  bool _matches(ToBuyItem item) {
    if (priority != null && item.priority != priority) return false;
    if (query.isNotBlank && !item.matches(query)) return false;
    return true;
  }

  bool get isFiltered => priority != null || query.isNotBlank;

  /// [pendingTotalMinor] is what the unbought items would cost, for the items that
  /// have a price at all.
  ///
  /// Integer minor units, summed as integers — the same rule as the Finance module,
  /// and for the same reason: a total the user is going to compare against their
  /// budget must not be the result of adding up binary floats.
  int get pendingTotalMinor {
    var total = 0;
    for (final item in pending) {
      total += item.estimatedPriceMinor ?? 0;
    }
    return total;
  }

  /// [pendingPricedCount] is how many of the pending items actually carry a price,
  /// so the screen can say what [pendingTotalMinor] is a total *of* rather than
  /// implying it covers everything on the list.
  int get pendingPricedCount {
    var count = 0;
    for (final item in pending) {
      if (item.estimatedPriceMinor != null) count++;
    }
    return count;
  }

  ToBuyState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    List<ToBuyItem>? items,
    bool? showPurchased,
    TaskPriority? priority,
    bool clearPriority = false,
    String? query,
    NotificationSettings? notificationSettings,
  }) =>
      ToBuyState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        items: items ?? this.items,
        showPurchased: showPurchased ?? this.showPurchased,
        priority: clearPriority ? null : (priority ?? this.priority),
        query: query ?? this.query,
        notificationSettings:
            notificationSettings ?? this.notificationSettings,
      );

  @override
  List<Object?> get props => [
        isLoading,
        error,
        message,
        items,
        showPurchased,
        priority,
        query,
        notificationSettings,
      ];
}
