import 'package:everything_app/data/models/bookmark.dart';
import 'package:everything_app/data/models/folder.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/services/bookmarks_service.dart';

/// [BookmarksRepository] defines the contract for bookmark persistence
/// (Requirement 6).
abstract class BookmarksRepository {
  /// [watchAll] streams every bookmark, refreshing on any change.
  Stream<List<Bookmark>> watchAll();

  /// [watchFolders] streams the bookmark folders (Requirement 6.4).
  Stream<List<Folder>> watchFolders();

  /// [create] saves a bookmark from its URL alone, with no network call.
  Future<JsonResponse> create(Bookmark bookmark);

  /// [update] saves an edited bookmark.
  Future<JsonResponse> update(Bookmark bookmark);

  /// [enrich] fetches the page's real title and preview image and writes them
  /// back. Best-effort: its failure means the bookmark keeps what its URL implied.
  Future<JsonResponse> enrich(String id);

  /// [delete] removes a bookmark by id.
  Future<JsonResponse> delete(String id);

  /// [saveFolder] inserts or renames a bookmark folder.
  Future<JsonResponse> saveFolder(Folder folder);

  /// [deleteFolder] removes a folder, keeping its bookmarks.
  Future<JsonResponse> deleteFolder(String id);
}

class BookmarksRepositoryImpl implements BookmarksRepository {
  const BookmarksRepositoryImpl({required this.bookmarksService});

  final BookmarksService bookmarksService;

  @override
  Stream<List<Bookmark>> watchAll() => bookmarksService.watchAll();

  @override
  Stream<List<Folder>> watchFolders() => bookmarksService.watchFolders();

  @override
  Future<JsonResponse> create(Bookmark bookmark) =>
      bookmarksService.create(bookmark);

  @override
  Future<JsonResponse> update(Bookmark bookmark) =>
      bookmarksService.update(bookmark);

  @override
  Future<JsonResponse> enrich(String id) => bookmarksService.enrich(id);

  @override
  Future<JsonResponse> delete(String id) => bookmarksService.delete(id);

  @override
  Future<JsonResponse> saveFolder(Folder folder) =>
      bookmarksService.saveFolder(folder);

  @override
  Future<JsonResponse> deleteFolder(String id) =>
      bookmarksService.deleteFolder(id);
}
