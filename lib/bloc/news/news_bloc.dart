import 'dart:async';

import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/data/models/article.dart';
import 'package:everything_app/data/repositories/news_repository.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'news_event.dart';
part 'news_state.dart';

/// [NewsBloc] owns the Dashboard's news section (Requirements 3.9, 3.11).
///
/// As in [WeatherBloc], the hydrated state *is* the offline cache
/// (Requirement 3.11).
///
/// Each category is cached separately with its own [kStaleCacheThreshold] check,
/// so tabbing back and forth does not spend six requests of the free news plan's
/// daily quota, which is measured in dozens.
class NewsBloc extends HydratedBloc<NewsEvent, NewsState> {
  NewsBloc({required this.repository}) : super(const NewsState()) {
    on<FetchNewsEvent>(_onFetchNewsEvent);
    on<SelectNewsCategoryEvent>(_onSelectNewsCategoryEvent);
  }

  final NewsRepository repository;

  FutureOr<void> _onFetchNewsEvent(
    FetchNewsEvent event,
    Emitter<NewsState> emit,
  ) async {
    final category = event.category ?? state.category;

    emit(state.copyWith(isLoading: true, error: '', message: ''));

    try {
      final response = await repository.headlines(category: category);

      if (!response.success) {
        // Requirement 3.11: surface the error only when the category has no
        // cached headlines to fall back on.
        emit(
          state.copyWith(
            isLoading: false,
            error: state.hasArticles(category) ? '' : response.message,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          isLoading: false,
          articles: {
            ...state.articles,
            category: response.data! as List<Article>,
          },
          fetchedAt: {...state.fetchedAt, category: DateTime.now()},
          error: '',
        ),
      );
    } on Exception {
      emit(
        state.copyWith(
          isLoading: false,
          error: state.hasArticles(category) ? '' : 'Could not load the news.',
        ),
      );
    }
  }

  FutureOr<void> _onSelectNewsCategoryEvent(
    SelectNewsCategoryEvent event,
    Emitter<NewsState> emit,
  ) {
    emit(state.copyWith(category: event.category, error: ''));

    // A tab with fresh cached headlines has nothing left to ask for.
    if (state.isStale(event.category)) {
      add(FetchNewsEvent(category: event.category));
    }
  }

  @override
  NewsState? fromJson(Map<String, dynamic> json) => NewsState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(NewsState state) => state.toJson();
}
