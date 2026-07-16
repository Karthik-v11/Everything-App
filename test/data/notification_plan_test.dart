import 'package:everything_app/data/models/notification_settings.dart';
import 'package:everything_app/data/models/scheduled_notification.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

/// The notification plan — the delivery rules of Requirement 5.
///
/// [NotificationPlan.build] is a pure function of `(tasks, settings, now)`, so
/// every rule is tested here with no device, no plugin and no waiting: the "now"
/// the rules are evaluated against is passed in, which is what makes a
/// missed-task alert or a Monday summary assertable at all.
void main() {
  // A Wednesday, so the weekly-summary weekday arithmetic has to actually work
  // rather than accidentally land on the day the test happens to run.
  final now = DateTime(2026, 7, 15, 10);

  const settings = NotificationSettings();

  Task task({
    String id = 'task-1',
    String title = 'Buy milk',
    DateTime? dueDate,
    TaskStatus status = TaskStatus.pending,
    List<Reminder> reminders = const [],
    DateTime? completedAt,
  }) =>
      Task(
        id: id,
        title: title,
        dueDate: dueDate,
        status: status,
        reminders: reminders,
        completedAt: completedAt,
        createdAt: now,
        updatedAt: now,
      );

  List<ScheduledNotification> plan(
    List<Task> tasks, {
    NotificationSettings config = settings,
    DateTime? at,
  }) =>
      NotificationPlan.build(
        tasks: tasks,
        settings: config,
        now: at ?? now,
      );

  List<ScheduledNotification> ofKind(
    List<ScheduledNotification> plan,
    NotificationKind kind,
  ) =>
      plan.where((item) => item.kind == kind).toList();

  group('Requirement 5.1 — task reminders', () {
    test('a reminder is scheduled for the moment the user chose', () {
      final due = now.add(const Duration(hours: 5));

      final scheduled = ofKind(
        plan([
          task(
            dueDate: due,
            reminders: [
              Reminder(id: 'r1', at: due.subtract(const Duration(hours: 1))),
            ],
          ),
        ]),
        NotificationKind.reminder,
      );

      expect(scheduled, hasLength(1));
      expect(scheduled.single.at, due.subtract(const Duration(hours: 1)));
      expect(scheduled.single.title, 'Buy milk');
      expect(scheduled.single.taskId, 'task-1');
    });

    test('a reminder whose moment has already passed is not scheduled', () {
      final scheduled = plan([
        task(
          dueDate: now.add(const Duration(days: 1)),
          reminders: [
            Reminder(id: 'r1', at: now.subtract(const Duration(minutes: 5))),
          ],
        ),
      ]);

      expect(ofKind(scheduled, NotificationKind.reminder), isEmpty);
    });
  });

  group('Requirements 5.2 and 5.4 — deadline and missed-task alerts', () {
    test('the deadline fires at the due date, the missed alert after it', () {
      final due = now.add(const Duration(hours: 3));
      final scheduled = plan([task(dueDate: due)]);

      final deadline = ofKind(scheduled, NotificationKind.deadline).single;
      final missed = ofKind(scheduled, NotificationKind.missed).single;

      expect(deadline.at, due);
      expect(missed.at, due.add(NotificationPlan.missedGrace));
      expect(missed.id, isNot(deadline.id));
    });

    test('a task with no due date has neither', () {
      final scheduled = plan([task()]);

      expect(ofKind(scheduled, NotificationKind.deadline), isEmpty);
      expect(ofKind(scheduled, NotificationKind.missed), isEmpty);
    });
  });

  group('a completed task is silent', () {
    test('completing a task withdraws every notification it had', () {
      final due = now.add(const Duration(hours: 5));
      final reminders = [
        Reminder(id: 'r1', at: due.subtract(const Duration(hours: 1))),
      ];

      expect(plan([task(dueDate: due, reminders: reminders)]), isNotEmpty);

      // The same task, ticked off. No explicit cancel exists anywhere in the app
      // — the plan simply stops containing it, and reconciliation does the rest.
      final completed = plan([
        task(
          dueDate: due,
          reminders: reminders,
          status: TaskStatus.completed,
          completedAt: now,
        ),
      ]);

      expect(completed.where((item) => item.taskId == 'task-1'), isEmpty);
    });
  });

  group('Requirement 5.5 — daily summary', () {
    test('fires at the configured time with the count of tasks due', () {
      final scheduled = ofKind(
        plan([
          task(id: 'a', dueDate: DateTime(2026, 7, 16, 9)),
          task(id: 'b', dueDate: DateTime(2026, 7, 16, 17)),
        ]),
        NotificationKind.dailySummary,
      );

      expect(scheduled.single.at, DateTime(2026, 7, 16, 8));
      expect(scheduled.single.body, '2 tasks due today.');
    });

    test('a day with nothing due gets no summary', () {
      // A digest that says "0 tasks today" is noise, and noise is what gets an
      // app's notifications switched off.
      expect(ofKind(plan([task()]), NotificationKind.dailySummary), isEmpty);
    });
  });

  group('Requirement 5.6 — weekly summary', () {
    test('fires on the configured weekday with both counts', () {
      final scheduled = ofKind(
        plan([
          task(
            id: 'done',
            status: TaskStatus.completed,
            completedAt: now.subtract(const Duration(days: 2)),
          ),
          task(id: 'open-a', dueDate: DateTime(2026, 7, 21, 9)),
          task(id: 'open-b', dueDate: DateTime(2026, 7, 22, 9)),
          // Outside the coming week — not counted.
          task(id: 'far', dueDate: DateTime(2026, 8, 30, 9)),
        ]),
        NotificationKind.weeklySummary,
      );

      // The next Monday at 09:00, from a Wednesday.
      expect(scheduled.single.at, DateTime(2026, 7, 20, 9));
      expect(scheduled.single.body, '1 done last week, 2 due this week.');
    });
  });

  group('the settings decide what is scheduled at all', () {
    test('the master switch off means nothing is scheduled', () {
      final scheduled = plan(
        [task(dueDate: now.add(const Duration(hours: 2)))],
        config: settings.copyWith(isEnabled: false),
      );

      expect(scheduled, isEmpty);
    });

    test('a switched-off kind is dropped and the others survive', () {
      final scheduled = plan(
        [task(dueDate: now.add(const Duration(hours: 2)))],
        config: settings.withKind(NotificationKind.missed, isOn: false),
      );

      expect(ofKind(scheduled, NotificationKind.missed), isEmpty);
      expect(ofKind(scheduled, NotificationKind.deadline), hasLength(1));
    });
  });

  group('platform limits', () {
    test('the plan is capped, and what survives is the soonest', () {
      // Far more tasks than any platform will hold pending at once. iOS drops
      // everything past its ceiling *silently*, so the app has to choose what to
      // keep rather than let the OS choose for it.
      final tasks = [
        for (var i = 0; i < 200; i++)
          task(id: 'task-$i', dueDate: now.add(Duration(hours: i + 1))),
      ];

      final scheduled = plan(tasks);
      expect(scheduled, hasLength(NotificationPlan.maxScheduled));

      final kept = scheduled.map((item) => item.at).toList();
      final latestKept = kept.reduce((a, b) => a.isAfter(b) ? a : b);
      final earliestDropped = tasks
          .map((item) => item.dueDate!)
          .where((due) => !kept.contains(due))
          .reduce((a, b) => a.isBefore(b) ? a : b);

      expect(latestKept.isBefore(earliestDropped), isTrue);
    });
  });

  group('notification ids', () {
    test('an id is stable, so a queue armed by an earlier run can be matched',
        () {
      // Reconciliation matches a plan built now against alarms armed by a
      // previous launch. If this id ever drifted, every pending notification
      // would be orphaned and re-armed on every start.
      expect(
        ScheduledNotification.idFor('deadline:task-1'),
        ScheduledNotification.idFor('deadline:task-1'),
      );
      expect(
        ScheduledNotification.idFor('deadline:task-1'),
        isNot(ScheduledNotification.idFor('missed:task-1')),
      );
    });

    test('an id is a positive 32-bit int, which is all the platforms accept', () {
      for (final seed in ['deadline:a', 'missed:b', 'daily:2026-07-15']) {
        final id = ScheduledNotification.idFor(seed);
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThan(1 << 31));
      }
    });
  });

  group('payload round-trip', () {
    test('a scheduled notification survives encoding and decoding intact', () {
      final notification = ScheduledNotification(
        id: 42,
        kind: NotificationKind.deadline,
        title: 'Buy milk',
        body: 'Due now.',
        at: DateTime(2026, 7, 15, 17, 30),
        taskId: 'task-1',
      );

      expect(ScheduledNotification.decode(notification.payload), notification);
    });

    test('a foreign payload decodes to null, never to a wrong notification', () {
      expect(ScheduledNotification.decode(null), isNull);
      expect(ScheduledNotification.decode('not json'), isNull);
      expect(ScheduledNotification.decode('{"foo":1}'), isNull);
    });
  });
}
