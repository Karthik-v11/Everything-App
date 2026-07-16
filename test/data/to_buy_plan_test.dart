import 'package:everything_app/data/models/notification_settings.dart';
import 'package:everything_app/data/models/to_buy_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// The to-buy reminder rules (Requirement 7.3).
///
/// Driven through the pure planner with an injected `now`, so "the reminder is
/// withdrawn once the item is bought" is an assertion rather than a wait.
///
/// The planner is *declarative*: it describes the reminders that should be pending,
/// and `NotificationService.applyPlan` cancels whatever it does not contain. So the
/// tests below never assert that something was cancelled — they assert that the plan
/// no longer *contains* it, which is the same thing and is the reason no cancel call
/// exists anywhere in the To Buy module.
void main() {
  final now = DateTime(2026, 7, 14, 9);

  ToBuyItem item({
    String id = 'i1',
    String name = 'Headphones',
    String? store,
    bool isPurchased = false,
    DateTime? reminderAt,
  }) =>
      ToBuyItem(
        id: id,
        name: name,
        store: store,
        isPurchased: isPurchased,
        reminderAt: reminderAt,
        createdAt: now,
      );

  const settings = NotificationSettings();

  List<String> plan(List<ToBuyItem> items, {NotificationSettings? config}) =>
      ToBuyPlan.build(
        items: items,
        settings: config ?? settings,
        now: now,
      ).map((notification) => notification.title).toList();

  test('an item with a future reminder is scheduled', () {
    final planned = ToBuyPlan.build(
      items: [item(reminderAt: now.add(const Duration(days: 1)))],
      settings: settings,
      now: now,
    );

    expect(planned, hasLength(1));
    expect(planned.single.title, 'Headphones');
    expect(planned.single.kind, NotificationKind.toBuyReminder);
    expect(planned.single.at, now.add(const Duration(days: 1)));
  });

  test('the store is named in the body when there is one', () {
    final planned = ToBuyPlan.build(
      items: [
        item(store: 'Croma', reminderAt: now.add(const Duration(days: 1))),
      ],
      settings: settings,
      now: now,
    );

    expect(planned.single.body, contains('Croma'));
  });

  test('an item with no reminder is not scheduled', () {
    expect(plan([item()]), isEmpty);
  });

  test('a purchased item is not scheduled', () {
    // The whole reason nothing in the app cancels a to-buy reminder: buying the
    // thing simply removes it from the plan, and the reconciliation withdraws the
    // alarm. This holds for a write from anywhere — the checkbox, the sheet, or code
    // that does not exist yet.
    expect(
      plan([
        item(
          isPurchased: true,
          reminderAt: now.add(const Duration(days: 1)),
        ),
      ]),
      isEmpty,
    );
  });

  test('a reminder whose moment has passed is not scheduled', () {
    // The OS would fire it immediately or reject it, and neither is what the user
    // asked for.
    expect(
      plan([item(reminderAt: now.subtract(const Duration(hours: 1)))]),
      isEmpty,
    );
  });

  test('nothing is scheduled when the master switch is off', () {
    expect(
      plan(
        [item(reminderAt: now.add(const Duration(days: 1)))],
        config: const NotificationSettings(isEnabled: false),
      ),
      isEmpty,
    );
  });

  test('nothing is scheduled when to-buy reminders are switched off', () {
    // The kind switched off individually, with the master switch still on — the case
    // a naive `isEnabled` check would miss.
    expect(
      plan(
        [item(reminderAt: now.add(const Duration(days: 1)))],
        config: settings.withKind(
          NotificationKind.toBuyReminder,
          isOn: false,
        ),
      ),
      isEmpty,
    );
  });

  test('task reminders being off does not silence to-buy reminders', () {
    // The two kinds are independent, and the queue is partitioned by kind. A user who
    // silenced their task alerts has not asked to stop hearing about the thing they
    // wanted to buy.
    expect(
      plan(
        [item(reminderAt: now.add(const Duration(days: 1)))],
        config: settings.withKind(NotificationKind.reminder, isOn: false),
      ),
      ['Headphones'],
    );
  });

  test('the plan is ordered soonest first', () {
    final planned = ToBuyPlan.build(
      items: [
        item(
          id: 'later',
          name: 'Later',
          reminderAt: now.add(const Duration(days: 5)),
        ),
        item(
          id: 'sooner',
          name: 'Sooner',
          reminderAt: now.add(const Duration(days: 1)),
        ),
      ],
      settings: settings,
      now: now,
    );

    expect(planned.map((n) => n.title), ['Sooner', 'Later']);
  });

  test('two items get two distinct notification ids', () {
    final planned = ToBuyPlan.build(
      items: [
        item(id: 'a', reminderAt: now.add(const Duration(days: 1))),
        item(id: 'b', reminderAt: now.add(const Duration(days: 2))),
      ],
      settings: settings,
      now: now,
    );

    // Colliding ids would mean one item silently overwriting the other's alarm.
    expect(planned.map((n) => n.id).toSet(), hasLength(2));
  });

  test('an item keeps the same notification id across rebuilds', () {
    // The id has to survive a restart so that yesterday's armed alarm can be matched
    // against today's plan. A drifting id would orphan every reminder in the OS
    // queue on every launch.
    List<int> ids() => ToBuyPlan.build(
          items: [item(reminderAt: now.add(const Duration(days: 1)))],
          settings: settings,
          now: now,
        ).map((n) => n.id).toList();

    expect(ids(), ids());
  });

  test('a new build enables the to-buy kind for an existing user', () {
    // Settings written before this kind existed list the kinds that *were* switchable
    // then. Without that record, every kind missing from `enabledKinds` would look
    // like one the user had turned off — and to-buy reminders would arrive silently
    // disabled for everyone who already had settings on disk, with no toggle in
    // Settings explaining why nothing was being delivered.
    final old = {
      'isEnabled': true,
      'enabledKinds': ['reminder', 'deadline'],
      'knownKinds': ['reminder', 'deadline', 'missed'],
    };

    final restored = NotificationSettings.fromJson(old);

    expect(restored.allows(NotificationKind.toBuyReminder), isTrue);
    expect(restored.allows(NotificationKind.missed), isFalse);
  });
}
