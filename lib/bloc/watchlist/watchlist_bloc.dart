import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/models/watchlist_item.dart';
import 'package:everything_app/data/repositories/watchlist_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'watchlist_event.dart';
part 'watchlist_state.dart';

/// [WatchlistBloc] owns the Watchlist (Requirement 8).
///
/// Subscribes once to the DAO stream and never re-reads — every count, group and
/// filter is derived in memory from that one list.
///
/// Property 16 is **not enforced here**: progress clamping and the completion
/// stamp live in [WatchlistItem.withProgress] / [WatchlistItem.withStatus], which
/// the service routes every write through, so all writers get the rule.
class WatchlistBloc extends Bloc<WatchlistEvent, WatchlistState> {
  WatchlistBloc({required this.repository}) : super(const WatchlistState()) {
    on<WatchWatchlistEvent>(_onWatchWatchlistEvent);
    on<FilterWatchlistEvent>(_onFilterWatchlistEvent);
    on<SearchWatchlistEvent>(_onSearchWatchlistEvent);
    on<SaveWatchlistItemEvent>(_onSaveWatchlistItemEvent);
    on<SetWatchlistProgressEvent>(_onSetWatchlistProgressEvent);
    on<SetWatchlistStatusEvent>(_onSetWatchlistStatusEvent);
    on<DeleteWatchlistItemEvent>(_onDeleteWatchlistItemEvent);
  }

  final WatchlistRepository repository;

  FutureOr<void> _onWatchWatchlistEvent(
    WatchWatchlistEvent event,
    Emitter<WatchlistState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: '', message: ''));

    await emit.forEach<List<WatchlistItem>>(
      repository.watchAll(),
      onData: (items) =>
          state.copyWith(isLoading: false, items: items, error: ''),
      onError: (_, _) => state.copyWith(
        isLoading: false,
        error: 'Could not load your watchlist.',
      ),
    );
  }

  FutureOr<void> _onFilterWatchlistEvent(
    FilterWatchlistEvent event,
    Emitter<WatchlistState> emit,
  ) {
    emit(
      state.copyWith(
        mediaType: event.mediaType,
        clearMediaType: event.mediaType == null,
        status: event.status,
        clearStatus: event.status == null,
      ),
    );
  }

  FutureOr<void> _onSearchWatchlistEvent(
    SearchWatchlistEvent event,
    Emitter<WatchlistState> emit,
  ) {
    emit(state.copyWith(query: event.query));
  }

  FutureOr<void> _onSaveWatchlistItemEvent(
    SaveWatchlistItemEvent event,
    Emitter<WatchlistState> emit,
  ) async {
    try {
      final response = event.isEditing
          ? await repository.update(event.item)
          : await repository.create(event.item);

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not save the entry.'));
    }
  }

  /// Records how far the user has got (Requirement 8.2). Progress is passed
  /// unclamped on purpose — the clamp is [WatchlistItem.withProgress]'s job.
  FutureOr<void> _onSetWatchlistProgressEvent(
    SetWatchlistProgressEvent event,
    Emitter<WatchlistState> emit,
  ) async {
    try {
      final response = await repository.setProgress(
        item: event.item,
        progress: event.progress,
      );

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not save your progress.'));
    }
  }

  FutureOr<void> _onSetWatchlistStatusEvent(
    SetWatchlistStatusEvent event,
    Emitter<WatchlistState> emit,
  ) async {
    try {
      final response = await repository.setStatus(
        item: event.item,
        status: event.status,
      );

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not update the entry.'));
    }
  }

  FutureOr<void> _onDeleteWatchlistItemEvent(
    DeleteWatchlistItemEvent event,
    Emitter<WatchlistState> emit,
  ) async {
    try {
      final response = await repository.delete(event.id);

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not delete the entry.'));
    }
  }
}
