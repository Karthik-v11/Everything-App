import 'dart:math';

import 'package:everything_app/data/models/budget.dart';
import 'package:everything_app/data/models/notification_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// The budget threshold rule — Requirements 14.3, 14.4, 14.5.
///
/// [BudgetStatus] is a pure value, so the rule is tested with no database, no
/// clock and no notification plugin. Every screen and every alert in the app reads
/// its level from here, which is what makes this the only place the rule has to be
/// right.
void main() {
  BudgetStatus status({
    required int spentMinor,
    required int limitMinor,
    Map<String, int> categoryLimits = const {},
    Map<String, int> spentByCategory = const {},
  }) =>
      BudgetStatus(
        budget: Budget(
          id: 'budget-1',
          monthlyLimitMinor: limitMinor,
          categoryLimits: categoryLimits,
          month: 7,
          year: 2026,
        ),
        spentMinor: spentMinor,
        spentByCategory: spentByCategory,
      );

  group('Property 8 — budget alert threshold invariant', () {
    // Feature: everything-app, Property 8: For any budget with a positive monthly
    // limit, the budget-warning notification is triggered if and only if total
    // monthly expenses are >= 80% of the limit but < 100%, and the budget-exceeded
    // notification is triggered if and only if total monthly expenses >= 100% of
    // the limit.
    test('holds for arbitrary spend and limit', () {
      // Seeded, so a failure is reproducible rather than a story about a run that
      // once went red.
      final random = Random(8);

      for (var iteration = 0; iteration < 500; iteration++) {
        final limitMinor = 1 + random.nextInt(50000000);

        // Drawn past the limit as well as under it, so the exceeded branch is
        // exercised as often as the quiet one.
        final spentMinor = random.nextInt((limitMinor * 1.4).round() + 1);

        final level = status(
          spentMinor: spentMinor,
          limitMinor: limitMinor,
        ).level;

        // The property, stated in the property's own terms rather than the
        // implementation's: a ratio, compared to 0.8 and 1.0.
        final ratio = spentMinor / limitMinor;

        final expected = switch (ratio) {
          >= 1.0 => BudgetAlertLevel.exceeded,
          >= 0.8 => BudgetAlertLevel.warning,
          _ => BudgetAlertLevel.none,
        };

        expect(
          level,
          expected,
          reason: 'spent $spentMinor of $limitMinor (${(ratio * 100).toStringAsFixed(2)}%)',
        );
      }
    });

    test('warning fires at exactly 80% and not a paise below', () {
      // 80% of 1000_00 is 800_00 exactly. The boundary is the whole rule, so it is
      // asserted on the paise either side of it rather than left to the random
      // sweep to stumble into.
      expect(
        status(spentMinor: 79999, limitMinor: 100000).level,
        BudgetAlertLevel.none,
      );
      expect(
        status(spentMinor: 80000, limitMinor: 100000).level,
        BudgetAlertLevel.warning,
      );
      expect(
        status(spentMinor: 99999, limitMinor: 100000).level,
        BudgetAlertLevel.warning,
      );
      expect(
        status(spentMinor: 100000, limitMinor: 100000).level,
        BudgetAlertLevel.exceeded,
      );
    });

    test('warning fires at 80% of a limit that 80% does not divide evenly', () {
      // 80% of 333_33 is 266_66.4 — the first paise at or above it is 266_67.
      // Computed in floating point, `26666 / 33333 >= 0.8` is the kind of
      // comparison that answers this wrongly, which is why the rule compares
      // integers.
      expect(
        status(spentMinor: 26666, limitMinor: 33333).level,
        BudgetAlertLevel.none,
      );
      expect(
        status(spentMinor: 26667, limitMinor: 33333).level,
        BudgetAlertLevel.warning,
      );
    });

    test('a limit of zero or less is not a budget and triggers nothing', () {
      expect(
        status(spentMinor: 500000, limitMinor: 0).level,
        BudgetAlertLevel.none,
      );
      expect(
        status(spentMinor: 500000, limitMinor: -100).level,
        BudgetAlertLevel.none,
      );
      expect(status(spentMinor: 500000, limitMinor: 0).alerts, isEmpty);
    });
  });

  group('alerts', () {
    test('a warning is one alert, and not also an exceeded', () {
      final alerts = status(spentMinor: 85000, limitMinor: 100000).alerts;

      expect(alerts, hasLength(1));
      expect(alerts.single.level, BudgetAlertLevel.warning);
      expect(alerts.single.kind, NotificationKind.budgetWarning);
      expect(alerts.single.category, isNull);
    });

    test('an exceeded budget is announced as exceeded, not as a warning', () {
      final alerts = status(spentMinor: 120000, limitMinor: 100000).alerts;

      expect(alerts, hasLength(1));
      expect(alerts.single.level, BudgetAlertLevel.exceeded);
      expect(alerts.single.kind, NotificationKind.budgetExceeded);
    });

    test('a category over its own limit is announced (Requirement 14.5)', () {
      final alerts = status(
        spentMinor: 30000,
        limitMinor: 100000,
        categoryLimits: {'Food': 20000, 'Travel': 50000},
        spentByCategory: {'Food': 25000, 'Travel': 5000},
      ).alerts;

      // The monthly budget is at 30%, so it says nothing; only Food does.
      expect(alerts, hasLength(1));
      expect(alerts.single.category, 'Food');
      expect(alerts.single.kind, NotificationKind.categoryBudgetExceeded);
      expect(alerts.single.level, BudgetAlertLevel.exceeded);
    });

    test('a category at 80% of its own limit is not announced', () {
      // Requirement 14.5 asks for no category warning — one notification per
      // category at 80% is how an app teaches its user to swipe them away.
      final alerts = status(
        spentMinor: 16000,
        limitMinor: 100000,
        categoryLimits: {'Food': 20000},
        spentByCategory: {'Food': 16000},
      ).alerts;

      expect(alerts, isEmpty);
    });

    test('the monthly and a category alert are both raised', () {
      final alerts = status(
        spentMinor: 105000,
        limitMinor: 100000,
        categoryLimits: {'Food': 20000},
        spentByCategory: {'Food': 25000},
      ).alerts;

      expect(alerts, hasLength(2));
      expect(alerts.first.category, isNull);
      expect(alerts.last.category, 'Food');
    });

    test('an alert key is stable across levels so a warning can be recognised', () {
      // The key identifies what the alert is *about*, so BudgetBloc can tell a
      // budget going on to be exceeded from a fresh one, and replace the warning
      // in the tray rather than sit beside it.
      const warning = BudgetAlert(
        level: BudgetAlertLevel.warning,
        spentMinor: 80000,
        limitMinor: 100000,
      );
      const exceeded = BudgetAlert(
        level: BudgetAlertLevel.exceeded,
        spentMinor: 110000,
        limitMinor: 100000,
      );

      expect(warning.key(2026, 7), exceeded.key(2026, 7));
      expect(warning.key(2026, 7), '2026-07:monthly');

      // A different month is a different alert, which is what lets August start
      // over without clearing July.
      expect(warning.key(2026, 8), isNot(warning.key(2026, 7)));
    });

    test('levels escalate but do not de-escalate into an announcement', () {
      expect(
        BudgetAlertLevel.exceeded.isAbove(BudgetAlertLevel.warning),
        isTrue,
      );
      expect(
        BudgetAlertLevel.warning.isAbove(BudgetAlertLevel.warning),
        isFalse,
      );
      expect(
        BudgetAlertLevel.warning.isAbove(BudgetAlertLevel.exceeded),
        isFalse,
      );
    });
  });

  group('progress', () {
    test('percentUsed is not clamped, so an overspend can be seen', () {
      final overspent = status(spentMinor: 150000, limitMinor: 100000);

      expect(overspent.percentUsed, 150);
      // The bar itself is clamped — it has nowhere to draw 150%.
      expect(overspent.ratio, 1);
      expect(overspent.remainingMinor, -50000);
    });

    test('an unset budget divides by nothing', () {
      const unset = BudgetStatus(budget: null, spentMinor: 5000);

      expect(unset.isSet, isFalse);
      expect(unset.percentUsed, 0);
      expect(unset.ratio, 0);
      expect(unset.level, BudgetAlertLevel.none);
      expect(unset.alerts, isEmpty);
    });
  });
}
