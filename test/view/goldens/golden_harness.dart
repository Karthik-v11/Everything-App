import 'package:bloc_test/bloc_test.dart';
import 'package:clock/clock.dart';
import 'package:everything_app/bloc/bookmarks/bookmarks_bloc.dart';
import 'package:everything_app/bloc/briefing/briefing_bloc.dart';
import 'package:everything_app/bloc/budget/budget_bloc.dart';
import 'package:everything_app/bloc/documents/documents_bloc.dart';
import 'package:everything_app/bloc/finance/finance_bloc.dart';
import 'package:everything_app/bloc/news/news_bloc.dart';
import 'package:everything_app/bloc/projects/projects_bloc.dart';
import 'package:everything_app/bloc/settings/settings_bloc.dart';
import 'package:everything_app/bloc/tasks/tasks_bloc.dart';
import 'package:everything_app/bloc/theme/theme_bloc.dart';
import 'package:everything_app/bloc/to_buy/to_buy_bloc.dart';
import 'package:everything_app/bloc/vault/vault_bloc.dart';
import 'package:everything_app/bloc/watchlist/watchlist_bloc.dart';
import 'package:everything_app/bloc/weather/weather_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The instant every golden is rendered at.
///
/// Deliberately in the past and never derived from the real clock: the fixtures
/// are all written relative to it, so the same pixels come out whatever day the
/// suite runs.
final DateTime kFrozenNow = DateTime(2026, 1, 15, 9, 30);

/// A phone-sized surface at 1:1, so the golden's pixels are its logical pixels.
const Size kGoldenSurface = Size(390, 844);

/// [pumpGolden] renders [child] on a fixed surface under the real app theme.
///
/// The theme is the production one — `AppTheme.build` via [ThemeState] — rather
/// than a stand-in, because the colour and type decisions are most of what these
/// goldens exist to protect.
Future<void> pumpGolden(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = kGoldenSurface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: const ThemeState().themeData(Brightness.dark),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

/// [freeze] pins [clock] for the whole of [body], including the pumps inside it.
Future<void> freeze(Future<void> Function() body) =>
    withClock(Clock.fixed(kFrozenNow), body);

/// The blocs are mocked rather than built: every real constructor reaches for the
/// encrypted database or `HydratedBloc.storage`, neither of which exists in a
/// widget test. [whenListen] with an empty stream gives each one a fixed state and
/// no emissions, which is exactly what a golden needs.
class MockTasksBloc extends MockBloc<TasksEvent, TasksState>
    implements TasksBloc {}

class MockFinanceBloc extends MockBloc<FinanceEvent, FinanceState>
    implements FinanceBloc {}

class MockBudgetBloc extends MockBloc<BudgetEvent, BudgetState>
    implements BudgetBloc {}

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class MockWeatherBloc extends MockBloc<WeatherEvent, WeatherState>
    implements WeatherBloc {}

class MockNewsBloc extends MockBloc<NewsEvent, NewsState> implements NewsBloc {}

class MockBriefingBloc extends MockBloc<BriefingEvent, BriefingState>
    implements BriefingBloc {}

class MockBookmarksBloc extends MockBloc<BookmarksEvent, BookmarksState>
    implements BookmarksBloc {}

class MockToBuyBloc extends MockBloc<ToBuyEvent, ToBuyState>
    implements ToBuyBloc {}

class MockWatchlistBloc extends MockBloc<WatchlistEvent, WatchlistState>
    implements WatchlistBloc {}

class MockVaultBloc extends MockBloc<VaultEvent, VaultState>
    implements VaultBloc {}

class MockProjectsBloc extends MockBloc<ProjectsEvent, ProjectsState>
    implements ProjectsBloc {}

class MockDocumentsBloc extends MockBloc<DocumentsEvent, DocumentsState>
    implements DocumentsBloc {}
