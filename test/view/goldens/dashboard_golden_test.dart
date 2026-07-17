import 'package:bloc_test/bloc_test.dart';
import 'package:everything_app/bloc/briefing/briefing_bloc.dart';
import 'package:everything_app/bloc/budget/budget_bloc.dart';
import 'package:everything_app/bloc/finance/finance_bloc.dart';
import 'package:everything_app/bloc/news/news_bloc.dart';
import 'package:everything_app/bloc/settings/settings_bloc.dart';
import 'package:everything_app/bloc/tasks/tasks_bloc.dart';
import 'package:everything_app/bloc/weather/weather_bloc.dart';
import 'package:everything_app/data/models/account.dart';
import 'package:everything_app/data/models/article.dart';
import 'package:everything_app/data/models/budget.dart';
import 'package:everything_app/data/models/category.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/data/models/transaction.dart';
import 'package:everything_app/data/models/weather.dart';
import 'package:everything_app/view/screens/dashboard/dashboard_page.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

/// The Dashboard is the one screen that owns no data: it is six blocs put side by
/// side, and every claim it makes is about *now* — the greeting's time of day, the
/// date line, today's open work, and this month's money regardless of which month
/// the Finance tab is scrolled to. That makes it both the most valuable screen to
/// pin and the one that could not be pinned at all before the clock was injectable.
///
/// The finance fixture is deliberately parked on a *different* selected month
/// (March) from the frozen clock (January): the Dashboard must still report
/// January, because [FinanceState.totalsFor] is what it reads rather than the
/// selected-month getters. A golden is what catches that being swapped back.
///
/// The 'Today's Tasks' preview is likewise not a filter on the wall clock but on
/// the frozen one, and it includes the overdue task by design — a dashboard that
/// hides what was already late is the one screen that must not.
void main() {
  final createdAt = DateTime(2026, 1, 10, 8);

  const work = Category(id: 'c1', name: 'Work', colorValue: 0xFF4C8BF5);
  const home = Category(id: 'c2', name: 'Home', colorValue: 0xFF66BB6A);

  final tasks = TasksState(
    selectedDate: DateTime(2026, 1, 15),
    categories: const [work, home],
    tasks: [
      Task(
        id: 't1',
        title: 'Renew domain registration',
        dueDate: DateTime(2026, 1, 13, 9),
        priority: TaskPriority.critical,
        categoryId: 'c1',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      Task(
        id: 't2',
        title: 'Ship the golden tests',
        dueDate: DateTime(2026, 1, 15, 18),
        priority: TaskPriority.high,
        categoryId: 'c1',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      Task(
        id: 't3',
        title: 'Water the plants',
        dueDate: DateTime(2026, 1, 15, 20),
        priority: TaskPriority.low,
        categoryId: 'c2',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      // Tomorrow: not today's work, so the preview must leave it out.
      Task(
        id: 't4',
        title: 'Team retrospective',
        dueDate: DateTime(2026, 1, 16, 11),
        categoryId: 'c1',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    ],
  );

  final finance = FinanceState(
    // Deliberately not the frozen month — see the note above.
    selectedMonth: DateTime(2026, 3),
    accounts: const [Account(id: 'a1', name: 'HDFC', type: AccountType.bank)],
    transactions: [
      Transaction(
        id: 'i1',
        title: 'January salary',
        amountMinor: 4000000,
        date: DateTime(2026, 1, 1, 9),
        accountId: 'a1',
        type: TransactionType.income,
        category: 'Salary',
        createdAt: DateTime(2026, 1, 1, 9),
      ),
      Transaction(
        id: 'e1',
        title: 'Rent',
        amountMinor: 2500000,
        date: DateTime(2026, 1, 2, 12),
        accountId: 'a1',
        category: 'Bills',
        createdAt: DateTime(2026, 1, 2, 12),
      ),
      Transaction(
        id: 'e2',
        title: 'Groceries',
        amountMinor: 800000,
        date: DateTime(2026, 1, 6, 12),
        accountId: 'a1',
        category: 'Food',
        createdAt: DateTime(2026, 1, 6, 12),
      ),
      // December, so the "vs last month" badge has something to compare against.
      Transaction(
        id: 'd1',
        title: 'December living costs',
        amountMinor: 2800000,
        date: DateTime(2025, 12, 10, 12),
        accountId: 'a1',
        category: 'Bills',
        createdAt: DateTime(2025, 12, 10, 12),
      ),
    ],
  );

  const budget = BudgetState(
    month: 1,
    year: 2026,
    budgets: [
      Budget(id: 'b1', monthlyLimitMinor: 4500000, month: 1, year: 2026),
    ],
  );

  final weather = WeatherState(
    city: 'Bengaluru',
    weather: Weather(
      city: 'Bengaluru',
      temperatureC: 27.4,
      feelsLikeC: 28.1,
      iconCode: '02d',
      description: 'few clouds',
      humidity: 64,
      windSpeedMs: 3.2,
      observedAt: kFrozenNow.subtract(const Duration(minutes: 20)),
    ),
    // Fresh against the frozen clock, so the stale banner stays down and the
    // golden records the Dashboard's normal state.
    fetchedAt: kFrozenNow.subtract(const Duration(minutes: 10)),
  );

  final news = NewsState(
    articles: {
      NewsCategory.all: const [
        // No image URLs: an Image.network in a widget test resolves to the error
        // builder, and a golden of six fallback boxes says nothing about the card.
        Article(
          title: 'Monsoon forecast revised upward for the southern peninsula',
          url: 'https://example.com/1',
          source: 'The Hindu',
        ),
        Article(
          title: 'Metro Phase 3 clears final environmental review',
          url: 'https://example.com/2',
          source: 'Deccan Herald',
        ),
        Article(
          title: 'Rupee steadies as inflation print comes in below estimates',
          url: 'https://example.com/3',
          source: 'Mint',
        ),
      ],
    },
    fetchedAt: {NewsCategory.all: kFrozenNow.subtract(const Duration(minutes: 5))},
  );

  const settings = SettingsState(userName: 'Karthik');

  // The briefing is pinned to a fixed line rather than generated: BriefingBloc is
  // mocked like every other bloc here, so no engine is reached and the card
  // renders exactly what it is given. What this golden protects is the card, not
  // the sentence.
  final briefing = BriefingState(
    text: 'Good morning. You have 3 things planned today.',
    generatedAt: kFrozenNow.subtract(const Duration(minutes: 2)),
  );

  testWidgets('the Dashboard renders the day at a glance', (tester) async {
    await freeze(() async {
      final tasksBloc = MockTasksBloc();
      final financeBloc = MockFinanceBloc();
      final budgetBloc = MockBudgetBloc();
      final settingsBloc = MockSettingsBloc();
      final weatherBloc = MockWeatherBloc();
      final newsBloc = MockNewsBloc();
      final briefingBloc = MockBriefingBloc();

      whenListen(tasksBloc, const Stream<TasksState>.empty(),
          initialState: tasks);
      whenListen(financeBloc, const Stream<FinanceState>.empty(),
          initialState: finance);
      whenListen(budgetBloc, const Stream<BudgetState>.empty(),
          initialState: budget);
      whenListen(settingsBloc, const Stream<SettingsState>.empty(),
          initialState: settings);
      whenListen(weatherBloc, const Stream<WeatherState>.empty(),
          initialState: weather);
      whenListen(newsBloc, const Stream<NewsState>.empty(), initialState: news);
      whenListen(briefingBloc, const Stream<BriefingState>.empty(),
          initialState: briefing);

      await pumpGolden(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<WeatherBloc>.value(value: weatherBloc),
            BlocProvider<NewsBloc>.value(value: newsBloc),
            BlocProvider<TasksBloc>.value(value: tasksBloc),
            BlocProvider<FinanceBloc>.value(value: financeBloc),
            BlocProvider<BudgetBloc>.value(value: budgetBloc),
            BlocProvider<BriefingBloc>.value(value: briefingBloc),
          ],
          child: const DashboardPage(),
        ),
      );

      // 09:30 on the frozen clock — the greeting is the clearest evidence the
      // freeze reaches the build path at all.
      expect(find.text('Good Morning, Karthik!'), findsOneWidget);
      expect(find.text('Team retrospective'), findsNothing,
          reason: "tomorrow's work is not today's");
      expect(find.text('Showing saved news'), findsNothing,
          reason: 'the cache is fresh against the frozen clock');

      await expectLater(
        find.byType(DashboardPage),
        matchesGoldenFile('goldens/dashboard_page.png'),
      );
    });
  });
}
