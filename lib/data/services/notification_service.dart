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
/// It keeps the standard service contract — every method returns [JsonResponse]
/// and nothing throws past this layer — so a device that has revoked the
/// permission, or an Android build that forbids exact alarms, degrades into a
/// failure message rather than an exception in a bloc.
///
/// The plugin is injected rather than constructed here so that the reconciliation
/// logic can be tested against a fake.
class NotificationService {
  NotificationService({required this.plugin});

  final FlutterLocalNotificationsPlugin plugin;

  /// Two channels, not five: the user wants to silence "the summaries" or "the
  /// task alerts", not each of the five kinds separately, and every channel added
  /// here is permanent — Android will not let one be removed once it has shipped.
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

  /// Its own channel rather than the task one: a reminder to buy something is not
  /// a task alert, and a user who silences their task reminders has not asked to
  /// stop hearing that the thing they wanted is worth going out for.
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
  /// Timezones are set up here rather than in `start.dart` so that nothing pays
  /// for the timezone database unless notifications are actually used, and so
  /// that the bootstrap stays untouched (CLAUDE.md §1).
  ///
  /// `zonedSchedule` needs a real IANA zone: scheduling in UTC would fire a 9am
  /// reminder at the wrong hour for everyone outside London, and scheduling in
  /// local wall-clock time without a zone would drift across a DST boundary.
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
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // All three are requested explicitly from Settings, not silently on
          // first launch: a permission prompt the user did not ask for is the
          // one they deny.
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
  /// Exact alarms are requested **separately and second**: on Android that opens
  /// a system settings page rather than a dialog, and asking for it before the
  /// user has even agreed to notifications reads as hostile.
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
  /// This is a reconciliation, not a rewrite: what is already scheduled and still
  /// wanted is left alone. Cancelling everything and rescheduling would be far
  /// simpler, but it would drop and re-arm every alarm on every keystroke-driven
  /// task write, and on Android each re-arm is a real `AlarmManager` round trip.
  ///
  /// The OS is the only store. It reports what is pending; each pending
  /// notification carries its own definition in its payload, so a plan built now
  /// can be compared against a queue armed by a previous run of the app. Anything
  /// pending that the plan does not contain — a reminder on a task since
  /// completed, deleted, or rescheduled — is cancelled, which is what makes it
  /// impossible for the queue to drift from the database.
  ///
  /// [owns] is which kinds this plan speaks for, and it is what lets more than one
  /// module schedule reminders at all. The cancel-what-I-did-not-ask-for rule is
  /// the whole mechanism above, so a reconciler that read the *entire* queue would
  /// cancel every notification belonging to a module other than its own: the Tasks
  /// sync would withdraw the to-buy reminders, the To-Buy sync would withdraw the
  /// task reminders, and the last write would win until the next one undid it. A
  /// caller therefore reconciles only the kinds it owns and does not touch a
  /// pending notification that is not one of them.
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

        // Undecodable means it was scheduled by a build of the app that wrote a
        // different payload. It can never be matched — by this reconciler or any
        // other — so it is dropped rather than left to fire something the app can
        // no longer explain. Every reconciler applies this, which is harmless:
        // the first one to run clears it and the rest find nothing.
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

  /// [show] delivers a notification **now** (Requirements 14.3, 14.4, 14.5).
  ///
  /// This is the budget alerts' path, and the only one that does not go through
  /// [applyPlan]. A budget alert has no future moment to be scheduled at: it
  /// becomes true the instant the user saves the transaction that makes it true,
  /// and a plan can only describe things that have not happened yet.
  ///
  /// It therefore never enters the pending queue, so [applyPlan]'s reconciliation
  /// neither sees it nor cancels it. Deciding whether an alert is news or a repeat
  /// is the caller's job — the OS remembers nothing here (see [BudgetBloc]).
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
          // A budget alert reports something that already happened; the reminder
          // category is for something the user still has to do.
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
  /// `zonedSchedule` **throws** if asked for one without it. Falling back to
  /// inexact means a reminder can be a few minutes late; asking anyway means it
  /// never arrives at all. A summary is a digest, so it takes the inexact,
  /// battery-cheap path either way.
  AndroidScheduleMode _scheduleModeFor(NotificationKind kind) {
    if (kind.isSummary) return AndroidScheduleMode.inexactAllowWhileIdle;

    return _canScheduleExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }
}
