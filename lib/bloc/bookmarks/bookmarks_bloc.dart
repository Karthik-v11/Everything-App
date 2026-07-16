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
/// Style A: it holds the bookmark list, the folders, the source filter and the
/// search query.
///
/// It subscribes once to the DAO stream and never re-reads. Filtering, folder
/// grouping and search are derived in memory from that one list, so a bookmark
/// saved in the sheet — or quietly enriched a second later by the metadata fetch —
/// refreshes the list with no reload event anywhere.
///
/// Events:
/// 1) [WatchBookmarksEvent] — subscribe to bookmarks and folders. Fired once.
/// 2) [FoldersUpdatedEvent] — a folder was added, renamed or removed.
/// 3) [FilterBookmarksEvent] — source type and folder narrowing.
/// 4) [SearchBookmarksEvent] — in-module search (Requirement 6.3).
/// 5) [SaveBookmarkEvent] / [DeleteBookmarkEvent] — the sheet and the swipe.
/// 6) [SaveFolderEvent] / [DeleteFolderEvent] — folder management.
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

  /// The folders subscription.
  ///
  /// `emit.forEach` can hold only one stream open for the life of a handler, and
  /// this module has two that never close. The bookmarks take it; the folders are
  /// subscribed separately and re-enter the bloc as [FoldersUpdatedEvent], so their
  /// emission still goes through a handler rather than round an emitter that has
  /// since completed. (Same shape as [FinanceBloc]'s accounts stream.)
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

  /// [_onSaveBookmarkEvent] saves a bookmark and *then* goes looking for its title.
  ///
  /// The two steps are deliberate. The save is local and instant, so the bookmark is
  /// on screen before this handler's first `await` returns — which is what makes
  /// saving a link work identically offline. The enrich that follows is a network
  /// call whose failure is not an error: on a device with no connection it simply
  /// does nothing, and the bookmark keeps the title and thumbnail derived from its
  /// URL. Nothing the user did has failed, so nothing is reported.
  ///
  /// Only on create. Re-fetching on every edit would let a page's title overwrite
  /// the one the user just typed.
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

      // Not awaited into an error path: the stream delivers the enriched row if it
      // lands, and says nothing if it does not.
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
      // No isLoading: the stream returns the updated list within milliseconds, and
      // a spinner over the whole list for a local delete would flicker.
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

      // The filter may have been pointing at the folder that just went away, which
      // would leave the list empty and no way to see anything again.
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
