import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/bloc/event_transformers.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/models/search_result.dart';
import 'package:everything_app/data/repositories/search_repository.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'search_event.dart';
part 'search_state.dart';

/// [SearchBloc] owns Global Search (Requirement 17).
///
/// Style A: it holds the current query, the ranked results, and the recent
/// searches — the last of which is the only slice that persists, so a returning
/// user's recent queries survive a restart while a stale result list never does.
///
/// [SearchQueryChanged] is debounced (`kSearchDebounce`) so a burst of keystrokes
/// runs one query on the settled text rather than one per character, which is
/// what keeps as-you-type search inside the < 300 ms budget (Requirement 24.2).
/// Recent searches are recorded only on an explicit [SubmitSearch] — every
/// keystroke's prefix is not a search the user meant to keep.
///
/// Events:
/// 1) [SearchQueryChanged] — the text field changed; re-run the search.
/// 2) [SubmitSearch] — the user pressed enter; record the query as recent.
/// 3) [RemoveRecentSearch] / [ClearRecentSearches] — manage the recent list.
class SearchBloc extends HydratedBloc<SearchEvent, SearchState> {
  SearchBloc({required this.repository}) : super(const SearchState()) {
    on<SearchQueryChanged>(
      _onSearchQueryChanged,
      transformer: debounce(kSearchDebounce),
    );
    on<SubmitSearch>(_onSubmitSearch);
    on<RemoveRecentSearch>(_onRemoveRecentSearch);
    on<ClearRecentSearches>(_onClearRecentSearches);
  }

  final SearchRepository repository;

  /// The most recent queries kept per user (Requirement 17). Old enough to be a
  /// history, short enough not to become a second list to scroll.
  static const int _maxRecent = 8;

  FutureOr<void> _onSearchQueryChanged(
    SearchQueryChanged event,
    Emitter<SearchState> emit,
  ) async {
    final query = event.query;

    // An empty box is the resting state, not a search of nothing: drop straight
    // back to recent searches rather than running a query.
    if (query.isBlank) {
      emit(state.copyWith(query: query, results: const [], hasQuery: false));
      return;
    }

    emit(state.copyWith(query: query, isLoading: true, error: '', hasQuery: true));

    final response = await repository.search(query);

    // A late response for a query the user has already cleared or changed must
    // not overwrite the current one.
    if (query != state.query) return;

    if (response.success) {
      emit(
        state.copyWith(
          isLoading: false,
          results: response.data! as List<SearchResult>,
        ),
      );
    } else {
      emit(state.copyWith(isLoading: false, error: response.message));
    }
  }

  FutureOr<void> _onSubmitSearch(
    SubmitSearch event,
    Emitter<SearchState> emit,
  ) {
    final query = event.query.trim();
    if (query.isBlank) return null;

    // Newest first, no case-insensitive duplicate, capped.
    final lowered = query.toLowerCase();
    final recent = [
      query,
      for (final entry in state.recentSearches)
        if (entry.toLowerCase() != lowered) entry,
    ].take(_maxRecent).toList();

    emit(state.copyWith(recentSearches: recent));
  }

  FutureOr<void> _onRemoveRecentSearch(
    RemoveRecentSearch event,
    Emitter<SearchState> emit,
  ) {
    emit(
      state.copyWith(
        recentSearches: [
          for (final entry in state.recentSearches)
            if (entry != event.query) entry,
        ],
      ),
    );
  }

  FutureOr<void> _onClearRecentSearches(
    ClearRecentSearches event,
    Emitter<SearchState> emit,
  ) {
    emit(state.copyWith(recentSearches: const []));
  }

  /// Only the recent searches persist. Results are rebuilt from the database on
  /// the next query, and the in-flight query and loading flag are transient.
  @override
  SearchState? fromJson(Map<String, dynamic> json) => SearchState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(SearchState state) => state.toJson();
}
