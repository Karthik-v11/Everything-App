import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/notification_settings.dart';
import 'package:everything_app/data/models/scheduled_notification.dart';
import 'package:everything_app/data/services/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// [_FakePlugin] is the OS notification queue: a map of what is currently
/// pending.
///
/// It behaves like the real queue rather than merely recording calls — a schedule
/// adds a pending request carrying its payload, a cancel removes it — because
/// that behaviour is exactly what reconciliation reads back and depends on.
class _FakePlugin implements FlutterLocalNotificationsPlugin {
  final Map<int, PendingNotificationRequest> pending = {};

  final List<int> cancelled = [];
  final List<int> scheduled = [];

  void seed(ScheduledNotification notification) {
    pending[notification.id] = PendingNotificationRequest(
      notification.id,
      notification.title,
      notification.body,
      notification.payload,
    );
  }

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async =>
      pending.values.toList();

  @override
  Future<void> cancel({required int id, String? tag}) async {
    pending.remove(id);
    cancelled.add(id);
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    pending[id] = PendingNotificationRequest(id, title, body, payload);
    scheduled.add(id);
  }

  @override
  Future<void> cancelAll() async => pending.clear();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Reconciliation between the app's plan and the OS's queue.
///
/// This is the part of notifications that fails silently. A reminder left armed
/// for a deleted task, or every alarm cancelled and re-armed on each keystroke,
/// both look like a perfectly working app right up until the user's phone buzzes
/// for something they finished last week.
void main() {
  late _FakePlugin plugin;
  late NotificationService service;

  setUpAll(() {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  });

  setUp(() {
    plugin = _FakePlugin();
    service = NotificationService(plugin: plugin);
  });

  ScheduledNotification notification({
    String seed = 'deadline:task-1',
    String title = 'Buy milk',
    DateTime? at,
    String? taskId = 'task-1',
    NotificationKind kind = NotificationKind.deadline,
  }) =>
      ScheduledNotification(
        id: ScheduledNotification.idFor(seed),
        kind: kind,
        title: title,
        body: 'Due now.',
        at: at ?? DateTime(2026, 8, 1, 9),
        taskId: taskId,
      );

  /// Every test below reconciles as the Tasks module does, which is what makes
  /// the partition test at the bottom mean something.
  Future<JsonResponse> apply(List<ScheduledNotification> plan) =>
      service.applyPlan(plan, owns: NotificationKind.taskKinds);

  test('an empty queue is filled from the plan', () async {
    final plan = [
      notification(seed: 'deadline:a', taskId: 'a'),
      notification(seed: 'deadline:b', taskId: 'b'),
    ];

    final response = await apply(plan);

    expect(response.success, isTrue, reason: response.message);
    expect(plugin.pending.keys.toSet(), plan.map((item) => item.id).toSet());
  });

  test('applying the same plan twice changes nothing the second time', () async {
    final plan = [notification()];

    await apply(plan);
    plugin.scheduled.clear();
    plugin.cancelled.clear();

    await apply(plan);

    // The whole point of reconciling rather than rewriting: an unchanged task
    // list must not re-arm a single alarm.
    expect(plugin.scheduled, isEmpty);
    expect(plugin.cancelled, isEmpty);
    expect(plugin.pending, hasLength(1));
  });

  test('a notification the plan no longer wants is cancelled', () async {
    final stale = notification(seed: 'deadline:deleted-task');
    plugin.seed(stale);

    await apply([]);

    expect(plugin.cancelled, [stale.id]);
    expect(plugin.pending, isEmpty);
  });

  test('a moved due date cancels the old alarm and arms the new one', () async {
    final original = notification(at: DateTime(2026, 8, 1, 9));
    plugin.seed(original);

    final moved = original.copyWith(at: DateTime(2026, 8, 2, 9));
    await apply([moved]);

    expect(plugin.cancelled, [original.id]);
    expect(plugin.scheduled, [moved.id]);

    // Same id, new moment — the queue holds the new one, not both.
    expect(plugin.pending, hasLength(1));
    expect(
      ScheduledNotification.decode(plugin.pending[moved.id]!.payload)!.at,
      DateTime(2026, 8, 2, 9),
    );
  });

  test('a renamed task rewords the pending notification', () async {
    final original = notification(title: 'Buy milk');
    plugin.seed(original);

    await apply([original.copyWith(title: 'Buy oat milk')]);

    expect(plugin.pending[original.id]!.title, 'Buy oat milk');
  });

  test('a pending notification the app cannot read is cancelled', () async {
    // An alarm armed by an older build, whose payload this build cannot parse.
    // It can never be matched against a plan, so leaving it would mean firing a
    // notification the app can no longer explain.
    plugin.pending[99] = const PendingNotificationRequest(
      99,
      'Legacy',
      'From an older version',
      'not-our-payload',
    );

    await apply([]);

    expect(plugin.cancelled, [99]);
    expect(plugin.pending, isEmpty);
  });

  test('turning notifications off clears the queue', () async {
    await apply([notification()]);

    final response = await service.cancelAll();

    expect(response.success, isTrue);
    expect(plugin.pending, isEmpty);
  });

  group('the queue is partitioned by kind', () {
    // Two modules schedule reminders against one OS queue. Reconciliation works
    // by cancelling whatever the plan does not contain, so a reconciler that read
    // the whole queue would withdraw the other module's alarms every time it ran
    // — and the user would simply never be reminded of the thing they wanted to
    // buy, with nothing in the app looking broken.
    final toBuy = ScheduledNotification(
      id: ScheduledNotification.idFor('to_buy:item-1'),
      kind: NotificationKind.toBuyReminder,
      title: 'Headphones',
      body: 'Still on your list.',
      at: DateTime(2026, 8, 1, 18),
    );

    test('a Tasks sync leaves a to-buy reminder armed', () async {
      plugin.seed(toBuy);

      await apply([notification()]);

      expect(plugin.cancelled, isEmpty);
      expect(plugin.pending.keys, contains(toBuy.id));
    });

    test('a To-Buy sync leaves a task reminder armed', () async {
      final task = notification();
      plugin.seed(task);

      await service.applyPlan([toBuy], owns: NotificationKind.toBuyKinds);

      expect(plugin.cancelled, isEmpty);
      expect(plugin.pending.keys, containsAll([task.id, toBuy.id]));
    });

    test('a module still cancels its own stale reminder', () async {
      plugin.seed(toBuy);

      // The item was purchased, so the To-Buy plan no longer contains it. Its own
      // reconciler is the one that must withdraw it.
      await service.applyPlan([], owns: NotificationKind.toBuyKinds);

      expect(plugin.cancelled, [toBuy.id]);
      expect(plugin.pending, isEmpty);
    });
  });
}
