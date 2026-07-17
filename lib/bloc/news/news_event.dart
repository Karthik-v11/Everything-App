part of 'news_bloc.dart';

/// [NewsEvent] is the base class for every news event.
abstract class NewsEvent extends Equatable {
  const NewsEvent();

  @override
  List<Object?> get props => [];
}

/// [FetchNewsEvent] refreshes one category's headlines. A null [category] means
/// whichever tab is open — what launch and pull-to-refresh want.
class FetchNewsEvent extends NewsEvent {
  const FetchNewsEvent({this.category});

  final NewsCategory? category;

  @override
  List<Object?> get props => [category];
}

/// [SelectNewsCategoryEvent] switches tabs (Requirement 3.9). Fetches only when
/// that tab's cache is stale, so tabbing back and forth costs nothing.
class SelectNewsCategoryEvent extends NewsEvent {
  const SelectNewsCategoryEvent({required this.category});

  final NewsCategory category;

  @override
  List<Object?> get props => [category];
}
