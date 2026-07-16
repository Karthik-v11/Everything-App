import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/notification_settings.dart';
import 'package:everything_app/data/models/scheduled_notification.dart';
import 'package:everything_app/data/services/notification_service.dart';

/// [NotificationsRepository] defines the contract for scheduling notifications.
abstract class NotificationsRepository {
  /// [initialize] prepares the timezone database, the plugin and the channels.
  /// Safe to call more than once.
  Future<JsonResponse> initialize();

  /// [permissions] reports `(isGranted, canScheduleExact)`.
  Future<JsonResponse> permissions();

  /// [requestPermission] asks the user to allow notifications, and on Android
  /// 14+ to allow exact alarms.
  Future<JsonResponse> requestPermission();

  /// [applyPlan] makes the caller's slice of the OS queue match [plan] exactly,
  /// cancelling anything pending of a kind in [owns] that the plan no longer
  /// contains, and leaving every other module's notifications alone.
  Future<JsonResponse> applyPlan(
    List<ScheduledNotification> plan, {
    required Set<NotificationKind> owns,
  });

  /// [show] delivers a notification immediately, for an alert that is about
  /// something that has already happened rather than something that is due.
  Future<JsonResponse> show({
    required int id,
    required NotificationKind kind,
    required String title,
    required String body,
  });

  /// [cancelAll] clears every pending notification.
  Future<JsonResponse> cancelAll();
}

class NotificationsRepositoryImpl implements NotificationsRepository {
  const NotificationsRepositoryImpl({required this.notificationService});

  final NotificationService notificationService;

  @override
  Future<JsonResponse> initialize() => notificationService.initialize();

  @override
  Future<JsonResponse> permissions() => notificationService.permissions();

  @override
  Future<JsonResponse> requestPermission() =>
      notificationService.requestPermission();

  @override
  Future<JsonResponse> applyPlan(
    List<ScheduledNotification> plan, {
    required Set<NotificationKind> owns,
  }) =>
      notificationService.applyPlan(plan, owns: owns);

  @override
  Future<JsonResponse> show({
    required int id,
    required NotificationKind kind,
    required String title,
    required String body,
  }) =>
      notificationService.show(id: id, kind: kind, title: title, body: body);

  @override
  Future<JsonResponse> cancelAll() => notificationService.cancelAll();
}
