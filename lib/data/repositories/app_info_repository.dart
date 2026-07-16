import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/services/app_info_service.dart';

/// [AppInfoRepository] is the contract for the app's own identity, shown in the
/// About section (Requirement 25.1).
abstract class AppInfoRepository {
  /// [read] returns the version, build number and package name.
  Future<JsonResponse> read();
}

class AppInfoRepositoryImpl implements AppInfoRepository {
  const AppInfoRepositoryImpl({required this.appInfoService});

  final AppInfoService appInfoService;

  @override
  Future<JsonResponse> read() => appInfoService.read();
}
