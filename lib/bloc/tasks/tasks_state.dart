part of 'tasks_bloc.dart';

/// [TaskGroup] is one dated section of the "By date" view.
///
/// [date] is null for the two sections that are not a single day: Overdue (which
/// spans every past day) and No date.
class TaskGroup extends Equatable {
  const TaskGroup({
    required this.label,
    required this.tasks,
    this.date,
    this.isOverdue = false,
  });

  final String label;
  final List<Task> tasks;
  final DateTime? date;
  final bool isOverdue;

  @override
  List<Object?> get props => [label, tasks, date, isOverdue];
}

/// [TaskFilter] is the active view over the task list (Requirement 4.9).
///
/// [date] is the default: every uncompleted task, grouped into date sections.
/// Category and priority are not members: they narrow any filter rather than
/// replacing it, and are separate fields on the state.
enum TaskFilter {
  date,
  today,
  tomorrow,
  upcoming,
  completed,
  overdue;

  String get label => switch (this) {
        TaskFilter.date => 'By date',
        TaskFilter.today => 'Today',
        TaskFilter.tomorrow => 'Tomorrow',
        TaskFilter.upcoming => 'Upcoming',
        TaskFilter.completed => 'Completed',
        TaskFilter.overdue => 'Overdue',
      };

  static TaskFilter fromName(String? name) => TaskFilter.values.firstWhere(
        (value) => value.name == name,
        orElse: () => TaskFilter.date,
      );
}

/// [TasksState] holds everything the Tasks module renders.
///
/// [tasks] is the complete list from the database. [visibleTasks] and
/// [dateGroups] derive from it, so changing a filter is a recomputation rather
/// than a database round trip.
class TasksState extends Equatable {
  const TasksState({
    required this.selectedDate,
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.tasks = const <Task>[],
    this.categories = const <Category>[],
    this.filter = TaskFilter.date,
    this.categoryId,
    this.priority,
    this.query = '',
    this.notificationSettings,
  });

  /// [TasksState.initial] starts on today, by date.
  factory TasksState.initial() => TasksState(selectedDate: DateTime.now().dateOnly);

  final bool isLoading;
  final String error;
  final String message;
  final List<Task> tasks;
  final List<Category> categories;
  final DateTime selectedDate;
  final TaskFilter filter;
  final String? categoryId;
  final TaskPriority? priority;
  final String query;

  /// The notification configuration, as last reported by [SettingsBloc]
  /// (Requirement 5).
  ///
  /// Null until Settings reports in, and that null is load-bearing: it is what
  /// keeps the bloc from scheduling anything against the defaults before the
  /// user's own choices are known. It is not persisted here — [SettingsBloc] owns
  /// it and hydrates it — and it is not rendered.
  final NotificationSettings? notificationSettings;

  /// [visibleTasks] is [tasks] under the active filter, the category and priority
  /// narrowing and the search query, sorted by urgency.
  ///
  /// The "By date" filter renders from [dateGroups] instead.
  List<Task> get visibleTasks {
    final matched = tasks
        .where((task) => _matchesFilter(task) && _matchesNarrowing(task))
        .toList();

    matched.sort(_byUrgency);

    return matched;
  }

  /// [dateGroups] is the "By date" view: every uncompleted task, split into date
  /// sections — Overdue, then each day in ascending order, then No date.
  ///
  /// Undated tasks get a section rather than being dropped: no other view in the
  /// app can show them, so omitting them would make a saved task unreachable.
  List<TaskGroup> get dateGroups {
    final overdue = <Task>[];
    final undated = <Task>[];
    final byDay = SplayTreeMap<DateTime, List<Task>>();

    for (final task in tasks) {
      if (task.status != TaskStatus.pending) continue;
      if (!_matchesNarrowing(task)) continue;

      final due = task.dueDate;

      if (due == null) {
        undated.add(task);
        continue;
      }

      // Overdue here is per-day, not per-minute as in [Task.isOverdue]: a task
      // due at 09:00 stays under Today for the rest of the day.
      if (due.dateOnly.isBefore(DateTime.now().dateOnly)) {
        overdue.add(task);
        continue;
      }

      byDay.putIfAbsent(due.dateOnly, () => <Task>[]).add(task);
    }

    return [
      if (overdue.isNotEmpty)
        TaskGroup(
          label: 'Overdue',
          isOverdue: true,
          tasks: overdue..sort(_byUrgency),
        ),
      for (final entry in byDay.entries)
        TaskGroup(
          label: entry.key.relativeLabel,
          date: entry.key,
          tasks: entry.value..sort(_byUrgency),
        ),
      if (undated.isNotEmpty)
        TaskGroup(label: 'No date', tasks: undated..sort(_byUrgency)),
    ];
  }

  /// [todayTasks] is what the Dashboard lists (Requirement 3.4): today's open
  /// work, sorted by urgency.
  ///
  /// Overdue tasks are in it. They are not "today's tasks" by their due date, but
  /// they are today's work by any other reading — and a dashboard that hides the
  /// thing that was already late is the one screen in the app that must not.
  List<Task> get todayTasks {
    final today = DateTime.now().dateOnly;

    final matched = [
      for (final task in tasks)
        if (task.status == TaskStatus.pending && task.dueDate != null)
          if (!task.dueDate!.dateOnly.isAfter(today)) task,
    ];

    return matched..sort(_byUrgency);
  }

  /// [datesWithTasks] is the set of days the calendar strip marks with a dot.
  Set<DateTime> get datesWithTasks => {
        for (final task in tasks)
          if (task.status == TaskStatus.pending && task.dueDate != null)
            task.dueDate!.dateOnly,
      };

  /// [_byUrgency] sorts open tasks first, then highest priority, then earliest
  /// due date, then newest.
  static int _byUrgency(Task a, Task b) {
    if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;

    // TaskPriority is declared low→critical, so the index comparison is inverted.
    final byPriority = b.priority.index.compareTo(a.priority.index);
    if (byPriority != 0) return byPriority;

    final aDue = a.dueDate;
    final bDue = b.dueDate;
    if (aDue == null && bDue == null) return b.createdAt.compareTo(a.createdAt);
    if (aDue == null) return 1; // undated tasks sink
    if (bDue == null) return -1;
    return aDue.compareTo(bDue);
  }

  bool _matchesNarrowing(Task task) {
    if (categoryId != null && task.categoryId != categoryId) return false;
    if (priority != null && task.priority != priority) return false;
    if (query.isNotBlank && !_matchesQuery(task)) return false;
    return true;
  }

  bool _matchesFilter(Task task) {
    final due = task.dueDate;

    return switch (filter) {
      // Rendered from [dateGroups]; every open task belongs to it, dated or not.
      TaskFilter.date => task.status == TaskStatus.pending,
      TaskFilter.today =>
        due != null && due.isToday && task.status == TaskStatus.pending,
      TaskFilter.tomorrow =>
        due != null && due.isTomorrow && task.status == TaskStatus.pending,
      // Starts from tomorrow; today's remaining work is the Today filter's job.
      TaskFilter.upcoming => due != null &&
          task.status == TaskStatus.pending &&
          due.dateOnly.isAfter(DateTime.now().dateOnly),
      TaskFilter.completed => task.status == TaskStatus.completed,
      TaskFilter.overdue => task.isOverdue,
    };
  }

  /// [_matchesQuery] searches title, tags, notes and the category name. The task
  /// holds only a category id, so the name can be resolved only here.
  bool _matchesQuery(Task task) {
    if (task.matches(query)) return true;

    final category = categoryOf(task);
    return category != null && category.name.containsIgnoreCase(query);
  }

  /// [categoryOf] resolves a task's category, or null when it has none.
  Category? categoryOf(Task task) {
    if (task.categoryId == null) return null;
    for (final category in categories) {
      if (category.id == task.categoryId) return category;
    }
    return null;
  }

  /// [isFiltered] is true when a query, category or priority is narrowing the
  /// list. The empty state uses it to tell "no tasks yet" from "nothing matched".
  bool get isFiltered =>
      query.isNotBlank || categoryId != null || priority != null;

  int get pendingCount =>
      tasks.where((task) => task.status == TaskStatus.pending).length;

  TasksState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    List<Task>? tasks,
    List<Category>? categories,
    DateTime? selectedDate,
    TaskFilter? filter,
    String? categoryId,
    bool clearCategoryId = false,
    TaskPriority? priority,
    bool clearPriority = false,
    String? query,
    NotificationSettings? notificationSettings,
  }) =>
      TasksState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        tasks: tasks ?? this.tasks,
        categories: categories ?? this.categories,
        selectedDate: selectedDate ?? this.selectedDate,
        filter: filter ?? this.filter,
        categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
        priority: clearPriority ? null : (priority ?? this.priority),
        query: query ?? this.query,
        notificationSettings:
            notificationSettings ?? this.notificationSettings,
      );

  /// [fromJson] restores only the filter choices. Tasks come from the database
  /// stream, and the selected date always resets to today.
  factory TasksState.fromJson(Map<String, dynamic> json) => TasksState(
        selectedDate: DateTime.now().dateOnly,
        filter: TaskFilter.fromName(json['HydratedFilter']?.toString()),
        categoryId: json['HydratedCategoryId']?.toString(),
        priority: json['HydratedPriority'] == null
            ? null
            : TaskPriority.fromName(json['HydratedPriority'].toString()),
      );

  Map<String, dynamic> toJson() => {
        'HydratedFilter': filter.name,
        'HydratedCategoryId': categoryId,
        'HydratedPriority': priority?.name,
      };

  @override
  List<Object?> get props => [
        isLoading,
        error,
        message,
        tasks,
        categories,
        selectedDate,
        filter,
        categoryId,
        priority,
        query,
        notificationSettings,
      ];
}
