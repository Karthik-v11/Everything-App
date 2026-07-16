import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/services/storage_service.dart';

/// [StorageRepository] is the contract for the Storage Usage section
/// (Requirement 25.4).
abstract class StorageRepository {
  /// [read] measures the app's storage, broken down by module.
  Future<JsonResponse> read();
}

class StorageRepositoryImpl implements StorageRepository {
  const StorageRepositoryImpl({required this.storageService});

  final StorageService storageService;

  @override
  Future<JsonResponse> read() => storageService.read();
}
