import 'dart:async';

import 'package:everything_app/bloc/tasks/tasks_bloc.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/view/screens/tasks/task_sheet.dart';
import 'package:everything_app/view/widgets/app_choice_chip.dart';
import 'package:everything_app/view/widgets/calendar_strip.dart';
import 'package:everything_app/view/widgets/module_app_bar.dart';
import 'package:everything_app/view/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// [TasksPage] is the Tasks module (Requirement 4).
///
/// The default view, "By date", is one continuous list of every open task split
/// into date sections. The calendar strip and the list are two-way bound: tapping
/// a day scrolls to that section, and scrolling moves the strip's highlight.
///
/// The focused date is a [ValueNotifier] rather than bloc state because scrolling
/// changes it many times a second; routing that through [TasksBloc] would rebuild
/// the list on every frame of a fling. The bloc is told only where the user
/// settled, which is the date a new task pre-fills as its due date.
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final _search = TextEditingController();
  final _scrollController = ItemScrollController();
  final _positionsListener = ItemPositionsListener.create();

  late final ValueNotifier<DateTime> _focusedDate;

  /// Debounce the search (one filter pass per pause, not per keystroke) and the
  /// scroll (one bloc event per gesture, not per frame).
  Timer? _searchDebounce;
  Timer? _scrollDebounce;

  /// The flat header-and-task rows the list renders. Held as a field so the
  /// scroll listener can map a visible index back to its date section.
  List<_ListItem> _items = const [];

  bool _isSearching = false;

  /// The day the user tapped in the calendar, held until they scroll the list
  /// themselves.
  ///
  /// A tap scrolls the list, and the list reports a new position on every frame of
  /// that scroll. Read back through [_onScrolled], each one looks like the user
  /// having scrolled there: the highlight is dragged back through every section on
  /// the way, and settles on whatever section ends up at the top of the viewport —
  /// which, for the last few days in the list, is not the day that was tapped but
  /// today. So while a day is pinned the list does not get to move the highlight;
  /// the next drag unpins it and two-way binding resumes.
  DateTime? _pinnedDate;

  @override
  void initState() {
    super.initState();

    _focusedDate = ValueNotifier(DateTime.now().dateOnly);
    _positionsListener.itemPositions.addListener(_onScrolled);
  }

  @override
  void dispose() {
    _positionsListener.itemPositions.removeListener(_onScrolled);
    _searchDebounce?.cancel();
    _scrollDebounce?.cancel();
    _focusedDate.dispose();
    _search.dispose();
    super.dispose();
  }

  /// [_onScrolled] moves the calendar's highlight to the section now at the top
  /// of the viewport.
  void _onScrolled() {
    if (_pinnedDate != null) return;

    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty || _items.isEmpty) return;

    // The lowest index still visible below the top edge, ignoring rows that have
    // scrolled past it.
    var topIndex = _items.length;
    for (final position in positions) {
      if (position.itemTrailingEdge > 0 && position.index < topIndex) {
        topIndex = position.index;
      }
    }
    if (topIndex >= _items.length) return;

    // Walk back to the section this row sits under: only headers carry a date.
    for (var i = topIndex; i >= 0; i--) {
      final date = _items[i].date;
      if (date == null) continue;
      if (!date.isSameDayAs(_focusedDate.value)) _focusedDate.value = date;
      return;
    }
  }

  /// [_onDaySelected] scrolls to the tapped day's section, or to the next section
  /// on or after it when that day holds no tasks.
  void _onDaySelected(DateTime date) {
    _focusedDate.value = date.dateOnly;
    _pinnedDate = date.dateOnly;
    _rememberDate(date.dateOnly);

    if (!_scrollController.isAttached || _items.isEmpty) return;

    final index = _indexOfSectionOnOrAfter(date.dateOnly);
    if (index == null) return;

    _scrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// [_onUserScroll] hands the highlight back to the list: from here on it follows
  /// the section at the top of the viewport again.
  void _onUserScroll() {
    if (_pinnedDate == null) return;
    _pinnedDate = null;
    _onScrolled();
  }

  int? _indexOfSectionOnOrAfter(DateTime date) {
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item is! _HeaderItem) continue;

      final itemDate = item.date;
      if (itemDate == null) continue;
      if (!itemDate.isBefore(date)) return i;
    }
    return null;
  }

  /// [_rememberDate] reports the settled date to [TasksBloc], which a new task
  /// uses as its default due date.
  void _rememberDate(DateTime date) {
    _scrollDebounce?.cancel();
    _scrollDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      context.read<TasksBloc>().add(SelectDateEvent(date: date));
    });
  }

  void _onQueryChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(kSearchDebounce, () {
      if (!mounted) return;
      context.read<TasksBloc>().add(SearchTasksEvent(query: query));
    });
  }

  void _toggleSearch() {
    setState(() => _isSearching = !_isSearching);
    if (!_isSearching) {
      _search.clear();
      context.read<TasksBloc>().add(const SearchTasksEvent(query: ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: BlocConsumer<TasksBloc, TasksState>(
        listenWhen: (previous, current) => previous.error != current.error,
        listener: (context, state) {
          if (state.error.isNotEmpty) {
            context.showSnack(state.error, isError: true);
          }
        },
        // selectedDate is excluded: the strip is driven by [_focusedDate], so
        // scrolling the list rebuilds nothing here.
        buildWhen: (previous, current) =>
            previous.tasks != current.tasks ||
            previous.categories != current.categories ||
            previous.filter != current.filter ||
            previous.categoryId != current.categoryId ||
            previous.priority != current.priority ||
            previous.query != current.query ||
            previous.isLoading != current.isLoading,
        builder: (context, state) {
          _items = _buildItems(state);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: responsivePadding(context),
                child: _Header(
                  isSearching: _isSearching,
                  controller: _search,
                  onQueryChanged: _onQueryChanged,
                  onToggleSearch: _toggleSearch,
                ),
              ),
              Padding(
                padding: responsivePadding(context),
                child: ValueListenableBuilder<DateTime>(
                  valueListenable: _focusedDate,
                  builder: (context, focusedDate, _) => CalendarStrip(
                    focusedDate: focusedDate,
                    markedDates: state.datesWithTasks,
                    onSelect: _onDaySelected,
                  ),
                ),
              ),
              _FilterRow(active: state.filter),
              Expanded(
                child: _TaskList(
                  state: state,
                  items: _items,
                  scrollController: _scrollController,
                  positionsListener: _positionsListener,
                  onUserScroll: _onUserScroll,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// [_buildItems] flattens the state into the rows the list renders: a header per
  /// date section for "By date", a single header for every other filter.
  List<_ListItem> _buildItems(TasksState state) {
    if (state.filter != TaskFilter.date) {
      return [
        _HeaderItem(label: state.filter.label),
        for (final task in state.visibleTasks) _TaskItem(task: task),
      ];
    }

    return [
      for (final group in state.dateGroups) ...[
        _HeaderItem(
          label: group.label,
          date: group.date,
          isOverdue: group.isOverdue,
          count: group.tasks.length,
        ),
        for (final task in group.tasks) _TaskItem(task: task, date: group.date),
      ],
    ];
  }
}

/// [_ListItem] is one row of the list: a date header, or a task.
sealed class _ListItem {
  const _ListItem({this.date});

  /// The date section this row belongs to, used to sync the calendar strip. Null
  /// for Overdue and No date, which span no single day.
  final DateTime? date;
}

class _HeaderItem extends _ListItem {
  const _HeaderItem({
    required this.label,
    super.date,
    this.isOverdue = false,
    this.count = 0,
  });

  final String label;
  final bool isOverdue;
  final int count;
}

class _TaskItem extends _ListItem {
  const _TaskItem({required this.task, super.date});

  final Task task;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isSearching,
    required this.controller,
    required this.onQueryChanged,
    required this.onToggleSearch,
  });

  final bool isSearching;
  final TextEditingController controller;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context) {
    // Held at the header's height, so opening search does not lift the calendar
    // strip and the list under it.
    if (isSearching) {
      return SizedBox(
        height: ModuleAppBar.height,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                onChanged: onQueryChanged,
                decoration: const InputDecoration(
                  hintText: 'Search title, tags, notes…',
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              onPressed: onToggleSearch,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close search',
            ),
          ],
        ),
      );
    }

    // FilledButton.icon(
    //   onPressed: () => showTaskSheet(context),
    //   icon: const Icon(Icons.add_rounded, size: 18),
    //   label: const Text('Add task'),
    //   style: FilledButton.styleFrom(
    //     padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    //   ),
    // ),
    return ModuleAppBar(
      title: 'Tasks',
      actions: [
        IconButton(
          onPressed: onToggleSearch,
          icon: const Icon(Icons.search_rounded),
          color: context.colors.onSurfaceVariant,
          tooltip: 'Search tasks',
        ),
      ],
    );
  }
}

/// [_FilterRow] is the horizontally scrolling filter chips (Requirement 4.9).
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.active});

  final TaskFilter active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: responsivePadding(context),
        itemCount: TaskFilter.values.length,
        separatorBuilder: (_, _) => const Gap(8),
        itemBuilder: (context, index) {
          final filter = TaskFilter.values[index];

          return Center(
            child: AppChoiceChip(
              label: filter.label,
              isSelected: filter == active,
              onSelected: (_) => context
                  .read<TasksBloc>()
                  .add(ChangeFilterEvent(filter: filter)),
            ),
          );
        },
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.state,
    required this.items,
    required this.scrollController,
    required this.positionsListener,
    required this.onUserScroll,
  });

  final TasksState state;
  final List<_ListItem> items;
  final ItemScrollController scrollController;
  final ItemPositionsListener positionsListener;

  /// Fires when the user drags the list, as opposed to the list being scrolled by
  /// a tap on the calendar.
  final VoidCallback onUserScroll;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // A header with no rows under it means there is nothing to show.
    if (items.length <= 1) return _EmptyState(state: state);

    return NotificationListener<ScrollStartNotification>(
      // dragDetails is null for a programmatic scroll, which is what separates
      // the user's own scrolling from the one a calendar tap starts.
      onNotification: (notification) {
        if (notification.dragDetails != null) onUserScroll();
        return false;
      },
      child: ScrollablePositionedList.builder(
        itemScrollController: scrollController,
        itemPositionsListener: positionsListener,
        itemCount: items.length,
        // Bottom padding clears the bottom nav and the floating AI dock.
        padding: responsivePadding(context).copyWith(top: 0, bottom: 140),
        itemBuilder: (context, index) {
          final item = items[index];

          return switch (item) {
            _HeaderItem() => _SectionHeader(item: item),
            _TaskItem() => _TaskRow(task: item.task, state: state),
          };
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.item});

  final _HeaderItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = item.isOverdue ? colors.error : colors.onSurface;

    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Row(
        children: [
          Text(
            item.label,
            style: context.texts.headlineMedium?.copyWith(color: accent),
          ),
          const Gap(8),
          if (item.count > 0)
            Text(
              '${item.count}',
              style: context.texts.labelSmall?.copyWith(
                color: item.isOverdue ? colors.error : colors.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.state});

  final Task task;
  final TasksState state;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: ColoredBox(
        color: context.colors.error,
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.delete_outline_rounded, color: Colors.white),
          ),
        ),
      ),
      onDismissed: (_) =>
          context.read<TasksBloc>().add(DeleteTaskEvent(id: task.id)),
      child: TaskCard(
        task: task,
        category: state.categoryOf(task),
        onToggle: (isCompleted) => context.read<TasksBloc>().add(
              ToggleTaskCompletionEvent(task: task, isCompleted: isCompleted),
            ),
        onTap: () => showTaskSheet(context, task: task),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.state});

  final TasksState state;

  @override
  Widget build(BuildContext context) {
    // "Nothing matched" and "no tasks at all" need different copy: only the second
    // should offer to create one.
    final isNarrowed = state.isFiltered || state.filter != TaskFilter.date;

    return Center(
      child: Padding(
        padding: responsivePadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isNarrowed ? Icons.filter_alt_off_rounded : Icons.task_alt_rounded,
              size: 40,
              color: context.colors.onSurfaceVariant,
            ),
            const Gap(12),
            Text(
              isNarrowed ? 'Nothing matches' : 'No tasks yet',
              style: context.texts.titleMedium,
            ),
            const Gap(6),
            Text(
              isNarrowed
                  ? 'Try a different filter or search.'
                  : 'Add your first one.',
              style: context.texts.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (!isNarrowed) ...[
              const Gap(16),
              FilledButton.icon(
                onPressed: () => showTaskSheet(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add task'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
