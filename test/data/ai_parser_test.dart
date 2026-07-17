import 'package:everything_app/data/entity/ai_intent.dart';
import 'package:everything_app/data/entity/parsed_task_intent.dart';
import 'package:everything_app/data/entity/parsed_transaction_intent.dart';
import 'package:everything_app/data/models/category.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/data/models/transaction.dart';
import 'package:everything_app/data/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// AI Assistant — the rule-based parser (Phase 10, Requirement 16).
///
/// These test the pure parse entities and the classifier directly. They are the
/// same shapes [AiService] — and Phase 13's model-backed replacement — return, so
/// Property 14's guarantees are asserted where the LLM will have to meet them too:
/// against [ParsedTaskIntent], not against a particular implementation.
void main() {
  // A fixed anchor so every relative date is deterministic: a Wednesday.
  final now = DateTime(2026, 7, 15, 9);

  group('ParsedTaskIntent — Property 14', () {
    test('a task line always parses to a non-empty title', () {
      for (final input in [
        'Buy milk tomorrow',
        'Call mum friday 5pm',
        'Pay rent tomorrow 5pm p1',
        'Finish the report',
      ]) {
        final intent = ParsedTaskIntent.parse(input, now: now);
        expect(intent.isConfident, isTrue, reason: input);
        expect(intent.title.trim(), isNotEmpty, reason: input);
      }
    });

    test('an inferable date lands on a non-null, consistent dueDate', () {
      final intent = ParsedTaskIntent.parse('Buy milk tomorrow', now: now);

      expect(intent.dueDate, isNotNull);
      // Tomorrow, relative to the Wednesday anchor.
      expect(intent.dueDate!.year, 2026);
      expect(intent.dueDate!.month, 7);
      expect(intent.dueDate!.day, 16);
    });

    test('the title is the words left after the tokens are stripped', () {
      final intent = ParsedTaskIntent.parse('Pay rent tomorrow 5pm', now: now);

      expect(intent.title, 'Pay rent');
      expect(intent.dueDate, DateTime(2026, 7, 16, 17));
    });

    test('resolves a #category against the real categories', () {
      const categories = [
        Category(id: 'c1', name: 'Finance', colorValue: 0, iconName: 'x'),
      ];

      final intent = ParsedTaskIntent.parse(
        'Pay rent tomorrow #finance',
        categories: categories,
        now: now,
      );

      expect(intent.categoryId, 'c1');
      expect(intent.title, 'Pay rent');
    });

    test('a line with only a date is not yet a task — it asks to be named', () {
      final intent = ParsedTaskIntent.parse('tomorrow 5pm', now: now);

      expect(intent.title.trim(), isEmpty);
      expect(intent.isConfident, isFalse);
    });
  });

  group('ParsedTaskIntent — reminders', () {
    test('a stated gap becomes a reminder that far before the due date', () {
      final intent = ParsedTaskIntent.parse(
        'Call mum tomorrow 5pm remind me 10 minutes before',
        now: now,
      );

      expect(intent.title, 'Call mum');
      expect(intent.reminderOffset, const Duration(minutes: 10));
      expect(intent.toTask().reminders.single.at, DateTime(2026, 7, 16, 16, 50));
    });

    test('the gap is read in every unit and shorthand it is written in', () {
      const cases = {
        'Ship it tomorrow alert me 30m before': Duration(minutes: 30),
        'Ship it tomorrow remind me 2 hours before': Duration(hours: 2),
        'Ship it tomorrow reminder 1 day before': Duration(days: 1),
        'Ship it tomorrow notify me 1 week early': Duration(days: 7),
        'Ship it tomorrow remind me on time': Duration.zero,
      };

      for (final entry in cases.entries) {
        final intent = ParsedTaskIntent.parse(entry.key, now: now);

        expect(intent.reminderOffset, entry.value, reason: entry.key);
        expect(intent.title, 'Ship it', reason: entry.key);
      }
    });

    test('a reminder with no due date is dropped rather than guessed at', () {
      final intent = ParsedTaskIntent.parse('Call mum remind me 1 hour before', now: now);

      expect(intent.reminderOffset, const Duration(hours: 1));
      expect(intent.dueDate, isNull);
      expect(intent.toTask().reminders, isEmpty);
    });

    test('the gap is not also read as a due date', () {
      final intent = ParsedTaskIntent.parse('Call mum remind me 2 days before', now: now);

      expect(intent.dueDate, isNull);
      expect(intent.title, 'Call mum');
    });

    test('a bare gap with no verb stays in the title', () {
      final intent = ParsedTaskIntent.parse('Boil the egg 10 minutes before', now: now);

      expect(intent.reminderOffset, isNull);
      expect(intent.title, 'Boil the egg 10 minutes before');
    });
  });

  group('ParsedTaskIntent — repeat', () {
    test('an interval is kept, not flattened to the bare frequency', () {
      final intent = ParsedTaskIntent.parse('Water plants every 2 weeks', now: now);

      expect(intent.title, 'Water plants');
      expect(intent.recurrence!.frequency, RecurrenceFrequency.weekly);
      expect(intent.recurrence!.interval, 2);
      expect(intent.recurrence!.until, isNull);
    });

    test('an until clause ends the series on that day', () {
      final intent = ParsedTaskIntent.parse('Standup every day until 25 dec', now: now);

      expect(intent.title, 'Standup');
      expect(intent.recurrence!.frequency, RecurrenceFrequency.daily);
      // End of the day, so the last occurrence is not cut off by its own hour.
      expect(intent.recurrence!.until, DateTime(2026, 12, 25, 23, 59));
    });

    test('the until date is not also taken as the due date', () {
      final intent = ParsedTaskIntent.parse('Standup every day until 25 dec', now: now);

      expect(intent.dueDate, isNull);
    });

    test('a due date and an until date coexist', () {
      final intent = ParsedTaskIntent.parse(
        'Standup tomorrow every day until 25 dec',
        now: now,
      );

      expect(intent.title, 'Standup');
      expect(intent.dueDate, DateTime(2026, 7, 16, 9));
      expect(intent.recurrence!.until, DateTime(2026, 12, 25, 23, 59));
    });

    test('an unreadable until leaves the rule open and the words in the title', () {
      final intent = ParsedTaskIntent.parse('Standup every day until further notice', now: now);

      expect(intent.recurrence!.until, isNull);
      expect(intent.title, 'Standup until further notice');
    });
  });

  group('ParsedTransactionIntent', () {
    test('reads amount, type and category from a spend line', () {
      final intent =
          ParsedTransactionIntent.parse('Spent 500 on food', now: now);

      expect(intent.isConfident, isTrue);
      expect(intent.amountMinor, 50000);
      expect(intent.type, TransactionType.expense);
      expect(intent.category, 'Food');
    });

    test('classifies income and keeps a positive amount', () {
      final intent =
          ParsedTransactionIntent.parse('Got 20000 salary', now: now);

      expect(intent.type, TransactionType.income);
      expect(intent.amountMinor, 2000000);
      expect(intent.category, 'Salary');
    });

    test('honours a currency marker and magnitude suffix', () {
      expect(
        ParsedTransactionIntent.parse('Paid ₹1,200 rent', now: now).amountMinor,
        120000,
      );
      expect(
        ParsedTransactionIntent.parse('Invested 2k', now: now).amountMinor,
        200000,
      );
    });

    test('a marked amount wins over an incidental number', () {
      final intent = ParsedTransactionIntent.parse(
        'Bought 2 coffees for ₹400',
        now: now,
      );

      expect(intent.amountMinor, 40000);
    });

    test('no amount means low confidence — it asks how much', () {
      final intent =
          ParsedTransactionIntent.parse('lunch at the cafe', now: now);

      expect(intent.hasAmount, isFalse);
      expect(intent.isConfident, isFalse);
    });

    test('logs against yesterday when the line says so', () {
      final intent =
          ParsedTransactionIntent.parse('Spent 200 on cab yesterday', now: now);

      expect(intent.date.day, 14);
    });

    test('toTransaction names an untitled line after its category', () {
      final intent = ParsedTransactionIntent.parse('Spent 500 on food', now: now)
          .toTransaction(accountId: 'a1');

      expect(intent.title, isNotEmpty);
      expect(intent.accountId, 'a1');
      expect(intent.amountMinor, 50000);
    });
  });

  group('AiService.classify', () {
    test('a plain to-do is a task', () {
      expect(AiService.classify('Call the dentist'), AiIntent.task);
      // A number that is a time, not money, stays a task.
      expect(AiService.classify('Call the dentist at 5pm'), AiIntent.task);
    });

    test('a shopping line is a to-buy item, not a task', () {
      // 'Buy milk tomorrow' reads as a to-do only until To Buy exists as a
      // destination. It is a shopping item, the To Buy chip is preselected, and
      // a task with the same words would be the wrong entry in the wrong module.
      expect(AiService.classify('Buy milk tomorrow'), AiIntent.toBuy);
      expect(AiService.classify('Pick up eggs'), AiIntent.toBuy);
    });

    test('a spend line is an expense', () {
      expect(AiService.classify('Spent 500 on food'), AiIntent.expense);
      expect(AiService.classify('Paid ₹1200 rent'), AiIntent.expense);
    });

    test('a question is a question', () {
      expect(AiService.classify('How much did I spend on food?'),
          AiIntent.question);
      expect(AiService.classify('What tasks are due today'), AiIntent.question);
    });

    test('an explicit find is a search', () {
      expect(AiService.classify('Find my passport'), AiIntent.search);
    });

    test('an explicit note is a note', () {
      expect(AiService.classify('Note buy groceries this weekend'),
          AiIntent.note);
    });
  });
}
