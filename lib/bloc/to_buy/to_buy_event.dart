part of 'to_buy_bloc.dart';

/// [ToBuyEvent] is the base class for every To Buy event.
abstract class ToBuyEvent extends Equatable {
  const ToBuyEvent();

  @override
  List<Object?> get props => [];
}

/// [WatchToBuyEvent] subscribes to the list. Fired once.
class WatchToBuyEvent extends ToBuyEvent {
  const WatchToBuyEvent();
}

/// [FilterToBuyEvent] narrows the list.
///
/// [showPurchased] defaults to false: the point of the screen is what has *not*
/// been bought yet, and a list that leads with a month of ticked-off items buries
/// it.
class FilterToBuyEvent extends ToBuyEvent {
  const FilterToBuyEvent({this.showPurchased = false, this.priority});

  final bool showPurchased;
  final TaskPriority? priority;

  @override
  List<Object?> get props => [showPurchased, priority];
}

/// [SearchToBuyEvent] is the in-module search.
class SearchToBuyEvent extends ToBuyEvent {
  const SearchToBuyEvent({required this.query});

  final String query;

  @override
  List<Object?> get props => [query];
}

/// [SaveToBuyItemEvent] creates or updates, depending on [isEditing].
class SaveToBuyItemEvent extends ToBuyEvent {
  const SaveToBuyItemEvent({required this.item, this.isEditing = false});

  final ToBuyItem item;
  final bool isEditing;

  @override
  List<Object?> get props => [item, isEditing];
}

/// [ToggleToBuyPurchasedEvent] ticks an item off, or puts it back
/// (Requirement 7.2).
class ToggleToBuyPurchasedEvent extends ToBuyEvent {
  const ToggleToBuyPurchasedEvent({
    required this.item,
    required this.isPurchased,
  });

  final ToBuyItem item;
  final bool isPurchased;

  @override
  List<Object?> get props => [item, isPurchased];
}

/// [DeleteToBuyItemEvent] removes an item.
class DeleteToBuyItemEvent extends ToBuyEvent {
  const DeleteToBuyItemEvent({required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}

/// [SyncToBuyRemindersEvent] rebuilds the reminder schedule (Requirement 7.3).
///
/// [settings] is non-null only when [SettingsBloc] is the one dispatching it —
/// pushing the user's configuration across rather than having this bloc read
/// another bloc's state (CLAUDE.md §4.4). Everywhere else it is null, and the
/// configuration already held in the state is used.
class SyncToBuyRemindersEvent extends ToBuyEvent {
  const SyncToBuyRemindersEvent({this.settings});

  final NotificationSettings? settings;

  @override
  List<Object?> get props => [settings];
}
