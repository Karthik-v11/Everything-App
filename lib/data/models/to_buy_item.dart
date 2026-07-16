import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/models/notification_settings.dart';
import 'package:everything_app/data/models/scheduled_notification.dart';
import 'package:everything_app/data/models/task.dart';

/// [ToBuyItem] is one thing the user intends to buy (Requirement 7).
///
/// [estimatedPriceMinor] is an integer count of minor units (paise), for the same
/// reason [Transaction.amountMinor] is: the list sums it, and binary floating point
/// cannot promise an exact sum. It is nullable — plenty of things go on a wishlist
/// before their price is known.
///
/// Priority reuses [TaskPriority] rather than declaring a parallel enum: it is the
/// same four levels, the same colours, and a second enum would be a second thing to
/// keep in step with the theme.
class ToBuyItem extends Equatable {
  const ToBuyItem({
    required this.id,
    required this.name,
    required this.createdAt,
    this.estimatedPriceMinor,
    this.store,
    this.priority = TaskPriority.medium,
    this.isPurchased = false,
    this.reminderAt,
    this.notes,
  });

  final String id;
  final String name;
  final int? estimatedPriceMinor;
  final String? store;
  final TaskPriority priority;
  final bool isPurchased;
  final DateTime? reminderAt;
  final String? notes;
  final DateTime createdAt;

  bool matches(String query) {
    if (query.isBlank) return true;
    return name.containsIgnoreCase(query) ||
        (store?.containsIgnoreCase(query) ?? false) ||
        (notes?.containsIgnoreCase(query) ?? false);
  }

  factory ToBuyItem.fromEntry(ToBuyItemEntry entry) => ToBuyItem(
        id: entry.id,
        name: entry.name,
        estimatedPriceMinor: entry.estimatedPriceMinor,
        store: entry.store,
        priority: TaskPriority.fromName(entry.priority),
        isPurchased: entry.isPurchased,
        reminderAt: entry.reminderAt,
        notes: entry.notes,
        createdAt: entry.createdAt,
      );

  ToBuyItemsTableCompanion toCompanion() => ToBuyItemsTableCompanion.insert(
        id: id,
        name: name,
        estimatedPriceMinor: Value(estimatedPriceMinor),
        store: Value(store),
        priority: Value(priority.name),
        isPurchased: Value(isPurchased),
        reminderAt: Value(reminderAt),
        notes: Value(notes),
        createdAt: createdAt,
      );

  ToBuyItem copyWith({
    String? id,
    String? name,
    int? estimatedPriceMinor,
    bool clearEstimatedPriceMinor = false,
    String? store,
    bool clearStore = false,
    TaskPriority? priority,
    bool? isPurchased,
    DateTime? reminderAt,
    bool clearReminderAt = false,
    String? notes,
    bool clearNotes = false,
    DateTime? createdAt,
  }) =>
      ToBuyItem(
        id: id ?? this.id,
        name: name ?? this.name,
        estimatedPriceMinor: clearEstimatedPriceMinor
            ? null
            : (estimatedPriceMinor ?? this.estimatedPriceMinor),
        store: clearStore ? null : (store ?? this.store),
        priority: priority ?? this.priority,
        isPurchased: isPurchased ?? this.isPurchased,
        reminderAt: clearReminderAt ? null : (reminderAt ?? this.reminderAt),
        notes: clearNotes ? null : (notes ?? this.notes),
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        estimatedPriceMinor,
        store,
        priority,
        isPurchased,
        reminderAt,
        notes,
        createdAt,
      ];
}

/// [ToBuyPlan] turns the to-buy list into the set of reminders that should be
/// pending right now (Requirement 7.3).
///
/// It is the To-Buy list's counterpart to [NotificationPlan], and it is a pure
/// function of `(items, settings, now)` for the same reason: the schedule is
/// *reconciled* rather than written, so nothing in the app has to remember to
/// cancel a reminder. An item that is purchased, has its reminder removed, or is
/// deleted simply stops appearing in the plan, and [NotificationService.applyPlan]
/// withdraws its alarm.
///
/// It reconciles only [NotificationKind.toBuyKinds], so it never touches the task
/// reminders sharing the same OS queue.
class ToBuyPlan {
  const ToBuyPlan._();

  /// [build] is every to-buy reminder that should be pending.
  ///
  /// A purchased item generates nothing: the point of the reminder was to make the
  /// purchase happen, and it has.
  static List<ScheduledNotification> build({
    required List<ToBuyItem> items,
    required NotificationSettings settings,
    required DateTime now,
  }) {
    if (!settings.allows(NotificationKind.toBuyReminder)) return const [];

    final planned = <ScheduledNotification>[
      for (final item in items)
        if (!item.isPurchased && item.reminderAt != null)
          ScheduledNotification(
            id: ScheduledNotification.idFor('to_buy:${item.id}'),
            kind: NotificationKind.toBuyReminder,
            title: item.name,
            body: item.store == null
                ? 'Still on your to-buy list.'
                : 'Still on your to-buy list — ${item.store}.',
            at: item.reminderAt!,
          ),
    ];

    // A moment that has passed is not scheduled: the OS would fire it immediately
    // or reject it, and neither is what the user asked for.
    return [
      for (final notification in planned)
        if (notification.at.isAfter(now)) notification,
    ]..sort((a, b) => a.at.compareTo(b.at));
  }
}
