import 'package:everything_app/data/models/home_widget_payload.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/services/home_widget_service.dart';

/// [HomeWidgetRepository] is the contract for the home screen widgets
/// (Requirement 13).
abstract class HomeWidgetRepository {
  /// [initialize] registers the shared container.
  Future<JsonResponse> initialize();

  /// [push] publishes [payload] to the home screen.
  Future<JsonResponse> push(HomeWidgetPayload payload);

  /// [clear] removes the published data from the shared container.
  Future<JsonResponse> clear();

  /// [initialTap] is the widget tap that launched the app, if one did.
  Future<JsonResponse> initialTap();

  /// [taps] is every widget tap while the app is already running.
  Stream<Uri?> taps();
}

class HomeWidgetRepositoryImpl implements HomeWidgetRepository {
  const HomeWidgetRepositoryImpl({required this.homeWidgetService});

  final HomeWidgetService homeWidgetService;

  @override
  Future<JsonResponse> initialize() => homeWidgetService.initialize();

  @override
  Future<JsonResponse> push(HomeWidgetPayload payload) =>
      homeWidgetService.push(payload);

  @override
  Future<JsonResponse> clear() => homeWidgetService.clear();

  @override
  Future<JsonResponse> initialTap() => homeWidgetService.initialTap();

  @override
  Stream<Uri?> taps() => homeWidgetService.taps();
}
