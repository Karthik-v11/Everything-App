part of 'bookmarks_bloc.dart';

/// [BookmarksEvent] is the base class for every Bookmarks event.
abstract class BookmarksEvent extends Equatable {
  const BookmarksEvent();

  @override
  List<Object?> get props => [];
}

/// [WatchBookmarksEvent] subscribes to the bookmark and folder streams. Fired once.
class WatchBookmarksEvent extends BookmarksEvent {
  const WatchBookmarksEvent();
}

/// [FoldersUpdatedEvent] carries a folder list in from its own subscription.
class FoldersUpdatedEvent extends BookmarksEvent {
  const FoldersUpdatedEvent({required this.folders, this.hasFailed = false});

  final List<Folder> folders;
  final bool hasFailed;

  @override
  List<Object?> get props => [folders, hasFailed];
}

/// [FilterBookmarksEvent] narrows the list by source type and folder.
///
/// A null field clears that filter rather than leaving it alone, so
/// `const FilterBookmarksEvent()` is "show everything".
class FilterBookmarksEvent extends BookmarksEvent {
  const FilterBookmarksEvent({this.source, this.folderId});

  final BookmarkSource? source;
  final String? folderId;

  @override
  List<Object?> get props => [source, folderId];
}

/// [SearchBookmarksEvent] is the in-module search (Requirement 6.3).
class SearchBookmarksEvent extends BookmarksEvent {
  const SearchBookmarksEvent({required this.query});

  final String query;

  @override
  List<Object?> get props => [query];
}

/// [SaveBookmarkEvent] creates or updates, depending on [isEditing].
class SaveBookmarkEvent extends BookmarksEvent {
  const SaveBookmarkEvent({required this.bookmark, this.isEditing = false});

  final Bookmark bookmark;
  final bool isEditing;

  @override
  List<Object?> get props => [bookmark, isEditing];
}

/// [DeleteBookmarkEvent] removes a bookmark.
class DeleteBookmarkEvent extends BookmarksEvent {
  const DeleteBookmarkEvent({required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}

/// [SaveFolderEvent] adds or renames a bookmark folder (Requirement 6.4).
class SaveFolderEvent extends BookmarksEvent {
  const SaveFolderEvent({required this.folder});

  final Folder folder;

  @override
  List<Object?> get props => [folder];
}

/// [DeleteFolderEvent] removes a folder. Its bookmarks are kept.
class DeleteFolderEvent extends BookmarksEvent {
  const DeleteFolderEvent({required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}
