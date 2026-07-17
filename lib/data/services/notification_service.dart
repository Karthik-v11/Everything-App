import 'dart:io';

import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/notification_settings.dart';
import 'package:everything_app/data/models/scheduled_notification.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// [NotificationService] is the app's only contact with the OS notification
/// queue (Requirement 5).
///
/// Every method returns [JsonResponse] and nothing throws past this layer, so a
/// revoked permission or a build that forbids exact alarms degrades into a
/// failure message rather than an exception in a bloc.
class NotificationService {
  NotificationService({required this.plugin});

  final FlutterLocalNotificationsPlugin plugin;

  /// Channels are grouped by what a user would silence, not per kind. Every
  /// channel added here is permanent — Android cannot remove one once shipped.
  static const AndroidNotificationChannel _tasksChannel =
      AndroidNotificationChannel(
    'tasks',
    'Task alerts',
    description: 'Reminders, deadlines and missed tasks.',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _summariesChannel =
      AndroidNotificationChannel(
    'summaries',
    'Summaries',
    description: 'Your daily and weekly task digests.',
    importance: Importance.defaultImportance,
  );

  static const AndroidNotificationChannel _budgetsChannel =
      AndroidNotificationChannel(
    'budgets',
    'Budget alerts',
    description: 'When your spending approaches or passes a budget.',
    importance: Importance.high,
  );

  /// Its own channel: silencing task reminders must not silence shopping ones.
  static const AndroidNotificationChannel _toBuyChannel =
      AndroidNotificationChannel(
    'to_buy',
    'Shopping reminders',
    description: 'Reminders on the things you want to buy.',
    importance: Importance.high,
  );

  bool _isInitialized = false;

  /// Whether the OS will honour an exact alarm. False on an Android 14+ device
  /// that has not granted it, which downgrades scheduling to inexact rather than
  /// failing (see [_scheduleModeFor]).
  bool _canScheduleExact = true;

  /// [initialize] prepares the timezone database, the plugin and the channels.
  ///
  /// `zonedSchedule` needs a real IANA zone: UTC fires reminders at the wrong
  /// local hour, and local wall-clock without a zone drifts across DST.
  Future<JsonResponse> initialize() async {
    if (_isInitialized) {
      return JsonResponse.success(message: 'Notifications ready.');
    }

    try {
      tz.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));

      await plugin.initialize(
        settings: const InitializationSettings(
          // Android masks the status-bar icon to its alpha channel, so the
          // full-colour launcher bitmap would render as a solid white square.
          android: AndroidInitializationSettings('@drawable/ic_stat_everything'),
          // Requested explicitly from Settings, not silently on first launch.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );

      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (android != null) {
        await android.createNotificationChannel(_tasksChannel);
        await android.createNotificationChannel(_summariesChannel);
        await android.createNotificationChannel(_budgetsChannel);
        await android.createNotificationChannel(_toBuyChannel);
        _canScheduleExact =
            await android.canScheduleExactNotifications() ?? false;
      }

      _isInitialized = true;

      return JsonResponse.success(message: 'Notifications ready.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not set up notifications.',
      );
    }
  }

  /// [permissions] reports whether the app may post notifications at all, and
  /// whether it may schedule them exactly.
  ///
  /// Returns a `(isGranted, canScheduleExact)` record as its data.
  Future<JsonResponse> permissions() async {
    try {
      if (Platform.isAndroid) {
        final android = plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

        final isGranted = await android?.areNotificationsEnabled() ?? false;
        _canScheduleExact =
            await android?.canScheduleExactNotifications() ?? false;

        return JsonResponse.success(
          message: 'Loaded successfully.',
          data: (isGranted: isGranted, canScheduleExact: _canScheduleExact),
        );
      }

      final ios = plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      final options = await ios?.checkPermissions();

      // iOS has no exact-alarm concept — a scheduled notification is exact.
      return JsonResponse.success(
        message: 'Loaded successfully.',
        data: (
          isGranted: options?.isEnabled ?? false,
          canScheduleExact: true,
        ),
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not read the notification permission.',
      );
    }
  }

  /// [requestPermission] asks the user for the notification permission, and on
  /// Android 14+ for the exact-alarm permission that reminders depend on.
  ///
  /// Exact alarms are requested separately and second: on Android that opens a
  /// system settings page rather than a dialog.
  Future<JsonResponse> requestPermission() async {
    try {
      if (Platform.isAndroid) {
        final android = plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

        final isGranted =
            await android?.requestNotificationsPermission() ?? false;

        if (!isGranted) {
          return JsonResponse.failure(
            statusCode: 403,
            message: 'Notifications are turned off for this app.',
          );
        }

        _canScheduleExact =
            await android?.canScheduleExactNotifications() ?? false;

        if (!_canScheduleExact) {
          await android?.requestExactAlarmsPermission();
          _canScheduleExact =
              await android?.canScheduleExactNotifications() ?? false;
        }

        return JsonResponse.success(message: 'Notifications are on.');
      }

      final ios = plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      final isGranted = await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;

      return isGranted
          ? JsonResponse.success(message: 'Notifications are on.')
          : JsonResponse.failure(
              statusCode: 403,
              message: 'Notifications are turned off for this app.',
            );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not turn on notifications.',
      );
    }
  }

  /// [applyPlan] makes the app's slice of the OS queue match [plan] exactly.
  ///
  /// A reconciliation, not a rewrite: what is already scheduled and still wanted
  /// is left alone, because each re-arm is an `AlarmManager` round trip on
  /// Android and every task write would pay for it.
  ///
  /// The OS is the only store; each pending notification carries its definition
  /// in its payload, so a plan can be compared against a queue armed by a
  /// previous run. Anything pending the plan does not contain is cancelled,
  /// which is what stops the queue drifting from the database.
  ///
  /// [owns] scopes that rule to the kinds this caller speaks for. A reconciler
  /// reading the entire queue would cancel other modules' notifications, so each
  /// one touches only the kinds it owns.
  Future<JsonResponse> applyPlan(
    List<ScheduledNotification> plan, {
    required Set<NotificationKind> owns,
  }) async {
    try {
      final desired = {
        for (final item in plan)
          if (owns.contains(item.kind)) item.id: item,
      };
      final pending = await plugin.pendingNotificationRequests();

      var cancelled = 0;
      var scheduled = 0;

      final live = <int, ScheduledNotification>{};

      for (final request in pending) {
        final existing = ScheduledNotification.decode(request.payload);

        // Undecodable means an older build wrote a different payload. It can
        // never be matched by any reconciler, so it is dropped rather than left
        // to fire something the app can no longer explain.
        if (existing == null || existing.id != request.id) {
          await plugin.cancel(id: request.id);
          cancelled++;
          continue;
        }

        // Somebody else's notification. Not ours to cancel, not ours to keep.
        if (!owns.contains(existing.kind)) continue;

        live[request.id] = existing;
      }

      for (final entry in live.entries) {
        if (desired[entry.key] == entry.value) continue;

        // Either no longer wanted, or wanted with a different time or wording.
        // Both are a cancel; the reschedule below re-adds the changed ones.
        await plugin.cancel(id: entry.key);
        cancelled++;
      }

      for (final item in desired.values) {
        if (live[item.id] == item) continue;

        await _schedule(item);
        scheduled++;
      }

      return JsonResponse.success(
        message: 'Reminders up to date.',
        data: (scheduled: scheduled, cancelled: cancelled),
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not update your reminders.',
      );
    }
  }

  /// [show] delivers a notification now (Requirements 14.3, 14.4, 14.5).
  ///
  /// The budget alerts' path: a budget alert has no future moment to schedule
  /// at, so it never enters the pending queue and [applyPlan] neither sees nor
  /// cancels it. Deciding whether an alert is news or a repeat is the caller's
  /// job — the OS remembers nothing here (see [BudgetBloc]).
  Future<JsonResponse> show({
    required int id,
    required NotificationKind kind,
    required String title,
    required String body,
  }) async {
    try {
      await plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _detailsFor(kind),
      );

      return JsonResponse.success(message: 'Notification delivered.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not deliver the notification.',
      );
    }
  }

  /// [cancelAll] clears the queue — used when notifications are switched off.
  Future<JsonResponse> cancelAll() async {
    try {
      await plugin.cancelAll();
      return JsonResponse.success(message: 'Reminders cleared.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not clear your reminders.',
      );
    }
  }

  Future<void> _schedule(ScheduledNotification notification) => plugin
      .zonedSchedule(
        id: notification.id,
        title: notification.title,
        body: notification.body,
        scheduledDate: tz.TZDateTime.from(notification.at, tz.local),
        notificationDetails: _detailsFor(notification.kind),
        androidScheduleMode: _scheduleModeFor(notification.kind),
        payload: notification.payload,
      );

  NotificationDetails _detailsFor(NotificationKind kind) {
    final channel = switch (kind) {
      _ when kind.isSummary => _summariesChannel,
      _ when kind.isBudget => _budgetsChannel,
      NotificationKind.toBuyReminder => _toBuyChannel,
      _ => _tasksChannel,
    };

    return NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: channel.importance,
        priority: kind.isSummary ? Priority.defaultPriority : Priority.high,
        category: switch (kind) {
          _ when kind.isSummary => AndroidNotificationCategory.status,
          // A budget alert reports what already happened; reminder is for
          // something the user still has to do.
          _ when kind.isBudget => AndroidNotificationCategory.event,
          _ => AndroidNotificationCategory.reminder,
        },
      ),
      iOS: DarwinNotificationDetails(
        interruptionLevel: kind.isSummary
            ? InterruptionLevel.passive
            : InterruptionLevel.timeSensitive,
      ),
    );
  }

  /// [_scheduleModeFor] picks the strongest alarm the OS will actually grant.
  ///
  /// An exact alarm on Android 14+ needs a permission the user can refuse, and
  /// `zonedSchedule` throws if asked for one without it. Summaries are digests
  /// and take the inexact, battery-cheap path either way.
  AndroidScheduleMode _scheduleModeFor(NotificationKind kind) {
    if (kind.isSummary) return AndroidScheduleMode.inexactAllowWhileIdle;

    return _canScheduleExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }
}
