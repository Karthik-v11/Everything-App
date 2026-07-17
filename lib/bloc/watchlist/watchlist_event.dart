part of 'watchlist_bloc.dart';

/// [WatchlistEvent] is the base class for every Watchlist event.
abstract class WatchlistEvent extends Equatable {
  const WatchlistEvent();

  @override
  List<Object?> get props => [];
}

/// [WatchWatchlistEvent] subscribes to the entries. Fired once.
class WatchWatchlistEvent extends WatchlistEvent {
  const WatchWatchlistEvent();
}

/// [FilterWatchlistEvent] narrows by media type and status. A null field clears
/// that filter, so `const FilterWatchlistEvent()` shows everything.
class FilterWatchlistEvent extends WatchlistEvent {
  const FilterWatchlistEvent({this.mediaType, this.status});

  final MediaType? mediaType;
  final WatchStatus? status;

  @override
  List<Object?> get props => [mediaType, status];
}

/// [SearchWatchlistEvent] is the in-module search.
class SearchWatchlistEvent extends WatchlistEvent {
  const SearchWatchlistEvent({required this.query});

  final String query;

  @override
  List<Object?> get props => [query];
}

/// [SaveWatchlistItemEvent] creates or updates, depending on [isEditing].
class SaveWatchlistItemEvent extends WatchlistEvent {
  const SaveWatchlistItemEvent({required this.item, this.isEditing = false});

  final WatchlistItem item;
  final bool isEditing;

  @override
  List<Object?> get props => [item, isEditing];
}

/// [SetWatchlistProgressEvent] records how far the user has got
/// (Requirement 8.2). [progress] is unclamped — [WatchlistItem.withProgress]
/// owns the clamp so it holds for every writer.
class SetWatchlistProgressEvent extends WatchlistEvent {
  const SetWatchlistProgressEvent({required this.item, required this.progress});

  final WatchlistItem item;
  final int progress;

  @override
  List<Object?> get props => [item, progress];
}

/// [SetWatchlistStatusEvent] moves an entry between the four statuses
/// (Requirement 8.3).
class SetWatchlistStatusEvent extends WatchlistEvent {
  const SetWatchlistStatusEvent({required this.item, required this.status});

  final WatchlistItem item;
  final WatchStatus status;

  @override
  List<Object?> get props => [item, status];
}

/// [DeleteWatchlistItemEvent] removes an entry.
class DeleteWatchlistItemEvent extends WatchlistEvent {
  const DeleteWatchlistItemEvent({required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}
