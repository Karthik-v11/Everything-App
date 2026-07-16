import 'package:bloc_test/bloc_test.dart';
import 'package:everything_app/bloc/budget/budget_bloc.dart';
import 'package:everything_app/data/models/account.dart';
import 'package:everything_app/data/models/budget.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/notification_settings.dart';
import 'package:everything_app/data/models/scheduled_notification.dart';
import 'package:everything_app/data/models/transaction.dart';
import 'package:everything_app/data/repositories/finance_repository.dart';
import 'package:everything_app/data/repositories/notifications_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

/// Budget alert delivery — Requirements 14.3, 14.4, 14.5.
///
/// The threshold rule itself is tested in `budget_test.dart`, against the pure
/// [BudgetStatus]. What is tested here is the thing only the bloc knows: whether
/// an alert is **news**. The OS keeps no record of what it has already shown, so
/// if this is wrong every transaction in an over-budget month fires the same
/// notification again — which is how an app's notifications get switched off.
void main() {
  late _FakeNotifications notifications;
  late _FakeFinanceRepository repository;

  setUpAll(() {
    // The bloc is hydrated. An in-memory storage keeps each test's memory of what
    // it has announced to itself.
    HydratedBloc.storage = _InMemoryStorage();
  });

  setUp(() {
    notifications = _FakeNotifications();
    repository = _FakeFinanceRepository();
  });

  BudgetBloc build() => BudgetBloc(
        repository: repository,
        notificationsRepository: notifications,
      );

  /// A ₹1,000 budget for July 2026.
  final budget = Budget(
    id: 'budget-1',
    monthlyLimitMinor: 100000,
    month: 7,
    year: 2026,
  );

  UpdateSpendEvent spend(int minor, {Map<String, int>? byCategory}) =>
      UpdateSpendEvent(
        month: 7,
        year: 2026,
        spentMinor: minor,
        spentByCategory: byCategory ?? {'Food': minor},
      );

  const settings = NotificationSettings();

  blocTest<BudgetBloc, BudgetState>(
    'delivers nothing until Settings has reported the configuration',
    build: build,
    seed: () => BudgetState.initial().copyWith(budgets: [budget]),
    // Deliberately no ConfigureBudgetAlertsEvent: the same guard TasksBloc applies
    // to reminders. Announcing against the defaults would notify a user who had
    // turned notifications off.
    act: (bloc) => bloc.add(spend(90000)),
    verify: (_) => expect(notifications.shown, isEmpty),
  );

  blocTest<BudgetBloc, BudgetState>(
    'warns once at 80%, and does not warn again as more is spent below the limit',
    build: build,
    seed: () => BudgetState.initial().copyWith(budgets: [budget]),
    act: (bloc) => bloc
      ..add(const ConfigureBudgetAlertsEvent(settings: settings))
      ..add(spend(80000))
      ..add(spend(85000))
      ..add(spend(99000)),
    verify: (_) {
      expect(notifications.shown, hasLength(1));
      expect(notifications.shown.single.kind, NotificationKind.budgetWarning);
    },
  );

  blocTest<BudgetBloc, BudgetState>(
    'escalates to exceeded, and replaces the warning rather than sitting beside it',
    build: build,
    seed: () => BudgetState.initial().copyWith(budgets: [budget]),
    act: (bloc) => bloc
      ..add(const ConfigureBudgetAlertsEvent(settings: settings))
      ..add(spend(85000))
      ..add(spend(120000))
      ..add(spend(130000)),
    verify: (_) {
      expect(notifications.shown, hasLength(2));
      expect(notifications.shown.first.kind, NotificationKind.budgetWarning);
      expect(notifications.shown.last.kind, NotificationKind.budgetExceeded);

      // Same id: the alert is keyed on what it is about, not on its level, so the
      // exceeded notification takes the warning's place in the tray.
      expect(notifications.shown.first.id, notifications.shown.last.id);
    },
  );

  blocTest<BudgetBloc, BudgetState>(
    'a budget raised back out of trouble is announced again if spending returns',
    build: build,
    seed: () => BudgetState.initial().copyWith(budgets: [budget]),
    act: (bloc) => bloc
      ..add(const ConfigureBudgetAlertsEvent(settings: settings))
      ..add(spend(90000))
      // The user deletes a transaction and drops back under 80%. The alert no
      // longer holds, so it is forgotten...
      ..add(spend(10000))
      // ...and crossing the line again is news again.
      ..add(spend(90000)),
    verify: (_) {
      expect(notifications.shown, hasLength(2));
      expect(
        notifications.shown.map((n) => n.kind),
        everyElement(NotificationKind.budgetWarning),
      );
    },
  );

  blocTest<BudgetBloc, BudgetState>(
    'nothing is delivered when the user has switched notifications off',
    build: build,
    seed: () => BudgetState.initial().copyWith(budgets: [budget]),
    act: (bloc) => bloc
      ..add(
        const ConfigureBudgetAlertsEvent(
          settings: NotificationSettings(isEnabled: false),
        ),
      )
      ..add(spend(120000)),
    verify: (_) => expect(notifications.shown, isEmpty),
  );

  blocTest<BudgetBloc, BudgetState>(
    'nothing is delivered when the budget kind alone is switched off',
    build: build,
    seed: () => BudgetState.initial().copyWith(budgets: [budget]),
    act: (bloc) => bloc
      ..add(
        ConfigureBudgetAlertsEvent(
          settings: settings.withKind(
            NotificationKind.budgetExceeded,
            isOn: false,
          ),
        ),
      )
      ..add(spend(120000)),
    verify: (_) => expect(notifications.shown, isEmpty),
  );

  blocTest<BudgetBloc, BudgetState>(
    'a month with no budget set announces nothing, however much is spent',
    build: build,
    seed: () => BudgetState.initial(),
    act: (bloc) => bloc
      ..add(const ConfigureBudgetAlertsEvent(settings: settings))
      ..add(spend(9999900)),
    verify: (_) => expect(notifications.shown, isEmpty),
  );

  blocTest<BudgetBloc, BudgetState>(
    'a category over its own limit is announced separately from the monthly one',
    build: build,
    seed: () => BudgetState.initial().copyWith(
      budgets: [
        budget.copyWith(categoryLimits: const {'Food': 20000}),
      ],
    ),
    act: (bloc) => bloc
      ..add(const ConfigureBudgetAlertsEvent(settings: settings))
      ..add(spend(25000, byCategory: {'Food': 25000})),
    verify: (_) {
      // The monthly budget is at 25%, so only Food speaks up.
      expect(notifications.shown, hasLength(1));
      expect(
        notifications.shown.single.kind,
        NotificationKind.categoryBudgetExceeded,
      );
      expect(notifications.shown.single.title, contains('Food'));
    },
  );

  blocTest<BudgetBloc, BudgetState>(
    'lowering the limit below what is already spent announces at once',
    build: build,
    seed: () => BudgetState.initial().copyWith(budgets: [budget]),
    act: (bloc) => bloc
      ..add(const ConfigureBudgetAlertsEvent(settings: settings))
      // ₹300 spent of a ₹1,000 budget — quiet.
      ..add(spend(30000))
      // The user cuts the budget to ₹250. Nothing was spent, but the budget is
      // now exceeded, and waiting for the next transaction to notice would be a
      // screen that says "over budget" beside a notification that never came.
      ..add(SetBudgetEvent(budget: budget.copyWith(monthlyLimitMinor: 25000))),
    verify: (_) {
      expect(notifications.shown, hasLength(1));
      expect(notifications.shown.single.kind, NotificationKind.budgetExceeded);
    },
  );
}

/// [_FakeNotifications] records what it was asked to deliver.
class _FakeNotifications implements NotificationsRepository {
  final List<({int id, NotificationKind kind, String title, String body})>
      shown = [];

  @override
  Future<JsonResponse> show({
    required int id,
    required NotificationKind kind,
    required String title,
    required String body,
  }) async {
    shown.add((id: id, kind: kind, title: title, body: body));
    return JsonResponse.success(message: 'Delivered.');
  }

  @override
  Future<JsonResponse> initialize() async =>
      JsonResponse.success(message: 'Ready.');

  @override
  Future<JsonResponse> permissions() async => JsonResponse.success(
        message: 'Loaded.',
        data: (isGranted: true, canScheduleExact: true),
      );

  @override
  Future<JsonResponse> requestPermission() async =>
      JsonResponse.success(message: 'On.');

  @override
  Future<JsonResponse> applyPlan(
    List<ScheduledNotification> plan, {
    required Set<NotificationKind> owns,
  }) async =>
      JsonResponse.success(message: 'Up to date.');

  @override
  Future<JsonResponse> cancelAll() async =>
      JsonResponse.success(message: 'Cleared.');
}

/// [_FakeFinanceRepository] serves the budget stream. The bloc under test writes
/// through [saveBudget] and reads its list from the seeded state, so only these
/// two do any work.
class _FakeFinanceRepository implements FinanceRepository {
  @override
  Stream<List<Budget>> watchBudgets() => const Stream.empty();

  @override
  Future<JsonResponse> saveBudget(Budget budget) async =>
      JsonResponse.success(message: 'Budget saved.', data: budget);

  @override
  Stream<List<Transaction>> watchTransactions() => const Stream.empty();

  @override
  Stream<List<Account>> watchAccounts() => const Stream.empty();

  @override
  Future<JsonResponse> createTransaction(Transaction transaction) async =>
      JsonResponse.created(message: 'Added.', data: transaction);

  @override
  Future<JsonResponse> updateTransaction(Transaction transaction) async =>
      JsonResponse.success(message: 'Updated.', data: transaction);

  @override
  Future<JsonResponse> deleteTransaction(String id) async =>
      JsonResponse.success(message: 'Deleted.');

  @override
  Future<JsonResponse> seedDefaultAccounts() async =>
      JsonResponse.success(message: 'Ready.');

  @override
  Future<JsonResponse> saveAccount(Account account) async =>
      JsonResponse.success(message: 'Saved.', data: account);

  @override
  Future<JsonResponse> deleteAccount(Account account) async =>
      JsonResponse.success(message: 'Deleted.');
}

/// [_InMemoryStorage] is HydratedBloc's storage, without a file system.
class _InMemoryStorage implements Storage {
  final Map<String, dynamic> _store = {};

  @override
  dynamic read(String key) => _store[key];

  @override
  Future<void> write(String key, dynamic value) async => _store[key] = value;

  @override
  Future<void> delete(String key) async => _store.remove(key);

  @override
  Future<void> clear() async => _store.clear();

  @override
  Future<void> close() async {}
}
