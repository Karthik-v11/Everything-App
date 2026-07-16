import 'dart:math';

import 'package:everything_app/bloc/finance/finance_bloc.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/database/daos/finance_dao.dart';
import 'package:everything_app/data/models/account.dart';
import 'package:everything_app/data/models/transaction.dart';
import 'package:everything_app/data/services/finance_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Transaction persistence and the finance summary — Requirements 12, 13, 14.1.
///
/// These run against a real Drift database, in memory: an amount that survives a
/// round trip through `AppDatabase.memory()` survives one through the encrypted
/// on-device database, because it is the same schema and the same column types.
/// No SQLCipher key is needed, so it runs in CI.
void main() {
  late AppDatabase database;
  late FinanceService service;

  setUp(() {
    database = AppDatabase.memory();
    service = FinanceService(dao: FinanceDao(database));
  });

  tearDown(() => database.close());

  Transaction transaction({
    String id = '',
    String title = 'Groceries',
    required int amountMinor,
    DateTime? date,
    TransactionType type = TransactionType.expense,
    String category = 'Food',
  }) =>
      Transaction(
        id: id,
        title: title,
        amountMinor: amountMinor,
        date: date ?? DateTime(2026, 7, 12),
        type: type,
        category: category,
        accountId: 'account-1',
        createdAt: DateTime(2026, 7, 12),
      );

  group('Property 6 — transaction amount preserved through round-trip', () {
    // Feature: everything-app, Property 6: For any valid Transaction with a
    // non-negative amount, creating it and reading it back should return the same
    // amount with no floating-point precision loss beyond two decimal places
    // (i.e. `(stored - original).abs() < 0.005`).
    test('any amount survives a write and a read', () async {
      final random = Random(6);

      for (var iteration = 0; iteration < 200; iteration++) {
        // Up to ten million rupees, to the paise. Money is stored as an integer
        // count of paise, so the round trip has nothing to round.
        final major = random.nextDouble() * 10000000;
        final amountMinor = Helpers.toMinorUnits(major);
        if (amountMinor <= 0) continue;

        final created = await service.createTransaction(
          transaction(amountMinor: amountMinor),
        );
        expect(created.success, isTrue, reason: created.message);

        final saved = created.data! as Transaction;
        final row = await FinanceDao(database).findTransaction(saved.id);
        final readBack = Transaction.fromEntry(row!);

        // The integer is identical, not merely close.
        expect(readBack.amountMinor, amountMinor);

        // And the property as design.md states it, in major units.
        expect(
          (Helpers.toMajorUnits(readBack.amountMinor) -
                  Helpers.toMajorUnits(amountMinor))
              .abs(),
          lessThan(0.005),
        );
      }
    });

    test('an amount summed a thousand times does not drift', () {
      // The reason money is an int at all. Summed as doubles, a thousand 0.1s
      // come to 99.9999999999986 — and Property 7 sums an arbitrary sequence.
      var total = 0;
      for (var i = 0; i < 1000; i++) {
        total += Helpers.toMinorUnits(0.1);
      }

      expect(total, 10000);
      expect(Helpers.toMajorUnits(total), 100.0);
    });

    test('every field survives the round trip, not only the amount', () async {
      final original = transaction(
        title: 'Dinner',
        amountMinor: 125050,
        type: TransactionType.expense,
        category: 'Food',
        date: DateTime(2026, 7, 12, 20, 30),
      );

      final created = await service.createTransaction(original);
      final saved = created.data! as Transaction;

      final row = await FinanceDao(database).findTransaction(saved.id);
      final readBack = Transaction.fromEntry(row!);

      expect(readBack.title, 'Dinner');
      expect(readBack.amountMinor, 125050);
      expect(readBack.type, TransactionType.expense);
      expect(readBack.category, 'Food');
      expect(readBack.date, DateTime(2026, 7, 12, 20, 30));
      expect(readBack.accountId, 'account-1');
    });
  });

  group('Property 7 — monthly budget tracking monotonicity', () {
    // Feature: everything-app, Property 7: For any sequence of expense
    // transactions added to a given month, the cumulative monthly expense total
    // returned by the finance summary should equal the arithmetic sum of all
    // expense amounts added, and should never decrease when new expense
    // transactions are appended.
    test('the summary equals the sum, and never decreases as expenses are appended',
        () async {
      final random = Random(7);
      final month = DateTime(2026, 7);

      final added = <Transaction>[];
      var expected = 0;
      var previousTotal = 0;

      for (var iteration = 0; iteration < 150; iteration++) {
        final amountMinor = 1 + random.nextInt(500000);

        final created = await service.createTransaction(
          transaction(
            amountMinor: amountMinor,
            // Anywhere within the month, so the summary's month filter is
            // exercised rather than every row landing on the same day.
            date: DateTime(2026, 7, 1 + random.nextInt(28)),
            category: ['Food', 'Travel', 'Bills'][random.nextInt(3)],
          ),
        );

        added.add(created.data! as Transaction);
        expected += amountMinor;

        // The summary as the app computes it — the same getter the dashboard,
        // the donut and the budget bar all read.
        final state = FinanceState.initial().copyWith(
          transactions: added,
          selectedMonth: month,
        );

        expect(state.expenseMinor, expected);
        expect(state.expenseMinor, greaterThanOrEqualTo(previousTotal));

        previousTotal = state.expenseMinor;
      }

      // And the figure the budget is tracked against is the same one.
      final spend = FinanceState.spendFor(added, month);
      expect(spend.totalMinor, expected);

      // The per-category split adds back up to the whole.
      expect(
        spend.byCategory.values.fold<int>(0, (sum, value) => sum + value),
        expected,
      );
    });

    test('income, transfers and investments are not counted as spending', () async {
      final month = DateTime(2026, 7);

      final transactions = [
        transaction(amountMinor: 10000, type: TransactionType.expense),
        transaction(amountMinor: 500000, type: TransactionType.income),
        transaction(amountMinor: 200000, type: TransactionType.transfer),
        transaction(amountMinor: 300000, type: TransactionType.investment),
      ];

      final state = FinanceState.initial().copyWith(
        transactions: transactions,
        selectedMonth: month,
      );

      // Only the expense. An investment is money moved, not money gone — budgeting
      // it as spending would tell a user who saved well that they overspent.
      expect(state.expenseMinor, 10000);
      expect(state.incomeMinor, 500000);
      expect(state.investedMinor, 300000);
      expect(state.savingsMinor, 490000);

      expect(FinanceState.spendFor(transactions, month).totalMinor, 10000);
    });

    test('a transaction in another month is not in this month’s total', () {
      final state = FinanceState.initial().copyWith(
        transactions: [
          transaction(amountMinor: 10000, date: DateTime(2026, 7, 15)),
          transaction(amountMinor: 99999, date: DateTime(2026, 6, 30)),
          transaction(amountMinor: 88888, date: DateTime(2025, 7, 15)),
        ],
        selectedMonth: DateTime(2026, 7),
      );

      // The same month of a different year is a different month.
      expect(state.expenseMinor, 10000);
    });
  });

  group('validation', () {
    test('a non-positive amount is rejected', () async {
      final zero = await service.createTransaction(
        transaction(amountMinor: 0),
      );
      expect(zero.success, isFalse);
      expect(zero.statusCode, 400);

      // The sign is carried by the type, so a negative amount is a bug rather than
      // an expense — accepting it would silently subtract from a month's total.
      final negative = await service.createTransaction(
        transaction(amountMinor: -5000),
      );
      expect(negative.success, isFalse);
      expect(negative.statusCode, 400);
    });

    test('a blank title is rejected', () async {
      final response = await service.createTransaction(
        transaction(title: '   ', amountMinor: 10000),
      );

      expect(response.success, isFalse);
      expect(response.statusCode, 400);
    });

    test('an update replaces the row rather than adding a second one', () async {
      final created = await service.createTransaction(
        transaction(amountMinor: 10000),
      );
      final saved = created.data! as Transaction;

      await service.updateTransaction(saved.copyWith(amountMinor: 25000));

      final all = await FinanceDao(database).allTransactions();

      expect(all, hasLength(1));
      expect(all.single.amountMinor, 25000);
    });
  });

  group('accounts', () {
    test('an account with history is archived rather than deleted', () async {
      final accounts = await service.seedDefaultAccounts();
      expect(accounts.success, isTrue);

      final dao = FinanceDao(database);
      final account = (await dao.allAccounts()).first;

      await service.createTransaction(
        Transaction(
          id: '',
          title: 'Coffee',
          amountMinor: 15000,
          date: DateTime(2026, 7, 12),
          accountId: account.id,
          createdAt: DateTime(2026, 7, 12),
        ),
      );

      final response = await service.deleteAccount(Account.fromEntry(account));

      expect(response.success, isTrue);

      // The account is still there, archived — deleting it would leave the
      // transaction naming an account that no longer exists.
      final stored = (await dao.allAccounts()).firstWhere(
        (entry) => entry.id == account.id,
      );
      expect(stored.isArchived, isTrue);

      // And the transaction it explains is untouched.
      expect(await dao.allTransactions(), hasLength(1));
    });

    test('an unused account is deleted outright', () async {
      await service.seedDefaultAccounts();

      final dao = FinanceDao(database);
      final before = await dao.allAccounts();

      final response = await service.deleteAccount(
        Account.fromEntry(before.first),
      );

      expect(response.success, isTrue);
      expect(await dao.allAccounts(), hasLength(before.length - 1));
    });

    test('seeding is skipped when accounts already exist', () async {
      await service.seedDefaultAccounts();
      await service.seedDefaultAccounts();

      // A deleted default must not be reinstated on the next launch, so the seed
      // is guarded on an empty table rather than on each row.
      expect(await FinanceDao(database).allAccounts(), hasLength(2));
    });
  });
}
