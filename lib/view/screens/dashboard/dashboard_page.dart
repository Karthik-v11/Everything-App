import 'package:clock/clock.dart';
import 'package:everything_app/bloc/briefing/briefing_bloc.dart';
import 'package:everything_app/bloc/budget/budget_bloc.dart';
import 'package:everything_app/bloc/finance/finance_bloc.dart';
import 'package:everything_app/bloc/news/news_bloc.dart';
import 'package:everything_app/bloc/settings/settings_bloc.dart';
import 'package:everything_app/bloc/tasks/tasks_bloc.dart';
import 'package:everything_app/bloc/weather/weather_bloc.dart';
import 'package:everything_app/core/route/routes.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/entity/ai_prompt.dart';
import 'package:everything_app/data/entity/briefing_facts.dart';
import 'package:everything_app/data/models/article.dart';
import 'package:everything_app/data/models/budget.dart';
import 'package:everything_app/data/models/weather.dart';
import 'package:everything_app/view/screens/dashboard/city_sheet.dart';
import 'package:everything_app/view/screens/dashboard/news_category_sheet.dart';
import 'package:everything_app/view/screens/tasks/task_sheet.dart';
import 'package:everything_app/view/widgets/briefing_card.dart';
import 'package:everything_app/view/widgets/completing_task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// How many of today's tasks the Dashboard lists before "Show All".
const int _kTaskPreviewCount = 3;

/// How many headlines the Top Stories section previews.
const int _kNewsCount = 10;

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  Future<void> _refresh(BuildContext context) async {
    context.read<WeatherBloc>().add(const FetchWeatherEvent());
    context.read<NewsBloc>().add(const FetchNewsEvent());
    context.read<BriefingBloc>().add(const RefreshBriefingEvent());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      top: false,
      child: RefreshIndicator(
        onRefresh: () => _refresh(context),
        child: Stack(
          children: [
            const _GreetingGlow(),
            ListView(
              padding: responsivePadding(context).copyWith(top: 32, bottom: 140),
              children: const [
                _Greeting(),
                Gap(14),
                _DateAndWeather(),
                Gap(16),
                _StaleBanner(),
                _Briefing(),
                Gap(28),
                _Agenda(),
                Gap(16),
                _MoneyAndUpcoming(),
                Gap(28),
                _TopStories(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// [_GreetingGlow] is the decorative radial wash behind the greeting.
///
/// Uses [ColorScheme.primary] because accent is a user setting. [IgnorePointer]
/// so it never eats the pull-to-refresh gesture it sits under.
class _GreetingGlow extends StatelessWidget {
  const _GreetingGlow();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return IgnorePointer(
      child: SizedBox(
        height: 280,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.4, -1),
              radius: 1.1,
              colors: [
                colors.primary.withValues(alpha: 0.18),
                colors.primary.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (previous, current) => previous.userName != current.userName,
      builder: (context, state) {
        final name = state.userName;

        return Row(
          children: [
            Expanded(
              child: Text(
                name.isEmpty
                    ? '${Helpers.greeting(at: clock.now())}!'
                    : '${Helpers.greeting(at: clock.now())}, $name!',
                style: context.texts.headlineSmall,
              ),
            ),
            const Gap(8),
            IconButton(
              onPressed: () => context.pushNamed(settingsRoute),
              icon: const Icon(Icons.person_rounded),
              color: Colors.white,
              tooltip: 'Settings',
            ),
          ],
        );
      },
    );
  }
}

/// [_DateAndWeather] is the two outlined pills (Requirements 3.1, 3.2).
///
/// Outlined, not filled: these are labels, not buttons competing with the AI orb.
class _DateAndWeather extends StatelessWidget {
  const _DateAndWeather();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // The date takes the larger share: `15th September, Wednesday` is the
        // longest this line gets and mono is a wide face, so the common case
        // fits without ellipsing.
        Expanded(
          flex: 9,
          child: _Pill(
            // No onTap: the date has nowhere to go, but keeps the pill shape so
            // the row reads as a pair.
            child: Text(
              clock.now().dashboardDate,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.labelSmall?.copyWith(
                color: context.colors.onSurface,
              ),
            ),
          ),
        ),
        const Gap(10),
        const Expanded(flex: 8, child: _WeatherPill()),
      ],
    );
  }
}

/// [_WeatherPill] is the outlined weather pill: `Bengaluru, 27° C`
/// (Requirement 3.2).
///
/// Three states, no spinner: a temperature, a "set location" prompt, or a dash
/// while the first fetch is in flight. A spinner this small only flickers.
class _WeatherPill extends StatelessWidget {
  const _WeatherPill();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WeatherBloc, WeatherState>(
      builder: (context, state) {
        final colors = context.colors;
        final weather = state.weather;

        if (!state.hasCity) {
          return _Pill(
            onTap: () => showCitySheet(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const Gap(6),
                Flexible(
                  child: Text(
                    'Set location',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.labelSmall?.copyWith(
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return _Pill(
          onTap: () => context.pushNamed(weatherRoute),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Only the city ellipses: a long name is what runs the pill out
              // of room, and the temperature is what the pill exists to show.
              Flexible(
                child: Text(
                  state.city,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelSmall?.copyWith(
                    color: colors.onSurface,
                  ),
                ),
              ),
              Text(
                ', ${weather?.temperature ?? '—'} C',
                style: context.texts.labelSmall?.copyWith(
                  color: colors.onSurface,
                ),
              ),
              const Gap(6),
              Icon(
                (weather?.condition ?? WeatherCondition.unknown).icon,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// [_Pill] is the outlined capsule the date and weather share.
///
/// [onTap] is optional: a pill with nowhere to go renders without an [InkWell]
/// rather than with a dead one.
class _Pill extends StatelessWidget {
  const _Pill({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final content = Container(
      height: 44,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: child,
    );

    final tap = onTap;
    if (tap == null) return content;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(24),
        child: content,
      ),
    );
  }
}

class _Briefing extends StatelessWidget {
  const _Briefing();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TasksBloc, TasksState>(
      buildWhen: (previous, current) => previous.tasks != current.tasks,
      builder: (context, tasks) {
        return BlocBuilder<WeatherBloc, WeatherState>(
          buildWhen: (previous, current) =>
              previous.weather != current.weather ||
              previous.city != current.city,
          builder: (context, weather) {
            return BlocBuilder<NewsBloc, NewsState>(
              buildWhen: (previous, current) =>
                  previous.visibleArticles != current.visibleArticles,
              builder: (context, news) {
                final todayTasks = tasks.todayTasks;

                final facts = BriefingFacts(
                  now: clock.now(),
                  city: weather.hasCity ? weather.city : null,
                  weather: weather.weather,
                  taskCount: todayTasks.length,
                  overdueCount: tasks.overdueCount,
                  taskTitles: [
                    for (final task in todayTasks.take(AiPrompt.maxBriefingTasks))
                      task.title,
                  ],
                  headlines: [
                    for (final article
                        in news.visibleArticles.take(AiPrompt.maxBriefingHeadlines))
                      article.title,
                  ],
                );

                context.read<BriefingBloc>().add(
                      BriefingFactsChanged(facts: facts),
                    );

                return const BriefingCard();
              },
            );
          },
        );
      },
    );
  }
}

/// [_StaleBanner] is the only thing the Dashboard says about being offline
/// (Requirement 3.11).
///
/// Cached weather and news are otherwise shown without comment — offline is
/// normal, not an error. The banner appears only once the cache is older than
/// [kStaleCacheThreshold].
class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WeatherBloc, WeatherState>(
      builder: (context, weather) {
        return BlocBuilder<NewsBloc, NewsState>(
          builder: (context, news) {
            final isWeatherStale = weather.hasData && weather.isStale;
            if (!isWeatherStale && !news.isCurrentStale) {
              return const SizedBox.shrink();
            }

            final colors = context.colors;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 16,
                      color: colors.onSurfaceVariant,
                    ),
                    const Gap(8),
                    Expanded(
                      child: Text(
                        isWeatherStale
                            ? 'Showing saved weather and news · ${weather.age}'
                            : 'Showing saved news',
                        style: context.texts.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// [_Agenda] is today's open work (Requirements 3.4, 3.5, 3.6).
///
/// `3 Overdue · 7 tasks today` means seven in total, three of them late — not
/// ten: [TasksState.todayTasks] already includes the overdue ones.
class _Agenda extends StatelessWidget {
  const _Agenda();

  /// [_showAll] is Requirement 3.6: the Tasks module, filtered to today.
  ///
  /// Filter is dispatched before the tab switch so the list is already narrowed
  /// when it comes into view.
  void _showAll(BuildContext context) {
    context.read<TasksBloc>().add(
          const ChangeFilterEvent(filter: TaskFilter.today),
        );
    context.goNamed(tasksRoute);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TasksBloc, TasksState>(
      // Derived only from tasks, categories and the load flag: the Tasks tab's
      // selected date, filter and search query do not change this preview.
      buildWhen: (previous, current) =>
          previous.tasks != current.tasks ||
          previous.categories != current.categories ||
          previous.isLoading != current.isLoading,
      builder: (context, state) {
        final tasks = state.todayTasks;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                "Today's Agenda",
                style: context.texts.headlineMedium,
              ),
            ),
            const Gap(4),
            Center(child: _AgendaSubline(state: state)),
            const Gap(16),
            if (tasks.isEmpty)
              if (state.isLoading)
                const _Empty(message: 'Loading…')
              else
                _AgendaEmpty(completedToday: state.completedTodayCount)
            else ...[
              for (final task in tasks.take(_kTaskPreviewCount))
                // Requirement 3.5: same actions and completion exit as the
                // Tasks list itself, so the card behaves identically on both.
                CompletingTaskCard(
                  key: ValueKey(task.id),
                  task: task,
                  category: state.categoryOf(task),
                  onTap: () => showTaskSheet(context, task: task),
                ),
              const Gap(4),
              _ShowAllButton(onTap: () => _showAll(context)),
            ],
          ],
        );
      },
    );
  }
}

/// [_AgendaSubline] is `3 Overdue · 7 tasks today`.
class _AgendaSubline extends StatelessWidget {
  const _AgendaSubline({required this.state});

  final TasksState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final overdue = state.overdueCount;
    final total = state.todayTasks.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Hidden entirely at zero: "0 Overdue" in red misreports a clean day.
        if (overdue > 0) ...[
          Text(
            '$overdue Overdue',
            style: texts.labelMedium?.copyWith(color: colors.error),
          ),
          Text(
            '  ·  ',
            style: texts.labelMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
        Text(
          total == 1 ? '1 task today' : '$total tasks today',
          style: texts.labelMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// [_ShowAllButton] is the full-width outlined `Show All ›` under the rows.
class _ShowAllButton extends StatelessWidget {
  const _ShowAllButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.onSurface,
        side: BorderSide(color: colors.outlineVariant),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Show All', style: context.texts.labelLarge),
          const Icon(Icons.chevron_right_rounded, size: 18),
        ],
      ),
    );
  }
}

/// [_MoneyAndUpcoming] is the two fixed panels of Requirement 3.7: what is left
/// to spend and what is about to happen; the rest lives in Finance
/// (Requirement 3.8).
///
/// Every figure is about *this* month regardless of the month the Finance tab is
/// scrolled to — hence [FinanceState.totalsFor] rather than the selected-month
/// getters. [BudgetStatus] is a pure value, so this month's limit and spending
/// can be combined here without moving [BudgetBloc] off the month it tracks.
class _MoneyAndUpcoming extends StatelessWidget {
  const _MoneyAndUpcoming();

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          Expanded(child: _RemainingPanel()),
          Gap(10),
          Expanded(child: _UpcomingPanel()),
        ],
      ),
    );
  }
}

/// [_RemainingPanel] is what is left of the month's budget.
class _RemainingPanel extends StatelessWidget {
  const _RemainingPanel();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FinanceBloc, FinanceState>(
      // Derived from this month's transactions: the Finance tab's selected
      // month, filters and search query do not change it.
      buildWhen: (previous, current) =>
          previous.transactions != current.transactions,
      builder: (context, finance) {
        return BlocBuilder<BudgetBloc, BudgetState>(
          // Only the limit, not the spend-and-alert churn FinanceBloc drives
          // through this bloc on every write.
          buildWhen: (previous, current) => previous.budgets != current.budgets,
          builder: (context, budgets) {
            final colors = context.colors;
            final texts = context.texts;
            final now = clock.now();

            final month = finance.totalsFor(now);
            final status = BudgetStatus(
              budget: budgets.budgetFor(month: now.month, year: now.year),
              spentMinor: month.expenseMinor,
            );

            return _Panel(
              title: 'Remaining',
              // An unset budget has no remainder, so the panel routes to
              // budget setup rather than showing "₹0".
              onTap: () => context.goNamed(
                status.isSet ? financeRoute : budgetsRoute,
              ),
              child: !status.isSet
                  ? Text(
                      'Not set',
                      style: texts.headlineSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: Text(
                                Helpers.formatMoney(
                                  status.remainingMinor,
                                  compact: true,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: texts.headlineSmall?.copyWith(
                                  // An overspent month is the figure the user
                                  // most needs to notice.
                                  color: status.remainingMinor < 0
                                      ? colors.error
                                      : colors.primary,
                                ),
                              ),
                            ),
                            const Gap(6),
                            Text(
                              'this month',
                              style: texts.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const Gap(10),
                        _BudgetBar(status: status),
                        const Gap(8),
                        Text(
                          '${status.percentUsed.round()}% used · '
                          '${Helpers.formatMoney(status.spentMinor, compact: true)} used',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: texts.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }
}

/// [_BudgetBar] is the progress bar under the remaining figure.
class _BudgetBar extends StatelessWidget {
  const _BudgetBar({required this.status});

  final BudgetStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        tween: Tween(end: status.ratio),
        builder: (context, ratio, _) => LinearProgressIndicator(
          value: ratio,
          minHeight: 6,
          backgroundColor: colors.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation(
            status.remainingMinor < 0 ? colors.error : colors.primary,
          ),
        ),
      ),
    );
  }
}

/// [_UpcomingPanel] is the next task due later today (Requirement 3.7).
///
/// Not a calendar event — the app has no calendar. It is
/// [TasksState.nextUpcoming]: the earliest pending task still ahead of the clock
/// today. The countdown rebuilds only when [TasksBloc] emits, not every minute:
/// a slightly stale "in 10 mins" is cheaper than a permanent [Timer.periodic].
class _UpcomingPanel extends StatelessWidget {
  const _UpcomingPanel();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TasksBloc, TasksState>(
      buildWhen: (previous, current) => previous.tasks != current.tasks,
      builder: (context, state) {
        final colors = context.colors;
        final texts = context.texts;
        final task = state.nextUpcoming;

        return _Panel(
          title: 'Upcoming',
          // Accent-outlined: the only thing on the Dashboard with a deadline.
          border: task == null ? null : colors.primary,
          onTap: () => context.goNamed(tasksRoute),
          // An empty panel keeps its footprint rather than collapsing the row
          // (CLAUDE.md §12).
          child: task == null
              ? Text(
                  'Nothing scheduled',
                  style: texts.titleMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: texts.titleMedium,
                    ),
                    const Gap(6),
                    Text(
                      task.dueDate!.countdown,
                      style: texts.labelMedium?.copyWith(color: colors.primary),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// [_Panel] is the shared shell of the two Dashboard panels: a title with a
/// chevron, and whatever the panel is about beneath it.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    required this.onTap,
    this.border,
  });

  final String title;
  final Widget child;
  final VoidCallback onTap;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final outline = border;

    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: outline == null ? null : Border.all(color: outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: context.texts.titleSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
              const Gap(10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// [_TopStories] is the headline preview (Requirements 3.9, 3.10).
///
/// Category selection lives in the News destination, not here: the Dashboard
/// never dispatches `SelectNewsCategoryEvent` and renders whatever tab that
/// module is on.
///
/// Live scores, when they land, take a fixed-height box between this header and
/// the rows, from a bloc of their own (design.md §7).
class _TopStories extends StatelessWidget {
  const _TopStories();

  /// [_open] hands the article to the external browser, not a webview
  /// (Requirement 3.10).
  Future<void> _open(BuildContext context, Article article) async {
    final url = Uri.tryParse(article.url);

    final isOpened = url != null &&
        await launchUrl(url, mode: LaunchMode.externalApplication);

    if (!isOpened && context.mounted) {
      context.showSnack('Could not open that article.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NewsBloc, NewsState>(
      // Without this, unrelated `message` churn re-issues every article image.
      buildWhen: (previous, current) =>
          previous.visibleArticles != current.visibleArticles ||
          previous.isLoading != current.isLoading ||
          previous.error != current.error,
      builder: (context, state) {
        final articles = state.visibleArticles;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: 'Top Stories',
              onAction: () => showNewsCategorySheet(context),
            ),
            const Gap(12),
            if (articles.isEmpty)
              _Empty(
                message: switch ((state.isLoading, state.error)) {
                  (true, _) => 'Loading headlines…',
                  (false, '') => 'No headlines right now.',
                  (false, final error) => error,
                },
              )
            else
              for (final article in articles.take(_kNewsCount))
                _ArticleCard(
                  article: article,
                  onTap: () => _open(context, article),
                ),
          ],
        );
      },
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.article, required this.onTap});

  final Article article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        article.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.titleMedium,
                      ),
                      const Gap(8),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              article.source,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.texts.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const Gap(6),
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Gap(12),
                _Thumbnail(url: article.imageUrl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [_Thumbnail] is the 96×72 picture on the right of a headline.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final image = url;

    // The box is reserved whether or not a picture arrives, so the row does not
    // reflow when one does (CLAUDE.md §12).
    Widget wrap(Widget child) => ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: 96, height: 72, child: child),
        );

    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Icon(
        Icons.article_outlined,
        size: 20,
        color: colors.onSurfaceVariant,
      ),
    );

    if (image == null || image.isEmpty) return wrap(placeholder);

    return wrap(
      Image.network(
        image,
        fit: BoxFit.cover,
        // Decode to the 96px box, not the source width: a full-size article
        // image costs megabytes of RGBA per card in a scrolling list.
        cacheWidth: (96 * MediaQuery.devicePixelRatioOf(context)).round(),
        // The card keeps its shape and drops the image rather than showing a
        // broken one. Offline, this is every card.
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : ColoredBox(color: colors.surfaceContainerHighest),
      ),
    );
  }
}

/// [_SectionHeader] is the `Top Stories ›` line.
///
/// The action is an unlabelled chevron, so the tooltip is what tells a screen
/// reader where it leads (CLAUDE.md §9).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onAction});

  final String title;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final action = onAction;

    return Row(
      children: [
        Expanded(
          child: Text(title, style: context.texts.headlineSmall),
        ),
        if (action != null)
          IconButton(
            onPressed: action,
            icon: const Icon(Icons.chevron_right_rounded),
            iconSize: 22,
            color: colors.onSurfaceVariant,
            visualDensity: VisualDensity.compact,
            tooltip: 'Change category',
          ),
      ],
    );
  }
}

/// [_AgendaEmpty] is the agenda with nothing open on it.
///
/// Two different days read as "no tasks": one where everything got done and one
/// where nothing was planned. [completedToday] separates them so a cleared list
/// is shown as finished work rather than as an absence.
class _AgendaEmpty extends StatelessWidget {
  const _AgendaEmpty({required this.completedToday});

  final int completedToday;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final isEarned = completedToday > 0;

    // Primary for a cleared day, neutral for an unplanned one: the celebratory
    // tint has to be earned, or every empty day looks like an achievement.
    final accent = isEarned ? colors.primary : colors.onSurfaceVariant;

    return Semantics(
      label: isEarned
          ? 'All tasks done today. $completedToday completed.'
          : 'Nothing scheduled for today.',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: isEarned
              ? colors.primaryContainer.withValues(alpha: 0.35)
              : colors.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isEarned
                ? colors.primary.withValues(alpha: 0.25)
                : colors.outlineVariant,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isEarned
                    ? Icons.task_alt_rounded
                    : Icons.wb_sunny_outlined,
                color: accent,
                size: 28,
              ),
            ),
            const Gap(14),
            Text(
              isEarned ? 'Agenda cleared' : 'A clear day ahead',
              textAlign: TextAlign.center,
              style: texts.titleMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Gap(6),
            Text(
              isEarned
                  ? completedToday == 1
                      ? 'You finished the one task on today’s list.'
                      : 'You finished all $completedToday tasks on today’s list.'
                  : 'Nothing due today. Tap + to plan something.',
              textAlign: TextAlign.center,
              style: texts.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: context.texts.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
