import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/models/bookmark.dart';
import 'package:everything_app/data/models/folder.dart';
import 'package:everything_app/data/repositories/bookmarks_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'bookmarks_event.dart';
part 'bookmarks_state.dart';

/// [BookmarksBloc] owns the Bookmarks sub-feature (Requirement 6).
///
/// It subscribes once to the DAO stream and never re-reads: filtering, folder
/// grouping and search (Requirement 6.3) are derived in memory from that one
/// list, so a save — or a later metadata enrich — refreshes the list with no
/// reload event anywhere.
class BookmarksBloc extends Bloc<BookmarksEvent, BookmarksState> {
  BookmarksBloc({required this.repository}) : super(const BookmarksState()) {
    on<WatchBookmarksEvent>(_onWatchBookmarksEvent);
    on<FoldersUpdatedEvent>(_onFoldersUpdatedEvent);
    on<FilterBookmarksEvent>(_onFilterBookmarksEvent);
    on<SearchBookmarksEvent>(_onSearchBookmarksEvent);
    on<SaveBookmarkEvent>(_onSaveBookmarkEvent);
    on<DeleteBookmarkEvent>(_onDeleteBookmarkEvent);
    on<SaveFolderEvent>(_onSaveFolderEvent);
    on<DeleteFolderEvent>(_onDeleteFolderEvent);
  }

  final BookmarksRepository repository;

  /// The folders subscription. `emit.forEach` can hold only one stream per
  /// handler, which the bookmarks take; folders are subscribed separately and
  /// re-enter as [FoldersUpdatedEvent] rather than emitting round a completed
  /// emitter.
  StreamSubscription<List<Folder>>? _folders;

  FutureOr<void> _onWatchBookmarksEvent(
    WatchBookmarksEvent event,
    Emitter<BookmarksState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: '', message: ''));

    await _folders?.cancel();
    _folders = repository.watchFolders().listen(
          (folders) => add(FoldersUpdatedEvent(folders: folders)),
          onError: (_) => add(
            const FoldersUpdatedEvent(folders: <Folder>[], hasFailed: true),
          ),
        );

    await emit.forEach<List<Bookmark>>(
      repository.watchAll(),
      onData: (bookmarks) => state.copyWith(
        isLoading: false,
        bookmarks: bookmarks,
        error: '',
      ),
      onError: (_, _) => state.copyWith(
        isLoading: false,
        error: 'Could not load your bookmarks.',
      ),
    );
  }

  FutureOr<void> _onFoldersUpdatedEvent(
    FoldersUpdatedEvent event,
    Emitter<BookmarksState> emit,
  ) {
    emit(
      event.hasFailed
          ? state.copyWith(error: 'Could not load your folders.')
          : state.copyWith(folders: event.folders, error: ''),
    );
  }

  FutureOr<void> _onFilterBookmarksEvent(
    FilterBookmarksEvent event,
    Emitter<BookmarksState> emit,
  ) {
    emit(
      state.copyWith(
        source: event.source,
        clearSource: event.source == null,
        folderId: event.folderId,
        clearFolderId: event.folderId == null,
      ),
    );
  }

  FutureOr<void> _onSearchBookmarksEvent(
    SearchBookmarksEvent event,
    Emitter<BookmarksState> emit,
  ) {
    emit(state.copyWith(query: event.query));
  }

  /// [_onSaveBookmarkEvent] saves locally, then enriches over the network.
  ///
  /// The enrich is best-effort and its failure is never reported: offline, the
  /// bookmark keeps the title and thumbnail derived from its URL. It runs only on
  /// create — re-fetching on edit would overwrite the title the user just typed.
  FutureOr<void> _onSaveBookmarkEvent(
    SaveBookmarkEvent event,
    Emitter<BookmarksState> emit,
  ) async {
    try {
      final response = event.isEditing
          ? await repository.update(event.bookmark)
          : await repository.create(event.bookmark);

      if (!response.success) {
        emit(state.copyWith(error: response.message, message: ''));
        return;
      }

      emit(state.copyWith(message: response.message, error: ''));

      if (event.isEditing) return;

      final saved = response.data;
      if (saved is! Bookmark) return;

      // Failure is not surfaced: the stream delivers the enriched row if it lands.
      await repository.enrich(saved.id);
    } on Exception {
      emit(state.copyWith(error: 'Could not save the bookmark.'));
    }
  }

  FutureOr<void> _onDeleteBookmarkEvent(
    DeleteBookmarkEvent event,
    Emitter<BookmarksState> emit,
  ) async {
    try {
      // No isLoading: a spinner over the list for a local delete would flicker.
      final response = await repository.delete(event.id);

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not delete the bookmark.'));
    }
  }

  FutureOr<void> _onSaveFolderEvent(
    SaveFolderEvent event,
    Emitter<BookmarksState> emit,
  ) async {
    try {
      final response = await repository.saveFolder(event.folder);

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not save the folder.'));
    }
  }

  FutureOr<void> _onDeleteFolderEvent(
    DeleteFolderEvent event,
    Emitter<BookmarksState> emit,
  ) async {
    try {
      final response = await repository.deleteFolder(event.id);

      // Clear the filter if it pointed at the deleted folder, or the list is stuck
      // empty with no way back.
      emit(
        response.success
            ? state.copyWith(
                message: response.message,
                error: '',
                clearFolderId: state.folderId == event.id,
              )
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not delete the folder.'));
    }
  }

  @override
  Future<void> close() {
    _folders?.cancel();
    return super.close();
  }
}
