part of 'search_bloc.dart';

/// [SearchEvent] is the base class for every Global Search event.
abstract class SearchEvent extends Equatable {
  const SearchEvent();

  @override
  List<Object?> get props => [];
}

/// [SearchQueryChanged] carries the text field's latest value (Requirement 17.2).
///
/// Debounced in the bloc, so a run of keystrokes issues one query on the settled
/// text. An empty query clears the results and shows recent searches instead.
class SearchQueryChanged extends SearchEvent {
  const SearchQueryChanged({required this.query});

  final String query;

  @override
  List<Object?> get props => [query];
}

/// [SubmitSearch] records [query] in the recent-search history (Requirement 17).
///
/// Dispatched when the user presses enter or taps a result — not on every
/// keystroke, so the history holds queries the user meant rather than every
/// prefix of them.
class SubmitSearch extends SearchEvent {
  const SubmitSearch({required this.query});

  final String query;

  @override
  List<Object?> get props => [query];
}

/// [RemoveRecentSearch] drops one entry from the recent-search history.
class RemoveRecentSearch extends SearchEvent {
  const RemoveRecentSearch({required this.query});

  final String query;

  @override
  List<Object?> get props => [query];
}

/// [ClearRecentSearches] empties the recent-search history.
class ClearRecentSearches extends SearchEvent {
  const ClearRecentSearches();
}
