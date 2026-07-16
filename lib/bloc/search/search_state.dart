part of 'search_bloc.dart';

/// [SearchResultGroup] is the results from one module, under its heading
/// (Requirement 17.2 — results grouped by module).
class SearchResultGroup extends Equatable {
  const SearchResultGroup({required this.module, required this.results});

  final SearchModule module;
  final List<SearchResult> results;

  @override
  List<Object?> get props => [module, results];
}

/// [SearchState] holds everything the search screen renders.
///
/// [results] is the flat, relevance-ranked list from the FTS query; [groups]
/// derives the by-module sections from it without a second query. [hasQuery]
/// tells "nothing typed yet" (show recent searches) apart from "typed, no match"
/// (show an empty state).
class SearchState extends Equatable {
  const SearchState({
    this.query = '',
    this.isLoading = false,
    this.error = '',
    this.results = const <SearchResult>[],
    this.recentSearches = const <String>[],
    this.hasQuery = false,
  });

  final String query;
  final bool isLoading;
  final String error;
  final List<SearchResult> results;

  /// The persisted recent-search history, newest first.
  final List<String> recentSearches;

  final bool hasQuery;

  /// [groups] splits [results] into by-module sections, in the canonical module
  /// order rather than in the order the ranking happened to interleave them, so
  /// the sections do not reshuffle between keystrokes.
  List<SearchResultGroup> get groups {
    final byModule = <SearchModule, List<SearchResult>>{};
    for (final result in results) {
      byModule.putIfAbsent(result.module, () => []).add(result);
    }

    return [
      for (final module in SearchModule.values)
        if (byModule[module] case final matches?)
          SearchResultGroup(module: module, results: matches),
    ];
  }

  /// True when a query is active but matched nothing — the "no results" state,
  /// distinct from the resting state before anything is typed.
  bool get isEmptyResult => hasQuery && !isLoading && results.isEmpty;

  SearchState copyWith({
    String? query,
    bool? isLoading,
    String? error,
    List<SearchResult>? results,
    List<String>? recentSearches,
    bool? hasQuery,
  }) =>
      SearchState(
        query: query ?? this.query,
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        results: results ?? this.results,
        recentSearches: recentSearches ?? this.recentSearches,
        hasQuery: hasQuery ?? this.hasQuery,
      );

  /// [fromJson] restores only the recent searches. The query, results and
  /// loading flag are all transient.
  factory SearchState.fromJson(Map<String, dynamic> json) => SearchState(
        recentSearches: (json['HydratedRecentSearches'] as List?)
                ?.map((entry) => entry.toString())
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'HydratedRecentSearches': recentSearches,
      };

  @override
  List<Object?> get props => [
        query,
        isLoading,
        error,
        results,
        recentSearches,
        hasQuery,
      ];
}
