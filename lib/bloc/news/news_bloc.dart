import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/data/models/article.dart';
import 'package:everything_app/data/repositories/news_repository.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'news_event.dart';
part 'news_state.dart';

/// [NewsBloc] owns the Dashboard's news section (Requirements 3.9, 3.11).
///
/// Style A, hydrated — and as in [WeatherBloc] the hydration **is** the offline
/// cache: the headlines last fetched for each tab are part of the state, so they
/// are on screen before the first request is made and remain there when it fails.
///
/// Each category is cached separately, because each is a separate request. A tab
/// the user has never opened is empty and fetches on first sight; a tab they
/// opened an hour ago re-fetches; a tab they opened a minute ago does not, which
/// is what keeps a scroll through six tabs from spending six requests of a daily
/// quota the free News_Service plan measures in dozens.
///
/// Events:
/// 1) [FetchNewsEvent] — refresh a category. Fired at launch and on pull.
/// 2) [SelectNewsCategoryEvent] — the tabs.
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
        // Requirement 3.11: cached headlines are the answer when the network is
        // not, and they are delivered without an error the user cannot act on.
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

    // A tab whose headlines are cached and fresh is already on screen — the tap
    // has nothing left to ask for.
    if (state.isStale(event.category)) {
      add(FetchNewsEvent(category: event.category));
    }
  }

  @override
  NewsState? fromJson(Map<String, dynamic> json) => NewsState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(NewsState state) => state.toJson();
}
