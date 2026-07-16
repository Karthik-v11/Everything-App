import 'package:everything_app/data/entity/ai_intent.dart';
import 'package:everything_app/data/entity/parsed_task_intent.dart';
import 'package:everything_app/data/entity/parsed_transaction_intent.dart';
import 'package:everything_app/data/models/category.dart';
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
      expect(AiService.classify('Buy milk tomorrow'), AiIntent.task);
      // A number that is a time, not money, stays a task.
      expect(AiService.classify('Call the dentist at 5pm'), AiIntent.task);
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
