import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/shared_item.dart';
import 'package:everything_app/data/services/share_service.dart';

/// [ShareRepository] is the contract for content shared into the app from another
/// app (Requirement 12).
abstract class ShareRepository {
  /// [initial] is the share that launched the app, or an empty list on a normal
  /// launch.
  Future<JsonResponse> initial();

  /// [stream] is every share that arrives while the app is already running.
  Stream<List<SharedItem>> stream();

  /// [reset] marks the pending share as handled, so it is not replayed on the
  /// next launch.
  Future<void> reset();
}

class ShareRepositoryImpl implements ShareRepository {
  const ShareRepositoryImpl({required this.shareService});

  final ShareService shareService;

  @override
  Future<JsonResponse> initial() => shareService.initial();

  @override
  Stream<List<SharedItem>> stream() => shareService.stream();

  @override
  Future<void> reset() => shareService.reset();
}
