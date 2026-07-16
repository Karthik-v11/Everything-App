part of 'news_bloc.dart';

/// [NewsEvent] is the base class for every news event.
abstract class NewsEvent extends Equatable {
  const NewsEvent();

  @override
  List<Object?> get props => [];
}

/// [FetchNewsEvent] refreshes one category's headlines.
///
/// [category] is null for "whichever tab is open", which is what launch and
/// pull-to-refresh mean.
class FetchNewsEvent extends NewsEvent {
  const FetchNewsEvent({this.category});

  final NewsCategory? category;

  @override
  List<Object?> get props => [category];
}

/// [SelectNewsCategoryEvent] switches tabs (Requirement 3.9).
///
/// It fetches only when that tab's cache is stale, so tabbing back and forth
/// costs nothing.
class SelectNewsCategoryEvent extends NewsEvent {
  const SelectNewsCategoryEvent({required this.category});

  final NewsCategory category;

  @override
  List<Object?> get props => [category];
}
