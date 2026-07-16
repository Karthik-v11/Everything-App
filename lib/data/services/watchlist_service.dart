import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/daos/watchlist_dao.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/watchlist_item.dart';
import 'package:uuid/uuid.dart';

/// [WatchlistService] is the Watchlist's persistence layer (Requirement 8).
///
/// Every write here goes through [WatchlistItem.withProgress] or
/// [WatchlistItem.withStatus] rather than assembling a row by hand. Those two
/// methods are where Property 16 lives — progress never exceeds a defined total,
/// and Completed always carries a date — and routing every write through them is
/// what makes the property hold for writes this service has not been written for
/// yet.
class WatchlistService {
  WatchlistService({required this.dao});

  final WatchlistDao dao;

  static const Uuid _uuid = Uuid();

  Stream<List<WatchlistItem>> watchAll() =>
      dao.watchAll().map((rows) => rows.map(WatchlistItem.fromEntry).toList());

  Future<JsonResponse> create(WatchlistItem item) async {
    try {
      final invalid = _validate(item);
      if (invalid != null) return invalid;

      // Through withStatus, so an entry added as already-Completed is stamped with
      // a completion date rather than being the one row in the table that has none
      // (Requirement 8.3).
      final prepared = item
          .copyWith(
            id: item.id.isBlank ? _uuid.v4() : item.id,
            title: item.title.trim(),
            createdAt: DateTime.now(),
          )
          .withStatus(item.status);

      await dao.upsert(prepared.toCompanion());

      return JsonResponse.created(message: 'Added to your list.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not save the entry.',
      );
    }
  }

  /// [update] saves an edited entry.
  ///
  /// It re-applies the status and the progress through the model rather than
  /// trusting what the form built: the user may have lowered the total below the
  /// progress they had already made, and 14/12 must not reach the database
  /// (Property 16).
  Future<JsonResponse> update(WatchlistItem item) async {
    try {
      final invalid = _validate(item);
      if (invalid != null) return invalid;

      final prepared = item
          .copyWith(title: item.title.trim())
          .withStatus(item.status)
          .withProgress(item.currentProgress ?? 0);

      await dao.upsert(prepared.toCompanion());

      return JsonResponse.success(message: 'Entry updated.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not update the entry.',
      );
    }
  }

  /// [setProgress] records how far the user has got (Requirement 8.2).
  ///
  /// Clamped to the total, and reaching the total completes the entry with a date —
  /// both in [WatchlistItem.withProgress], so the stepper on the card and the field
  /// in the sheet cannot disagree about what finishing something means.
  Future<JsonResponse> setProgress({
    required WatchlistItem item,
    required int progress,
  }) async {
    try {
      final prepared = item.withProgress(progress);

      await dao.upsert(prepared.toCompanion());

      return JsonResponse.success(
        message: prepared.isCompleted && !item.isCompleted
            ? 'Finished — nice.'
            : 'Progress saved.',
        data: prepared,
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not save your progress.',
      );
    }
  }

  /// [setStatus] moves an entry between Wishlist / Watching / Completed / Dropped
  /// (Requirement 8.3).
  Future<JsonResponse> setStatus({
    required WatchlistItem item,
    required WatchStatus status,
  }) async {
    try {
      final prepared = item.withStatus(status);

      await dao.upsert(prepared.toCompanion());

      return JsonResponse.success(
        message: 'Moved to ${status.label}.',
        data: prepared,
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not update the entry.',
      );
    }
  }

  Future<JsonResponse> delete(String id) async {
    try {
      final removed = await dao.deleteById(id);

      return removed == 0
          ? JsonResponse.failure(
              statusCode: 404,
              message: 'That entry no longer exists.',
            )
          : JsonResponse.success(message: 'Entry deleted.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not delete the entry.',
      );
    }
  }

  JsonResponse? _validate(WatchlistItem item) {
    if (item.title.isBlank) {
      return JsonResponse.failure(
        statusCode: 400,
        message: 'What are you tracking?',
      );
    }

    final rating = item.rating;
    if (rating != null && (rating < 0 || rating > 10)) {
      return JsonResponse.failure(
        statusCode: 400,
        message: 'A rating runs from 0 to 10.',
      );
    }

    final total = item.total;
    if (total != null && total <= 0) {
      return JsonResponse.failure(
        statusCode: 400,
        message: 'A total has to be at least 1.',
      );
    }

    return null;
  }
}
