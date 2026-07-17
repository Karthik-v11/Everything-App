import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/daos/to_buy_dao.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/to_buy_item.dart';
import 'package:uuid/uuid.dart';

/// [ToBuyService] is the To Buy list's persistence layer (Requirement 7).
class ToBuyService {
  ToBuyService({required this.dao});

  final ToBuyDao dao;

  static const Uuid _uuid = Uuid();

  Stream<List<ToBuyItem>> watchAll() =>
      dao.watchAll().map((rows) => rows.map(ToBuyItem.fromEntry).toList());

  Future<JsonResponse> create(ToBuyItem item) async {
    try {
      final invalid = _validate(item);
      if (invalid != null) return invalid;

      final prepared = item.copyWith(
        id: item.id.isBlank ? _uuid.v4() : item.id,
        name: item.name.trim(),
        createdAt: DateTime.now(),
      );

      await dao.upsert(prepared.toCompanion());

      return JsonResponse.created(message: 'Added to your list.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not save the item.',
      );
    }
  }

  Future<JsonResponse> update(ToBuyItem item) async {
    try {
      final invalid = _validate(item);
      if (invalid != null) return invalid;

      final prepared = item.copyWith(name: item.name.trim());

      await dao.upsert(prepared.toCompanion());

      return JsonResponse.success(message: 'Item updated.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not update the item.',
      );
    }
  }

  /// [setPurchased] ticks an item off (Requirement 7.2).
  ///
  /// It deliberately does not cancel the item's reminder: [ToBuyPlan] reconciles
  /// reminders from the list and does not plan for a purchased item, so the alarm
  /// is withdrawn on the next sync without this code knowing alarms exist.
  Future<JsonResponse> setPurchased({
    required ToBuyItem item,
    required bool isPurchased,
  }) async {
    try {
      final prepared = item.copyWith(isPurchased: isPurchased);

      await dao.upsert(prepared.toCompanion());

      return JsonResponse.success(
        message: isPurchased ? 'Marked as bought.' : 'Back on your list.',
        data: prepared,
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not update the item.',
      );
    }
  }

  Future<JsonResponse> delete(String id) async {
    try {
      final removed = await dao.deleteById(id);

      return removed == 0
          ? JsonResponse.failure(
              statusCode: 404,
              message: 'That item no longer exists.',
            )
          : JsonResponse.success(message: 'Item deleted.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not delete the item.',
      );
    }
  }

  /// [_validate] holds the rules every entry point is subject to — the sheet, the
  /// AI parser, the share intent.
  JsonResponse? _validate(ToBuyItem item) {
    if (item.name.isBlank) {
      return JsonResponse.failure(
        statusCode: 400,
        message: 'What do you want to buy?',
      );
    }

    final price = item.estimatedPriceMinor;
    if (price != null && price < 0) {
      return JsonResponse.failure(
        statusCode: 400,
        message: 'A price cannot be negative.',
      );
    }

    return null;
  }
}
