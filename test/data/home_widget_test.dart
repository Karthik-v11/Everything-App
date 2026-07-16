import 'dart:convert';

import 'package:everything_app/data/models/home_widget_payload.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/data/models/widget_action.dart';
import 'package:flutter_test/flutter_test.dart';

/// Home screen widgets (Phase 12, Requirement 13).
///
/// What earns a test here is the **boundary**, not the drawing. Everything a
/// widget shows leaves the encrypted database for a container the OS lets another
/// process read (see `HomeWidgetService`), so the thing worth asserting is *what
/// crosses it* — and that is decided entirely by the pure
/// [HomeWidgetPayload.build] and [HomeWidgetPayload.toWidgetData]. The Kotlin and
/// Swift that render the result are not testable from here and do not decide
/// anything: they draw the strings they are handed.
///
/// [WidgetAction.fromUri] is tested because a registered URL scheme is callable by
/// any app on the device, so what the app will and will not accept from one is a
/// security boundary rather than a convenience.
void main() {
  // A fixed anchor so "today" is a parameter rather than the day the suite runs.
  final now = DateTime(2026, 7, 15, 9, 30);
  final today = DateTime(2026, 7, 15);

  Task task({
    required String id,
    required String title,
    DateTime? dueDate,
    TaskStatus status = TaskStatus.pending,
  }) =>
      Task(
        id: id,
        title: title,
        dueDate: dueDate,
        status: status,
        createdAt: now,
        updatedAt: now,
      );

  group('HomeWidgetPayload — what leaves the encrypted database', () {
    test('publishes only the fields the widgets draw, and nothing else', () {
      final payload = HomeWidgetPayload.build(
        tasks: [
          task(
            id: '1',
            title: 'Pay rent',
            dueDate: today.add(const Duration(hours: 17)),
          ),
        ],
        expenseMinor: 1500000,
        now: now,
      );

      // The exact key set is asserted rather than "contains", because this map is
      // the entire surface that leaves the database. A field added here without
      // thought is data published to an unencrypted store, and this test is what
      // makes that a decision rather than an accident.
      expect(
        payload.toWidgetData().keys.toSet(),
        {
          'tasks',
          'openCount',
          'completedCount',
          'overdueCount',
          'spentLabel',
          'spentCaption',
          'updatedAtLabel',
        },
      );
    });

    test('a published task carries no notes, no category and no project', () {
      final payload = HomeWidgetPayload.build(
        tasks: [
          task(
            id: '1',
            title: 'Pay rent',
            dueDate: today.add(const Duration(hours: 17)),
          ).copyWith(
            notes: 'Bank details: 1234-5678',
            categoryId: 'finance',
            projectId: 'house',
          ),
        ],
        expenseMinor: 0,
        now: now,
      );

      final published = payload.toWidgetData()['tasks']!;

      // The title is the only text a task contributes. Notes are where people put
      // the things they would not want on a lock screen, and a widget is drawn on
      // one.
      expect(published, contains('Pay rent'));
      expect(published, isNot(contains('Bank details')));
      expect(published, isNot(contains('1234-5678')));
      expect(published, isNot(contains('house')));

      final decoded = (jsonDecode(published) as List).first as Map;
      expect(
        decoded.keys.toSet(),
        {'id', 'title', 'isCompleted', 'isOverdue', 'dueLabel'},
      );
    });

    test('money is published pre-formatted, never as a raw minor-unit int', () {
      final payload = HomeWidgetPayload.build(
        tasks: const [],
        expenseMinor: 1500000,
        now: now,
      );

      // 1500000 paise is ₹15,000 — the minor units are the stored form, and this
      // division is exactly what the native side must never be asked to do. Three
      // implementations of that rule is three chances for the home screen to
      // disagree with the Finance tab.
      expect(payload.spentLabel, '₹15,000');
      expect(payload.toWidgetData()['spentLabel'], isNot(contains('1500000')));
    });
  });

  group('HomeWidgetPayload.build — what the widget calls today', () {
    test('overdue tasks stay on the list, and sort above everything', () {
      final payload = HomeWidgetPayload.build(
        tasks: [
          // 5pm, not a bare date: a bare date is midnight, so at 09:30 it would
          // already be overdue and there would be nothing to sort against.
          task(
            id: '1',
            title: 'Due today',
            dueDate: today.add(const Duration(hours: 17)),
          ),
          task(
            id: '2',
            title: 'Overdue',
            dueDate: today.subtract(const Duration(days: 3)),
          ),
        ],
        expenseMinor: 0,
        now: now,
      );

      // A widget that showed only today's due items would go quiet on the day the
      // user is furthest behind.
      expect(payload.tasks.map((t) => t.title), ['Overdue', 'Due today']);
      expect(payload.overdueCount, 1);
    });

    test('a completed overdue task drops off; a completed one due today stays',
        () {
      final payload = HomeWidgetPayload.build(
        tasks: [
          task(
            id: '1',
            title: 'Done and overdue',
            dueDate: today.subtract(const Duration(days: 2)),
            status: TaskStatus.completed,
          ),
          task(
            id: '2',
            title: 'Done today',
            dueDate: today,
            status: TaskStatus.completed,
          ),
        ],
        expenseMinor: 0,
        now: now,
      );

      // An overdue task that is done is not overdue — it is finished, and dragging
      // it back onto today's list would make the widget an archive.
      expect(payload.tasks.map((t) => t.title), ['Done today']);
      expect(payload.openCount, 0);
      expect(payload.completedCount, 1);
      expect(payload.overdueCount, 0);
    });

    test('a task with no due date is not today\'s work', () {
      final payload = HomeWidgetPayload.build(
        tasks: [task(id: '1', title: 'Someday')],
        expenseMinor: 0,
        now: now,
      );

      expect(payload.tasks, isEmpty);
    });

    test('never publishes more than maxTasks, however many are due', () {
      final payload = HomeWidgetPayload.build(
        tasks: [
          for (var i = 0; i < 30; i++)
            task(id: '$i', title: 'Task $i', dueDate: today),
        ],
        expenseMinor: 0,
        now: now,
      );

      // The cap bounds what is written; each size truncates further. The counts
      // still describe all of them, which is the point of counting separately.
      expect(payload.tasks.length, HomeWidgetPayload.maxTasks);
      expect(payload.openCount, 30);
    });

    test('a date-only due date shows no time, only a timed one does', () {
      // Anchored at midnight, which is the only moment a date-only task due today
      // is not yet late: the app's rule is `dueDate.isBefore(now)`, and a bare
      // date is midnight, so by 09:30 it genuinely is overdue and would correctly
      // say so. This isolates the no-time branch rather than the overdue one.
      final midnight = today;

      final payload = HomeWidgetPayload.build(
        tasks: [
          task(id: '1', title: 'Someday today', dueDate: today),
          task(
            id: '2',
            title: 'At five',
            dueDate: today.add(const Duration(hours: 17)),
          ),
        ],
        expenseMinor: 0,
        now: midnight,
      );

      // Midnight is not a deadline the user set; showing "12:00 AM" against a
      // date-only task would invent one.
      final byTitle = {for (final t in payload.tasks) t.title: t.dueLabel};
      expect(byTitle['Someday today'], '');

      // Matched loosely on purpose: `intl` renders this with a narrow no-break
      // space (U+202F) before the meridiem, not an ordinary space, so an equality
      // check against '5:00 PM' fails on a character nobody can see. The claim
      // being made is that a timed task shows its time.
      expect(byTitle['At five'], contains('5:00'));
      expect(byTitle['At five'], contains('PM'));
    });

    test('overdue is judged against the injected clock, not the wall clock', () {
      // The regression guard for the real bug here: `Task.isOverdue` reads
      // `DateTime.now()` itself, so building the payload through it made this a
      // function of when the suite ran. Judged from a week earlier, a task due
      // today is simply not late yet.
      final lastWeek = DateTime(2026, 7, 8, 9);

      final payload = HomeWidgetPayload.build(
        tasks: [task(id: '1', title: 'Due today', dueDate: today)],
        expenseMinor: 0,
        now: lastWeek,
      );

      expect(payload.overdueCount, 0);
      expect(payload.tasks, isEmpty, reason: 'not today, judged from last week');
    });

    test('a cancelled task is never overdue — abandoned is not late', () {
      final payload = HomeWidgetPayload.build(
        tasks: [
          task(
            id: '1',
            title: 'Called it off',
            dueDate: today.subtract(const Duration(days: 5)),
            status: TaskStatus.cancelled,
          ),
        ],
        expenseMinor: 0,
        now: now,
      );

      expect(payload.overdueCount, 0);
    });
  });

  group('WidgetAction.fromUri — a registered scheme any app can call', () {
    test('reads every action the widgets emit', () {
      // Single-segment actions parse with the value as the URI *host* and an
      // empty path; two-segment ones split across host and path. Getting this
      // wrong makes half the actions silently unmatchable.
      expect(
        WidgetAction.fromUri(Uri.parse('everything://ai')),
        WidgetAction.assistant,
      );
      expect(
        WidgetAction.fromUri(Uri.parse('everything://task/new')),
        WidgetAction.addTask,
      );
      expect(
        WidgetAction.fromUri(Uri.parse('everything://transaction/new')),
        WidgetAction.addTransaction,
      );
      expect(
        WidgetAction.fromUri(Uri.parse('everything://search')),
        WidgetAction.search,
      );
    });

    test('anything that is not an action is refused', () {
      for (final uri in [
        'everything://widget',
        'everything://task/new/../../etc',
        'everything://tasks/12345',
        'everything://',
        'https://example.com/task/new',
      ]) {
        expect(
          WidgetAction.fromUri(Uri.parse(uri)),
          isNull,
          reason: '$uri must not resolve to an action',
        );
      }

      expect(WidgetAction.fromUri(null), isNull);
    });
  });
}
