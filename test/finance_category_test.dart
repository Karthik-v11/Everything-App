import 'package:everything_app/data/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('categoryColor', () {
    test('gives every starter category a colour of its own', () {
      final colors = {
        for (final category in kTransactionCategories)
          categoryColor(category.name),
      };

      expect(colors.length, kTransactionCategories.length);
    });

    test('is stable and case-insensitive', () {
      expect(categoryColor('food'), categoryColor('Food'));
      expect(categoryColor('Gifts'), categoryColor('Gifts'));
    });

    test('keeps a custom category off the starter colours', () {
      final starters = {
        for (final category in kTransactionCategories)
          categoryColor(category.name),
      };

      expect(starters.contains(categoryColor('Pets')), isFalse);
    });
  });

  group('inferTransactionCategory', () {
    test('reads the category out of what was typed', () {
      expect(inferTransactionCategory('Swiggy dinner'), 'Food');
      expect(inferTransactionCategory('Uber to office'), 'Travel');
      expect(inferTransactionCategory('Electricity bill'), 'Bills');
      expect(inferTransactionCategory('SIP mutual fund'), 'Investment');
      expect(inferTransactionCategory('Netflix'), 'Entertainment');
      expect(inferTransactionCategory('July salary'), 'Salary');
      expect(inferTransactionCategory('Pharmacy — medicines'), 'Healthcare');
      expect(inferTransactionCategory('Udemy course'), 'Education');
      expect(inferTransactionCategory('Myntra shoes'), 'Shopping');
    });

    test('says nothing rather than guessing wrong', () {
      expect(inferTransactionCategory(''), isNull);
      expect(inferTransactionCategory('   '), isNull);
      expect(inferTransactionCategory('Karthik'), isNull);
      // A keyword inside a longer word is not a match.
      expect(inferTransactionCategory('barber'), isNull);
    });

    test('prefers the longest keyword it matched', () {
      expect(inferTransactionCategory('Mutual fund top up'), 'Investment');
    });
  });
}
