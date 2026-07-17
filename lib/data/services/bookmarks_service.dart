import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/daos/bookmarks_dao.dart';
import 'package:everything_app/data/models/bookmark.dart';
import 'package:everything_app/data/models/folder.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/services/metadata_service.dart';
import 'package:uuid/uuid.dart';

/// [BookmarksService] is the Bookmarks sub-feature's persistence layer
/// (Requirement 6).
///
/// Drift-backed, with one networked side door: [enrich].
class BookmarksService {
  BookmarksService({required this.dao, required this.metadataService});

  final BookmarksDao dao;
  final MetadataService metadataService;

  static const Uuid _uuid = Uuid();

  Stream<List<Bookmark>> watchAll() =>
      dao.watchAll().map((rows) => rows.map(Bookmark.fromEntry).toList());

  Stream<List<Folder>> watchFolders() =>
      dao.watchFolders().map((rows) => rows.map(Folder.fromEntry).toList());

  /// [create] saves a bookmark **without touching the network** (Requirement 6.1).
  ///
  /// The source type, title and thumbnail are all derived from the URL, so the
  /// save is instant and works offline. The real title and preview image are a
  /// later improvement fetched by [enrich]; a save that waited on a page fetch
  /// would fail whenever the page is down.
  Future<JsonResponse> create(Bookmark bookmark) async {
    try {
      if (bookmark.url.isBlank) {
        return JsonResponse.failure(
          statusCode: 400,
          message: 'Paste a link to save.',
        );
      }

      if (!UrlMetadata.isValid(bookmark.url)) {
        return JsonResponse.failure(
          statusCode: 400,
          message: "That doesn't look like a link.",
        );
      }

      final url = UrlMetadata.normalize(bookmark.url);
      final derived = UrlMetadata.read(url);

      final prepared = bookmark.copyWith(
        id: bookmark.id.isBlank ? _uuid.v4() : bookmark.id,
        url: url,
        // A title the user typed is theirs; a blank one is ours to fill in.
        title: bookmark.title.isBlank ? derived.title : bookmark.title.trim(),
        sourceType: derived.source,
        thumbnailUrl: bookmark.thumbnailUrl ?? derived.thumbnailUrl,
        savedAt: DateTime.now(),
      );

      await dao.upsert(prepared.toCompanion());

      return JsonResponse.created(message: 'Bookmark saved.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not save the bookmark.',
      );
    }
  }

  /// [update] saves an edited bookmark, keeping its original [Bookmark.savedAt].
  ///
  /// The source type is re-derived: the URL may have changed, and a link
  /// re-pasted as a YouTube video should stop calling itself an article.
  Future<JsonResponse> update(Bookmark bookmark) async {
    try {
      if (!UrlMetadata.isValid(bookmark.url)) {
        return JsonResponse.failure(
          statusCode: 400,
          message: "That doesn't look like a link.",
        );
      }

      final url = UrlMetadata.normalize(bookmark.url);
      final derived = UrlMetadata.read(url);

      final prepared = bookmark.copyWith(
        url: url,
        title: bookmark.title.isBlank ? derived.title : bookmark.title.trim(),
        sourceType: derived.source,
      );

      await dao.upsert(prepared.toCompanion());

      return JsonResponse.success(message: 'Bookmark updated.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not update the bookmark.',
      );
    }
  }

  /// [enrich] fetches the page's real title and preview image and writes them back
  /// (Requirement 6.1).
  ///
  /// Not an error path: its failure is one the caller is expected to ignore, and
  /// the bookmark keeps the values derived from its URL.
  ///
  /// It re-reads the row before writing — the user may have renamed or deleted the
  /// bookmark while the fetch was in flight, and a late title must not overwrite
  /// one they typed.
  Future<JsonResponse> enrich(String id) async {
    try {
      final existing = await dao.findById(id);
      if (existing == null) {
        return JsonResponse.failure(
          statusCode: 404,
          message: 'That bookmark no longer exists.',
        );
      }

      final bookmark = Bookmark.fromEntry(existing);
      final response = await metadataService.fetch(bookmark.url);

      if (!response.success || response.data is! UrlMetadata) return response;

      final metadata = response.data! as UrlMetadata;
      final derived = UrlMetadata.read(bookmark.url);

      // A title still matching the one guessed from the slug is unclaimed;
      // anything else was typed by the user and is not ours to replace.
      final prepared = bookmark.copyWith(
        title: bookmark.title == derived.title ? metadata.title : bookmark.title,
        thumbnailUrl: bookmark.thumbnailUrl ?? metadata.thumbnailUrl,
      );

      if (prepared == bookmark) {
        return JsonResponse.success(message: 'Nothing to add.', data: bookmark);
      }

      await dao.upsert(prepared.toCompanion());

      return JsonResponse.success(message: 'Bookmark updated.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not read that page.',
      );
    }
  }

  Future<JsonResponse> delete(String id) async {
    try {
      final removed = await dao.deleteById(id);

      return removed == 0
          ? JsonResponse.failure(
              statusCode: 404,
              message: 'That bookmark no longer exists.',
            )
          : JsonResponse.success(message: 'Bookmark deleted.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not delete the bookmark.',
      );
    }
  }

  // ── Folders (Requirement 6.4) ──────────────────────────────────────────────

  Future<JsonResponse> saveFolder(Folder folder) async {
    try {
      if (folder.name.isBlank) {
        return JsonResponse.failure(
          statusCode: 400,
          message: 'A folder needs a name.',
        );
      }

      final prepared = folder.copyWith(
        id: folder.id.isBlank ? _uuid.v4() : folder.id,
        name: folder.name.trim(),
        scope: FolderScope.bookmark,
      );

      await dao.upsertFolder(prepared.toCompanion());

      return JsonResponse.success(message: 'Folder saved.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not save the folder.',
      );
    }
  }

  /// [deleteFolder] removes a folder. Its bookmarks are kept and returned to the
  /// top level — see [BookmarksDao.deleteFolder].
  Future<JsonResponse> deleteFolder(String id) async {
    try {
      await dao.deleteFolder(id);

      return JsonResponse.success(
        message: 'Folder deleted — its bookmarks were kept.',
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not delete the folder.',
      );
    }
  }
}
