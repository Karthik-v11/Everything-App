part of 'bookmarks_bloc.dart';

/// [BookmarksState] holds everything the Bookmarks screen renders.
///
/// [bookmarks] is the complete list from the database. The filtered list, the
/// counts on the source chips and the folder groupings are all derived from it
/// here, so changing a filter is a recomputation rather than a database round trip
/// and no two figures on the screen can disagree.
class BookmarksState extends Equatable {
  const BookmarksState({
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.bookmarks = const <Bookmark>[],
    this.folders = const <Folder>[],
    this.source,
    this.folderId,
    this.query = '',
  });

  final bool isLoading;
  final String error;
  final String message;
  final List<Bookmark> bookmarks;
  final List<Folder> folders;

  final BookmarkSource? source;
  final String? folderId;
  final String query;

  /// [visibleBookmarks] is the list under the active filters and search query.
  List<Bookmark> get visibleBookmarks => [
        for (final bookmark in bookmarks)
          if (_matches(bookmark)) bookmark,
      ];

  bool _matches(Bookmark bookmark) {
    if (source != null && bookmark.sourceType != source) return false;
    if (folderId != null && bookmark.folderId != folderId) return false;
    if (query.isNotBlank && !bookmark.matches(query)) return false;
    return true;
  }

  /// [isFiltered] tells "you have saved nothing" from "nothing matched", which are
  /// two very different empty states.
  bool get isFiltered =>
      source != null || folderId != null || query.isNotBlank;

  /// [countOf] is how many bookmarks a source type holds — the number on its chip.
  ///
  /// It counts within the *folder* filter but ignores the source filter, so the
  /// chips keep showing what is behind them rather than collapsing to one non-zero
  /// count as soon as one is selected.
  int countOf(BookmarkSource value) {
    var count = 0;
    for (final bookmark in bookmarks) {
      if (bookmark.sourceType != value) continue;
      if (folderId != null && bookmark.folderId != folderId) continue;
      if (query.isNotBlank && !bookmark.matches(query)) continue;
      count++;
    }
    return count;
  }

  /// [sources] are the source types the user actually has bookmarks in — the only
  /// ones worth a chip. A filter row offering "Reddit (0)" is a row of dead ends.
  List<BookmarkSource> get sources => [
        for (final value in BookmarkSource.values)
          if (countOf(value) > 0) value,
      ];

  /// [folderOf] resolves a bookmark's folder, or null when it is at the top level.
  Folder? folderOf(Bookmark bookmark) {
    for (final folder in folders) {
      if (folder.id == bookmark.folderId) return folder;
    }
    return null;
  }

  /// [selectedFolder] is the folder the list is currently narrowed to.
  Folder? get selectedFolder {
    for (final folder in folders) {
      if (folder.id == folderId) return folder;
    }
    return null;
  }

  BookmarksState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    List<Bookmark>? bookmarks,
    List<Folder>? folders,
    BookmarkSource? source,
    bool clearSource = false,
    String? folderId,
    bool clearFolderId = false,
    String? query,
  }) =>
      BookmarksState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        bookmarks: bookmarks ?? this.bookmarks,
        folders: folders ?? this.folders,
        source: clearSource ? null : (source ?? this.source),
        folderId: clearFolderId ? null : (folderId ?? this.folderId),
        query: query ?? this.query,
      );

  @override
  List<Object?> get props => [
        isLoading,
        error,
        message,
        bookmarks,
        folders,
        source,
        folderId,
        query,
      ];
}
