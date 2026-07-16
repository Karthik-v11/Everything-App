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
import 'package:everything_app/data/models/article.dart';
import 'package:everything_app/data/models/budget.dart';
import 'package:everything_app/data/models/weather.dart';
import 'package:everything_app/view/screens/dashboard/city_sheet.dart';
import 'package:everything_app/view/screens/tasks/task_sheet.dart';
import 'package:everything_app/view/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// How many of today's tasks the Dashboard lists before "See All".
const int _kTaskPreviewCount = 4;

/// How many headlines the news section shows.
const int _kNewsCount = 6;

/// [DashboardPage] is the day at a glance (Requirement 3).
///
/// It is the one screen that owns no data. Every figure on it belongs to a module
/// that already owns it — [TasksBloc] has today's work, [FinanceBloc] the month's
/// money, [BudgetBloc] the limit it is measured against — and the Dashboard is
/// where the four are put side by side. That is why it is built after them: a
/// summary of nothing is a mock.
///
/// The two blocs it does bring, [WeatherBloc] and [NewsBloc], are the app's only
/// networked ones. Both are hydrated, so what they last fetched is on screen
/// before the first request is made and stays there when it fails — which is the
/// whole of the offline behaviour Requirement 3.11 asks for (see [_StaleBanner]).
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  /// [_refresh] is the pull gesture: the two things on this screen that can be out
  /// of date, asked again. Tasks and money arrive on a database stream and are
  /// never stale.
  Future<void> _refresh(BuildContext context) async {
    context.read<WeatherBloc>().add(const FetchWeatherEvent());
    context.read<NewsBloc>().add(const FetchNewsEvent());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => _refresh(context),
        child: ListView(
          padding: responsivePadding(context).copyWith(top: 8, bottom: 140),
          children: const [
            _Greeting(),
            Gap(20),
            _DateAndWeather(),
            Gap(10),
            _StaleBanner(),
            _TodayTasks(),
            Gap(16),
            _FinanceSummary(),
            Gap(28),
            _News(),
          ],
        ),
      ),
    );
  }
}

/// [_Greeting] is the serif salutation (Requirement 3.1).
///
/// The name comes from [SettingsBloc], which owns it. A *widget* reading another
/// module's bloc is the point of this screen; what is forbidden is a **bloc**
/// reading another bloc's state (CLAUDE.md §4.4).
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
                // An unnamed greeting is still a greeting: the app works perfectly
                // well for someone who never opened Settings.
                name.isEmpty
                    ? '${Helpers.greeting()}!'
                    : '${Helpers.greeting()}, $name!',
                style: context.texts.headlineSmall,
              ),
            ),
            const Gap(8),
            // The avatar is the way into Settings, and Settings is the only place
            // the name can be set — which is what makes an unnamed greeting
            // self-explanatory rather than a defect.
            IconButton.filledTonal(
              onPressed: () => context.pushNamed(settingsRoute),
              icon: const Icon(Icons.person_outline_rounded),
              tooltip: 'Settings',
            ),
          ],
        );
      },
    );
  }
}

/// [_DateAndWeather] is the date line and the weather pill (Requirements 3.1, 3.2).
class _DateAndWeather extends StatelessWidget {
  const _DateAndWeather();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Date',
                style: context.texts.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const Gap(2),
              Text(
                DateTime.now().dashboardDate,
                style: context.texts.titleLarge,
              ),
            ],
          ),
        ),
        const Gap(12),
        const _WeatherPill(),
      ],
    );
  }
}

/// [_WeatherPill] is the amber pill of the reference UI (Requirement 3.2).
///
/// Three states, no spinner: a temperature, an invitation to say where the user
/// is, and — while the very first fetch is in flight — a dash. A spinner on
/// something this small is a flicker, and it would replace the one thing the user
/// is looking at the pill to read.
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
                  size: 18,
                  color: colors.onPrimary,
                ),
                const Gap(6),
                Text(
                  'Set location',
                  style: context.texts.labelLarge?.copyWith(
                    color: colors.onPrimary,
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
              Icon(
                (weather?.condition ?? WeatherCondition.unknown).icon,
                size: 20,
                color: colors.onPrimary,
              ),
              const Gap(8),
              Text(
                '${weather?.temperature ?? '—'}C',
                style: context.texts.titleMedium?.copyWith(
                  color: colors.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(2),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colors.onPrimary,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.primary,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: child,
        ),
      ),
    );
  }
}

/// [_StaleBanner] is the only thing the Dashboard says about being offline
/// (Requirement 3.11).
///
/// Cached weather and news are otherwise shown without comment — offline is this
/// app's normal condition, not an error, and a banner every time the user is in a
/// lift is noise. It appears once the cache is older than [kStaleCacheThreshold],
/// which is the point at which the figure on the pill stops being an answer and
/// starts being a memory.
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

/// [_TodayTasks] is today's open work (Requirements 3.4, 3.5, 3.6).
class _TodayTasks extends StatelessWidget {
  const _TodayTasks();

  /// [_seeAll] is Requirement 3.6: the Tasks module, filtered to today.
  ///
  /// The filter is dispatched before the tab is switched, so the list is already
  /// narrowed when it comes into view rather than re-filtering under the user.
  void _seeAll(BuildContext context) {
    context.read<TasksBloc>().add(
          const ChangeFilterEvent(filter: TaskFilter.today),
        );
    context.goNamed(tasksRoute);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TasksBloc, TasksState>(
      // Today's preview is derived from the task list, its categories and the
      // load flag. The selected date, active filter and in-module search query
      // the Tasks tab carries do not change it.
      buildWhen: (previous, current) =>
          previous.tasks != current.tasks ||
          previous.categories != current.categories ||
          previous.isLoading != current.isLoading,
      builder: (context, state) {
        final tasks = state.todayTasks;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: "Today's Tasks",
              action: tasks.isEmpty ? null : 'See All',
              onAction: () => _seeAll(context),
            ),
            if (tasks.isEmpty)
              _Empty(
                message: state.isLoading
                    ? 'Loading…'
                    : 'Nothing due today. Tap + to add something.',
              )
            else
              for (final task in tasks.take(_kTaskPreviewCount))
                TaskCard(
                  task: task,
                  category: state.categoryOf(task),
                  // Requirement 3.5: the same two actions the Tasks list itself
                  // offers, because a card that behaves differently on a different
                  // screen is a card the user has to learn twice.
                  onToggle: (isCompleted) => context.read<TasksBloc>().add(
                        ToggleTaskCompletionEvent(
                          task: task,
                          isCompleted: isCompleted,
                        ),
                      ),
                  onTap: () => showTaskSheet(context, task: task),
                ),
          ],
        );
      },
    );
  }
}

/// [_FinanceSummary] is the four cards of Requirement 3.7.
///
/// Every figure is about *this* month, whatever month the Finance tab happens to
/// be scrolled to — hence [FinanceState.totalsFor] rather than the selected-month
/// getters, which would put February's spending on the Dashboard because the user
/// went looking at February. The budget card is assembled the same way:
/// [BudgetStatus] is a pure value, so this month's limit and this month's spending
/// can be put together here without asking [BudgetBloc] to leave the month it is
/// tracking.
class _FinanceSummary extends StatelessWidget {
  const _FinanceSummary();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FinanceBloc, FinanceState>(
      // The four cards are this month's totals, derived from the transactions.
      // The selected month, filters and search query the Finance tab carries do
      // not change them, so they must not rebuild this row.
      buildWhen: (previous, current) =>
          previous.transactions != current.transactions,
      builder: (context, finance) {
        return BlocBuilder<BudgetBloc, BudgetState>(
          // Only the budget-left card reads BudgetBloc, and only its limit — not
          // the spend-and-alert churn FinanceBloc drives through it per write.
          buildWhen: (previous, current) => previous.budgets != current.budgets,
          builder: (context, budgets) {
            final now = DateTime.now();

            final month = finance.totalsFor(now);
            final previous = finance.totalsFor(
              DateTime(now.year, now.month - 1),
            );

            final status = BudgetStatus(
              budget: budgets.budgetFor(month: now.month, year: now.year),
              spentMinor: month.expenseMinor,
            );

            // Requirement 3.8: every card is a way into the Finance module.
            void open() => context.goNamed(financeRoute);

            return SizedBox(
              height: 104,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _SpentCard(
                    spentMinor: month.expenseMinor,
                    previousMinor: previous.expenseMinor,
                    onTap: open,
                  ),
                  const Gap(10),
                  _SummaryCard(
                    label: 'Income',
                    value: Helpers.formatMoney(
                      month.incomeMinor,
                      compact: true,
                    ),
                    onTap: open,
                  ),
                  const Gap(10),
                  _SummaryCard(
                    label: 'Savings',
                    value: Helpers.formatMoney(
                      month.savingsMinor,
                      compact: true,
                    ),
                    // A month that spent more than it earned is the one figure here
                    // the user most needs to notice.
                    isNegative: month.savingsMinor < 0,
                    onTap: open,
                  ),
                  const Gap(10),
                  _SummaryCard(
                    label: 'Budget left',
                    value: status.isSet
                        ? Helpers.formatMoney(
                            status.remainingMinor,
                            compact: true,
                          )
                        : 'Not set',
                    isNegative: status.isSet && status.remainingMinor < 0,
                    onTap: open,
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

/// [_SpentCard] is the reference UI's headline card: what the month has cost, and
/// how that compares with the last one.
class _SpentCard extends StatelessWidget {
  const _SpentCard({
    required this.spentMinor,
    required this.previousMinor,
    required this.onTap,
  });

  final int spentMinor;
  final int previousMinor;
  final VoidCallback onTap;

  /// The change on last month, or null when there is nothing to compare against —
  /// a first month has no trend, and a percentage of zero is not a fact about
  /// anyone's spending.
  double? get _change {
    if (previousMinor <= 0) return null;
    return (spentMinor - previousMinor) / previousMinor * 100;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final change = _change;

    return _Card(
      width: 218,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('You spent', style: context.texts.titleMedium),
              ),
              if (change != null) _ChangeBadge(change: change),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  Helpers.formatMoney(spentMinor, compact: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.headlineSmall,
                ),
              ),
              const Gap(6),
              Text(
                'this month',
                style: context.texts.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// [_ChangeBadge] is the `24% ↑` marker of the reference UI.
class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({required this.change});

  final double change;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isUp = change >= 0;
    final tint = isUp ? colors.error : colors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${change.abs().round()}%',
            style: context.texts.labelSmall?.copyWith(
              color: tint,
              fontWeight: FontWeight.w700,
            ),
          ),
          Icon(
            isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 12,
            color: tint,
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.onTap,
    this.isNegative = false,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool isNegative;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return _Card(
      width: 138,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: context.texts.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.titleLarge?.copyWith(
              color: isNegative ? colors.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.width,
    required this.child,
    required this.onTap,
  });

  final double width;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: width,
          padding: const EdgeInsets.all(14),
          child: child,
        ),
      ),
    );
  }
}

/// [_News] is the headlines and their category tabs (Requirements 3.9, 3.10).
class _News extends StatelessWidget {
  const _News();

  /// [_open] hands the article to the browser (Requirement 3.10).
  ///
  /// Not a webview: that would wrap somebody else's page in this app's chrome and
  /// make the app answerable for it, along with a back button to explain.
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
      builder: (context, state) {
        final articles = state.visibleArticles;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: 'News'),
            const Gap(8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: NewsCategory.values.length,
                separatorBuilder: (_, _) => const Gap(8),
                itemBuilder: (context, index) {
                  final category = NewsCategory.values[index];

                  return _CategoryTab(
                    label: category.label,
                    isSelected: category == state.category,
                    onTap: () => context.read<NewsBloc>().add(
                          SelectNewsCategoryEvent(category: category),
                        ),
                  );
                },
              ),
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

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              isSelected ? colors.surfaceContainerHighest : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? colors.outline : colors.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: context.texts.labelMedium?.copyWith(
            color: isSelected ? colors.onSurface : colors.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
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
    final image = article.imageUrl;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (image != null && image.isNotEmpty)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    image,
                    fit: BoxFit.cover,
                    // A headline whose picture will not load is still a headline:
                    // the card keeps its shape and drops the image rather than
                    // showing a broken one. Offline, this is every card.
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: colors.surfaceContainerHighest,
                      child: Icon(
                        Icons.article_outlined,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    loadingBuilder: (context, child, progress) => progress == null
                        ? child
                        : ColoredBox(color: colors.surfaceContainerHighest),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleMedium,
                    ),
                    const Gap(6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            article.source,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 14,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [_SectionHeader] is the `Today's Tasks — See All ›` line.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = action;

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: context.texts.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        if (label != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: colors.onSurfaceVariant,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: context.texts.labelMedium),
                const Icon(Icons.chevron_right_rounded, size: 16),
              ],
            ),
          ),
      ],
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
