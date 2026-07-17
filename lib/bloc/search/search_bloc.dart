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
/// Recent searches are the only persisted slice — a stale result list must never
/// survive a restart.
///
/// [SearchQueryChanged] is debounced (`kSearchDebounce`) to keep as-you-type
/// search inside the < 300 ms budget (Requirement 24.2). Recent searches are
/// recorded only on an explicit [SubmitSearch], so the history holds queries the
/// user meant rather than every prefix of them.
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

  /// How many recent queries are kept (Requirement 17).
  static const int _maxRecent = 8;

  FutureOr<void> _onSearchQueryChanged(
    SearchQueryChanged event,
    Emitter<SearchState> emit,
  ) async {
    final query = event.query;

    // An empty box drops back to recent searches rather than querying for nothing.
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

  /// Only the recent searches persist; results are rebuilt on the next query.
  @override
  SearchState? fromJson(Map<String, dynamic> json) => SearchState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(SearchState state) => state.toJson();
}
