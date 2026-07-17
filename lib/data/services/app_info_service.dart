import 'package:everything_app/data/models/json_response.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// [AppInfoService] reads the app's own identity, for the About section
/// (Requirement 25.1).
///
/// It exists rather than the Settings screen calling [PackageInfo] directly
/// because a platform channel is I/O, and I/O belongs behind a service.
class AppInfoService {
  AppInfoService();

  Future<JsonResponse> read() async {
    try {
      final info = await PackageInfo.fromPlatform();

      return JsonResponse.success(
        message: 'Loaded successfully.',
        data: (
          version: info.version,
          buildNumber: info.buildNumber,
          packageName: info.packageName,
        ),
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not read the app version.',
      );
    }
  }
}
