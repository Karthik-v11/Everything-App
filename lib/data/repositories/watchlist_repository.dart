import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/watchlist_item.dart';
import 'package:everything_app/data/services/watchlist_service.dart';

/// [WatchlistRepository] defines the contract for the Watchlist (Requirement 8).
abstract class WatchlistRepository {
  /// [watchAll] streams every entry, refreshing on any change.
  Stream<List<WatchlistItem>> watchAll();

  /// [create] adds an entry. Fails on a blank title, a rating outside 0–10, or a
  /// total below 1.
  Future<JsonResponse> create(WatchlistItem item);

  /// [update] saves an edited entry, clamping its progress to its total.
  Future<JsonResponse> update(WatchlistItem item);

  /// [setProgress] records how far the user has got, clamped to the total, and
  /// completes the entry when it reaches it (Requirement 8.2, Property 16).
  Future<JsonResponse> setProgress({
    required WatchlistItem item,
    required int progress,
  });

  /// [setStatus] moves an entry, stamping a completion date on Completed
  /// (Requirement 8.3, Property 16).
  Future<JsonResponse> setStatus({
    required WatchlistItem item,
    required WatchStatus status,
  });

  /// [delete] removes an entry by id.
  Future<JsonResponse> delete(String id);
}

class WatchlistRepositoryImpl implements WatchlistRepository {
  const WatchlistRepositoryImpl({required this.watchlistService});

  final WatchlistService watchlistService;

  @override
  Stream<List<WatchlistItem>> watchAll() => watchlistService.watchAll();

  @override
  Future<JsonResponse> create(WatchlistItem item) =>
      watchlistService.create(item);

  @override
  Future<JsonResponse> update(WatchlistItem item) =>
      watchlistService.update(item);

  @override
  Future<JsonResponse> setProgress({
    required WatchlistItem item,
    required int progress,
  }) =>
      watchlistService.setProgress(item: item, progress: progress);

  @override
  Future<JsonResponse> setStatus({
    required WatchlistItem item,
    required WatchStatus status,
  }) =>
      watchlistService.setStatus(item: item, status: status);

  @override
  Future<JsonResponse> delete(String id) => watchlistService.delete(id);
}
