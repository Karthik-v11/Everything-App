import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/to_buy_item.dart';
import 'package:everything_app/data/services/to_buy_service.dart';

/// [ToBuyRepository] defines the contract for the To Buy list (Requirement 7).
abstract class ToBuyRepository {
  /// [watchAll] streams the whole list, purchased items included — the reminder
  /// plan needs to see a purchased item to know its alarm should be withdrawn.
  Stream<List<ToBuyItem>> watchAll();

  /// [create] adds an item. Fails on a blank name or a negative price.
  Future<JsonResponse> create(ToBuyItem item);

  /// [update] saves an edited item.
  Future<JsonResponse> update(ToBuyItem item);

  /// [setPurchased] ticks an item off, or puts it back (Requirement 7.2).
  Future<JsonResponse> setPurchased({
    required ToBuyItem item,
    required bool isPurchased,
  });

  /// [delete] removes an item by id.
  Future<JsonResponse> delete(String id);
}

class ToBuyRepositoryImpl implements ToBuyRepository {
  const ToBuyRepositoryImpl({required this.toBuyService});

  final ToBuyService toBuyService;

  @override
  Stream<List<ToBuyItem>> watchAll() => toBuyService.watchAll();

  @override
  Future<JsonResponse> create(ToBuyItem item) => toBuyService.create(item);

  @override
  Future<JsonResponse> update(ToBuyItem item) => toBuyService.update(item);

  @override
  Future<JsonResponse> setPurchased({
    required ToBuyItem item,
    required bool isPurchased,
  }) =>
      toBuyService.setPurchased(item: item, isPurchased: isPurchased);

  @override
  Future<JsonResponse> delete(String id) => toBuyService.delete(id);
}
