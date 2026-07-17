import 'package:everything_app/bloc/projects/projects_bloc.dart';
import 'package:everything_app/bloc/settings/settings_bloc.dart';
import 'package:everything_app/bloc/task_form/task_form_bloc.dart';
import 'package:everything_app/bloc/tasks/tasks_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/entity/quick_task_params.dart';
import 'package:everything_app/data/models/category.dart';
import 'package:everything_app/data/models/project.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/view/widgets/option_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

/// [showTaskSheet] opens the quick-add sheet (Requirement 4.4).
///
/// [task] is null when creating and the task itself when editing.
///
/// The root navigator is used so the sheet covers the bottom navigation and the
/// AI dock rather than being clipped into the shell's body.
///
/// [projectId] pre-files a new task under a project, passed by the project
/// screen's "Add".
Future<void> showTaskSheet(
  BuildContext context, {
  Task? task,
  String? projectId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    // Capped below full height so the list stays visible behind the sheet.
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    builder: (_) => TaskSheet(task: task, projectId: projectId),
  );
}

/// [TaskSheet] creates or edits a task in one line.
///
/// Fields are written inline — `#work`, `@errands`, `p1`, `tomorrow 5pm` (see
/// [QuickTaskParams]) — or set from the pill row. Notes, subtasks and delete sit
/// behind "More".
///
/// The inline shorthand is parsed only when creating: re-parsing an edit would
/// eat words out of a title the user already wrote (`Call mum monday`).
class TaskSheet extends StatefulWidget {
  const TaskSheet({this.task, this.projectId, super.key});

  final Task? task;

  /// The project a new task is pre-filed under, or null for an unfiled task.
  final String? projectId;

  @override
  State<TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<TaskSheet> {
  static const _uuid = Uuid();

  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _subtask = TextEditingController();
  final _titleFocus = FocusNode();

  /// Read once, in [initState]: neither list changes while the sheet is open, and
  /// watching [TasksBloc] would rebuild the sheet on every keystroke elsewhere.
  late final List<Category> _categories;
  late final List<String> _knownTags;

  /// The projects a task can be filed under, read once like the categories.
  late final List<Project> _projects;

  /// The chosen project. Not parsed from the title, so it needs no `…Set` flag.
  String? _projectId;

  /// The due date a new task falls back to: the day the calendar is focused on.
  late final DateTime _defaultDue;

  /// The last parse of the title field. Empty in edit mode, which does not parse.
  QuickTaskParams _parsed = QuickTaskParams();

  /// A value picked from the pills. It wins over whatever the text says, and its
  /// `…Set` flag is what separates "cleared" from "never touched" — both of which
  /// are a null field.
  DateTime? _pickedDue;
  bool _isDueSet = false;
  TaskPriority? _pickedPriority;
  String? _pickedCategoryId;
  bool _isCategorySet = false;
  RecurrenceRule? _pickedRecurrence;
  bool _isRecurrenceSet = false;

  /// How long before the due date to fire the reminder. Null means no reminder.
  /// Stored on the task as an absolute moment but *chosen* as an offset, so it
  /// survives the due date being moved afterwards.
  Duration? _pickedReminderOffset;
  bool _isReminderSet = false;

  List<SubTask> _subtasks = [];
  List<String> _ownTags = [];

  /// Tags dropped from the pills. A tag can come from the text, which the chip's
  /// delete button cannot rewrite, so removal is recorded rather than applied.
  final Set<String> _droppedTags = {};

  bool _isMoreOpen = false;

  Task? get _original => widget.task;

  bool get _isEditing => _original != null;

  DateTime? get _dueDate =>
      _isDueSet ? _pickedDue : (_parsed.dueDate ?? _defaultDue);

  TaskPriority get _priority =>
      _pickedPriority ?? _parsed.priority ?? TaskPriority.medium;

  String? get _categoryId =>
      _isCategorySet ? _pickedCategoryId : _parsed.categoryId;

  RecurrenceRule? get _recurrence =>
      _isRecurrenceSet ? _pickedRecurrence : _parsed.recurrence;

  Duration? get _reminderOffset =>
      _isReminderSet ? _pickedReminderOffset : _parsed.reminderOffset;

  List<String> get _tags => [
    for (final tag in {..._ownTags, ..._parsed.tags})
      if (!_droppedTags.contains(tag)) tag,
  ];

  /// [_reminders] is the reminder as the task stores it: an absolute moment,
  /// [_reminderOffset] before the due date. No due date means no reminder.
  ///
  /// An existing reminder's id is reused so re-saving an unmoved reminder does
  /// not cancel and re-arm the notification the OS already holds.
  List<Reminder> get _reminders {
    final dueDate = _dueDate;
    final offset = _reminderOffset;
    if (dueDate == null || offset == null) return const [];

    final existing = _original?.reminders;

    return [
      Reminder(
        id: existing == null || existing.isEmpty
            ? _uuid.v4()
            : existing.first.id,
        at: dueDate.subtract(offset),
      ),
    ];
  }

  /// [_titleText] is what the task will be called: the field minus every token the
  /// parser claimed.
  String get _titleText => _isEditing ? _title.text.trim() : _parsed.title;

  @override
  void initState() {
    super.initState();

    final tasks = context.read<TasksBloc>().state;

    _categories = tasks.categories;
    _knownTags = {for (final task in tasks.tasks) ...task.tags}.toList()
      ..sort();
    _projects = context.read<ProjectsBloc>().state.projects;

    final existing = _original;
    if (existing == null) {
      _projectId = widget.projectId;
      final date = tasks.selectedDate;
      _defaultDue = DateTime(date.year, date.month, date.day, 9);
      return;
    }

    // Editing: every field is already decided, so all of them count as picked.
    _projectId = existing.projectId;
    _defaultDue = existing.dueDate ?? DateTime.now();
    _title.text = existing.title;
    _notes.text = existing.notes ?? '';
    _pickedDue = existing.dueDate;
    _isDueSet = true;
    _pickedPriority = existing.priority;
    _pickedCategoryId = existing.categoryId;
    _isCategorySet = true;
    _pickedRecurrence = existing.recurrence;
    _isRecurrenceSet = true;
    _subtasks = List.of(existing.subtasks);
    _ownTags = List.of(existing.tags);
    _isMoreOpen = existing.notes != null || existing.subtasks.isNotEmpty;

    // The stored reminder is absolute; the sheet edits it as an offset, so it is
    // read back as the gap between the two.
    final reminder = existing.reminders.isEmpty
        ? null
        : existing.reminders.first;
    final dueDate = existing.dueDate;

    _isReminderSet = true;
    if (reminder != null && dueDate != null) {
      _pickedReminderOffset = dueDate.difference(reminder.at);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _subtask.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _onTitleChanged(String text) {
    if (_isEditing) {
      setState(() {});
      return;
    }

    final hadReminder = _reminderOffset != null;

    setState(() {
      _parsed = QuickTaskParams.parse(text, categories: _categories);
    });

    // A reminder can now arrive by typing rather than only from the pill, so the
    // permission is requested here too — at the moment the user asked to be
    // notified, which is the same rule [_onReminderSelected] follows.
    if (!hadReminder && _reminderOffset != null) _ensureNotificationsAllowed();
  }

  /// [_onCaretMoved] re-reads which token the caret is in after a tap.
  ///
  /// Editing completes no tokens, so the rebuild is skipped there.
  void _onCaretMoved() {
    if (_isEditing) return;
    setState(() {});
  }

  /// [_activeToken] is the `#`- or `@`-token the caret is inside, which is what
  /// the suggestion row completes. Null when the caret is anywhere else.
  _Token? get _activeToken {
    if (_isEditing) return null;

    final selection = _title.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;

    final text = _title.text;
    final caret = selection.baseOffset;
    if (caret <= 0 || caret > text.length) return null;

    for (var i = caret - 1; i >= 0; i--) {
      final character = text[i];
      if (character == ' ' || character == '\n') return null;
      if (character != '#' && character != '@') continue;

      // A symbol mid-word (`c#`, an email) is not a token.
      if (i > 0 && text[i - 1] != ' ') return null;

      return _Token(
        symbol: character,
        query: text.substring(i + 1, caret),
        start: i,
      );
    }

    return null;
  }

  /// [_suggestionsFor] is the categories or tags matching what has been typed so
  /// far. An empty query lists everything.
  List<String> _suggestionsFor(_Token token) {
    final pool = token.symbol == '#'
        ? [for (final category in _categories) category.name]
        : _knownTags;

    final query = token.query.toLowerCase();

    return [
      for (final value in pool)
        if (query.isEmpty || value.toLowerCase().contains(query)) value,
    ].take(6).toList();
  }

  void _completeToken(_Token token, String value) {
    // The token cannot hold a space, so a multi-word category is completed to its
    // first word — the parser resolves the rest by prefix.
    final replacement = '${token.symbol}${value.split(' ').first} ';
    final end = token.start + 1 + token.query.length;
    final text = _title.text.replaceRange(token.start, end, replacement);

    _title.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: token.start + replacement.length,
      ),
    );

    _onTitleChanged(text);
    _titleFocus.requestFocus();
  }

  Future<void> _onDueSelected(_DueChoice choice) async {
    final today = DateTime.now().dateOnly;
    final time = _dueDate;

    // A day chosen from the menu keeps whatever time is already on the task.
    DateTime at(DateTime date) => DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 9,
      time?.minute ?? 0,
    );

    switch (choice) {
      case _DueChoice.today:
        _setDue(at(today));
      case _DueChoice.tomorrow:
        _setDue(at(today.add(const Duration(days: 1))));
      case _DueChoice.nextWeek:
        _setDue(at(today.add(const Duration(days: 7))));
      case _DueChoice.none:
        _setDue(null);
      case _DueChoice.time:
        await _pickDueTime();
      case _DueChoice.pick:
        await _pickDueDate();
    }
  }

  /// [_pickDueTime] edits the hour without touching the day.
  ///
  /// A task with no day yet gets today: the user has just named a time, and a
  /// time on no particular day is not a due date.
  Future<void> _pickDueTime() async {
    final current = _dueDate ?? DateTime.now().dateOnly;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;

    _setDue(
      DateTime(
        current.year,
        current.month,
        current.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final current = _dueDate;

    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? now),
    );
    if (!mounted) return;

    _setDue(
      DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? current?.hour ?? 9,
        time?.minute ?? current?.minute ?? 0,
      ),
    );
  }

  void _setDue(DateTime? date) {
    setState(() {
      _pickedDue = date;
      _isDueSet = true;
    });
    _titleFocus.requestFocus();
  }

  /// [_onReminderSelected] sets when to be reminded, relative to the due date.
  ///
  /// A reminder needs a due date to be relative to, so one is picked first rather
  /// than refusing.
  ///
  /// This is also where the OS notification permission is requested — at the
  /// moment the user has asked to be notified, rather than on first launch.
  /// Without the grant the reminder is saved, scheduled, and never delivered.
  Future<void> _onReminderSelected(_ReminderChoice choice) async {
    if (choice.offset != null && _dueDate == null) {
      await _pickDueDate();
      if (!mounted || _dueDate == null) return;
    }

    setState(() {
      _pickedReminderOffset = choice.offset;
      _isReminderSet = true;
    });

    if (choice.offset != null) _ensureNotificationsAllowed();

    _titleFocus.requestFocus();
  }

  /// [_ensureNotificationsAllowed] asks the OS for permission if it has not been
  /// granted yet. Dispatched, not awaited: the sheet must not block on a system
  /// dialog, and the schedule is rebuilt from the database once the answer lands.
  void _ensureNotificationsAllowed() {
    final settings = context.read<SettingsBloc>();
    if (settings.state.isPermissionGranted) return;

    settings.add(const RequestNotificationPermissionEvent());
  }

  void _addSubtask() {
    final title = _subtask.text.trim();
    if (title.isEmpty) return;

    setState(() {
      _subtasks = [..._subtasks, SubTask(id: _uuid.v4(), title: title)];
      _subtask.clear();
    });
  }

  void _submit() {
    final title = _titleText;
    if (title.isEmpty) {
      context.showSnack('Give the task a title.', isError: true);
      return;
    }

    final notes = _notes.text.trim();

    final task = _parsed
        .copyWith(title: title)
        .toTask(
          original: _original,
          dueDate: _dueDate,
          priority: _priority,
          categoryId: _categoryId,
          projectId: _projectId,
          recurrence: _recurrence,
          tags: _tags,
          subtasks: _subtasks,
          reminders: _reminders,
          notes: notes.isEmpty ? null : notes,
        );

    context.read<TaskFormBloc>().add(
      SubmitTaskEvent(task: task, isEditing: _isEditing),
    );
  }

  void _delete() {
    context.read<TasksBloc>().add(DeleteTaskEvent(id: _original!.id));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final token = _activeToken;
    final suggestions = token == null
        ? const <String>[]
        : _suggestionsFor(token);

    return BlocConsumer<TaskFormBloc, TaskFormState>(
      listener: (context, state) {
        if (state is TaskFormSuccess) {
          // The bloc is app-scoped: a lingering Success state would close the
          // next sheet the moment it opened.
          context.read<TaskFormBloc>().add(const ResetTaskFormEvent());
          Navigator.of(context).pop();
        } else if (state is TaskFormFailure) {
          context.showSnack(state.message, isError: true);
        }
      },
      builder: (context, state) {
        return _KeyboardInset(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Only the unbounded parts scroll (title, tags, More); the pills
                // and send button stay put so opening More cannot push Save
                // under the keyboard.
                Flexible(
                  child: SingleChildScrollView(
                    // Clamping, not bouncing: an overscroll bounce inside a
                    // drag-to-dismiss sheet reads as the sheet coming away.
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _title,
                          focusNode: _titleFocus,
                          autofocus: true,
                          maxLines: null,
                          textInputAction: TextInputAction.done,
                          textCapitalization: TextCapitalization.sentences,
                          style: context.texts.titleMedium,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                            hintText: _isEditing
                                ? 'Task name'
                                : 'Pay rent tomorrow 5pm #finance p1',
                          ),
                          onChanged: _onTitleChanged,
                          onSubmitted: (_) => _submit(),
                          // Moving the caret changes which token is completed.
                          onTap: _onCaretMoved,
                        ),
                        if (_tags.isNotEmpty) ...[
                          const Gap(10),
                          _TagRow(
                            tags: _tags,
                            onRemove: (tag) =>
                                setState(() => _droppedTags.add(tag)),
                          ),
                        ],
                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _isMoreOpen
                              ? _MoreSection(
                                  notes: _notes,
                                  subtask: _subtask,
                                  subtasks: _subtasks,
                                  canDelete: _isEditing,
                                  onAddSubtask: _addSubtask,
                                  onToggleSubtask: (index, isDone) =>
                                      setState(() {
                                        _subtasks = [
                                          for (
                                            var i = 0;
                                            i < _subtasks.length;
                                            i++
                                          )
                                            i == index
                                                ? _subtasks[i].copyWith(
                                                    isDone: isDone,
                                                  )
                                                : _subtasks[i],
                                        ];
                                      }),
                                  onRemoveSubtask: (index) => setState(() {
                                    _subtasks = [..._subtasks]..removeAt(index);
                                  }),
                                  onDelete: _delete,
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ],
                    ),
                  ),
                ),
                if (suggestions.isNotEmpty) ...[
                  const Gap(10),
                  _SuggestionRow(
                    suggestions: suggestions,
                    onSelect: (value) => _completeToken(token!, value),
                  ),
                ],
                const Gap(16),
                Row(
                  // The pills wrap onto several lines; Save stays on the last of
                  // them rather than floating in the middle of the block.
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _OptionsRow(
                        dueDate: _dueDate,
                        priority: _priority,
                        category: _categoryOf(_categoryId),
                        categories: _categories,
                        project: _projectOf(_projectId),
                        projects: _projects,
                        recurrence: _recurrence,
                        reminderOffset: _reminderOffset,
                        isMoreOpen: _isMoreOpen,
                        onDueSelected: _onDueSelected,
                        onReminderSelected: _onReminderSelected,
                        onPrioritySelected: (priority) =>
                            setState(() => _pickedPriority = priority),
                        onCategorySelected: (id) => setState(() {
                          _pickedCategoryId = id;
                          _isCategorySet = true;
                        }),
                        onProjectSelected: (id) =>
                            setState(() => _projectId = id),
                        onRecurrenceSelected: (rule) => setState(() {
                          _pickedRecurrence = rule;
                          _isRecurrenceSet = true;
                        }),
                        onToggleMore: () =>
                            setState(() => _isMoreOpen = !_isMoreOpen),
                      ),
                    ),
                    const Gap(12),
                    _SendButton(
                      isEnabled: _titleText.isNotEmpty && state is! SavingTask,
                      isSaving: state is SavingTask,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Category? _categoryOf(String? id) {
    if (id == null) return null;
    for (final category in _categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  Project? _projectOf(String? id) {
    if (id == null) return null;
    for (final project in _projects) {
      if (project.id == id) return project;
    }
    return null;
  }
}

/// [_KeyboardInset] lifts [child] clear of the keyboard, which is always up here.
///
/// A separate widget rather than a [Padding] in the sheet's own `build`: the
/// inset changes every frame the keyboard animates, and reading it there would
/// rebuild the whole sheet — field, parse and pills — on each one.
class _KeyboardInset extends StatelessWidget {
  const _KeyboardInset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    );
  }
}

/// [_Token] is a `#`- or `@`-token the caret is currently inside.
class _Token {
  const _Token({
    required this.symbol,
    required this.query,
    required this.start,
  });

  final String symbol;
  final String query;

  /// Index of the symbol itself in the field, which is where completion writes.
  final int start;
}

/// [_DueChoice] is one entry of the due-date menu. `pick` opens the full picker —
/// the escape hatch for a date the shortcuts do not cover.
///
/// `time` edits the hour alone: the day shortcuts keep the task's existing time,
/// so without it moving a 9:00 task to 17:00 means re-picking its date.
enum _DueChoice { today, tomorrow, nextWeek, time, pick, none }

/// [_RepeatChoice] is one entry of the repeat menu. It exists so that "never" can
/// travel as a value: a [PopupMenuButton] reads a null selection as a dismissal.
enum _RepeatChoice {
  never(null),
  daily(RecurrenceFrequency.daily),
  weekly(RecurrenceFrequency.weekly),
  monthly(RecurrenceFrequency.monthly),
  yearly(RecurrenceFrequency.yearly);

  const _RepeatChoice(this.frequency);

  final RecurrenceFrequency? frequency;

  String get label => name.capitalized;
}

/// [_ReminderChoice] is one entry of the reminder menu (Requirement 5.1).
///
/// The value is the gap *before* the due date, so `none` is a null offset — and,
/// as with the repeat menu, it must travel as a value for a [PopupMenuButton] to
/// report it.
enum _ReminderChoice {
  none(null, 'No reminder'),
  onTime(Duration.zero, 'At the time'),
  tenMinutes(Duration(minutes: 10), '10 minutes before'),
  oneHour(Duration(hours: 1), '1 hour before'),
  oneDay(Duration(days: 1), '1 day before');

  const _ReminderChoice(this.offset, this.label);

  final Duration? offset;
  final String label;
}

/// [reminderOffsetLabel] names the offset on the pill. An offset the menu does
/// not list falls back to the raw gap, never to "No reminder", which would deny
/// a reminder that exists — and a typed offset is often one the menu has no
/// entry for.
///
/// Public because the assistant's preview names the same offsets and must not
/// name them differently.
String reminderOffsetLabel(Duration offset) {
  for (final choice in _ReminderChoice.values) {
    if (choice.offset == offset) return choice.label;
  }

  if (offset.inDays > 0) return '${offset.inDays}d before';
  if (offset.inHours > 0) return '${offset.inHours}h before';
  if (offset.inMinutes > 0) return '${offset.inMinutes}m before';

  return 'At the time';
}

/// The category menu's "none", for the same reason.
const String _noCategory = '';

/// The project menu's "none", for the same reason.
const String _noProject = '';

/// [_OptionsRow] is the block of pills under the field. It wraps onto as many
/// lines as it needs: every option has to be reachable without a sideways scroll,
/// which hid Category and Repeat off the right edge.
class _OptionsRow extends StatelessWidget {
  const _OptionsRow({
    required this.dueDate,
    required this.priority,
    required this.category,
    required this.categories,
    required this.project,
    required this.projects,
    required this.recurrence,
    required this.reminderOffset,
    required this.isMoreOpen,
    required this.onDueSelected,
    required this.onReminderSelected,
    required this.onPrioritySelected,
    required this.onCategorySelected,
    required this.onProjectSelected,
    required this.onRecurrenceSelected,
    required this.onToggleMore,
  });

  final DateTime? dueDate;
  final TaskPriority priority;
  final Category? category;
  final List<Category> categories;
  final Project? project;
  final List<Project> projects;
  final RecurrenceRule? recurrence;
  final Duration? reminderOffset;
  final bool isMoreOpen;
  final ValueChanged<_DueChoice> onDueSelected;
  final ValueChanged<_ReminderChoice> onReminderSelected;
  final ValueChanged<TaskPriority> onPrioritySelected;
  final ValueChanged<String?> onCategorySelected;
  final ValueChanged<String?> onProjectSelected;
  final ValueChanged<RecurrenceRule?> onRecurrenceSelected;
  final VoidCallback onToggleMore;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OptionPillMenu<_DueChoice>(
          icon: Icons.event_rounded,
          label: dueDate == null ? 'Date' : _dueLabel(dueDate!),
          isSet: dueDate != null,
          accent: colors.primary,
          onSelected: onDueSelected,
          entries: const [
            PillOption(value: _DueChoice.today, label: 'Today'),
            PillOption(value: _DueChoice.tomorrow, label: 'Tomorrow'),
            PillOption(value: _DueChoice.nextWeek, label: 'Next week'),
            PillDivider(),
            PillOption(value: _DueChoice.time, label: 'Time…'),
            PillOption(value: _DueChoice.pick, label: 'Pick a date…'),
            PillOption(value: _DueChoice.none, label: 'No date'),
          ],
        ),
        OptionPillMenu<_ReminderChoice>(
          icon: Icons.notifications_none_rounded,
          label: reminderOffset == null
              ? 'Remind'
              : reminderOffsetLabel(reminderOffset!),
          isSet: reminderOffset != null,
          accent: colors.primary,
          onSelected: onReminderSelected,
          entries: [
            for (final choice in _ReminderChoice.values)
              PillOption(value: choice, label: choice.label),
          ],
        ),
        OptionPillMenu<TaskPriority>(
          icon: Icons.flag_rounded,
          label: _priorityLabel(priority),
          isSet: priority != TaskPriority.medium,
          accent: priority.color,
          onSelected: onPrioritySelected,
          entries: [
            for (final value in _priorityOrder)
              PillOption(
                value: value,
                label: '${_priorityLabel(value)} · ${value.name.capitalized}',
                icon: Icons.flag_rounded,
                iconColor: value.color,
              ),
          ],
        ),
        // Sentinel rather than null, so a "None" pick stays distinguishable
        // from a dismissal.
        OptionPillMenu<String>(
          icon: Icons.folder_outlined,
          label: category?.name ?? 'Category',
          isSet: category != null,
          accent: category?.color ?? colors.primary,
          onSelected: (id) => onCategorySelected(id == _noCategory ? null : id),
          entries: [
            const PillOption(value: _noCategory, label: 'None'),
            for (final value in categories)
              PillOption(
                value: value.id,
                label: value.name,
                icon: Icons.brightness_1_rounded,
                iconColor: value.color,
              ),
          ],
        ),
        // Only worth a pill when there is a project to file under.
        if (projects.isNotEmpty) ...[
          OptionPillMenu<String>(
            icon: Icons.workspaces_outline,
            label: project?.name ?? 'Project',
            isSet: project != null,
            accent: project?.color ?? colors.primary,
            onSelected: (id) => onProjectSelected(id == _noProject ? null : id),
            entries: [
              const PillOption(value: _noProject, label: 'None'),
              for (final value in projects)
                PillOption(value: value.id, label: value.name),
            ],
          ),
        ],
        OptionPillMenu<_RepeatChoice>(
          icon: Icons.repeat_rounded,
          label: recurrence == null ? 'Repeat' : recurrence!.label,
          isSet: recurrence != null,
          accent: colors.primary,
          onSelected: (choice) => onRecurrenceSelected(
            choice.frequency == null
                ? null
                : RecurrenceRule(frequency: choice.frequency!),
          ),
          entries: [
            for (final choice in _RepeatChoice.values)
              PillOption(value: choice, label: choice.label),
          ],
        ),
        OptionPill(
          icon: isMoreOpen
              ? Icons.expand_less_rounded
              : Icons.more_horiz_rounded,
          label: 'More',
          isSet: isMoreOpen,
          accent: colors.primary,
          onTap: onToggleMore,
        ),
      ],
    );
  }
}

/// [_SuggestionRow] completes the `#`- or `@`-token being typed.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.suggestions, required this.onSelect});

  final List<String> suggestions;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const Gap(8),
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];

          return ActionChip(
            label: Text(suggestion),
            visualDensity: VisualDensity.compact,
            onPressed: () => onSelect(suggestion),
          );
        },
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({required this.tags, required this.onRemove});

  final List<String> tags;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in tags)
          Chip(
            label: Text('@$tag'),
            visualDensity: VisualDensity.compact,
            onDeleted: () => onRemove(tag),
            deleteIcon: const Icon(Icons.close_rounded, size: 14),
          ),
      ],
    );
  }
}

/// [_MoreSection] holds everything a task rarely needs: notes, subtasks, delete.
class _MoreSection extends StatelessWidget {
  const _MoreSection({
    required this.notes,
    required this.subtask,
    required this.subtasks,
    required this.canDelete,
    required this.onAddSubtask,
    required this.onToggleSubtask,
    required this.onRemoveSubtask,
    required this.onDelete,
  });

  final TextEditingController notes;
  final TextEditingController subtask;
  final List<SubTask> subtasks;
  final bool canDelete;
  final VoidCallback onAddSubtask;
  final void Function(int index, bool isDone) onToggleSubtask;
  final ValueChanged<int> onRemoveSubtask;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Gap(12),
        TextField(
          controller: notes,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Notes', isDense: true),
        ),
        const Gap(12),
        for (var i = 0; i < subtasks.length; i++)
          Row(
            children: [
              Checkbox(
                value: subtasks[i].isDone,
                visualDensity: VisualDensity.compact,
                onChanged: (value) => onToggleSubtask(i, value ?? false),
              ),
              Expanded(
                child: Text(
                  subtasks[i].title,
                  style: context.texts.bodyMedium?.copyWith(
                    decoration: subtasks[i].isDone
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => onRemoveSubtask(i),
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Remove subtask',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: subtask,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Add a step',
                  isDense: true,
                ),
                onSubmitted: (_) => onAddSubtask(),
              ),
            ),
            IconButton(
              onPressed: onAddSubtask,
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Add subtask',
              
            ),
          ],
        ),
        if (canDelete) ...[
          const Gap(4),
          TextButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete task'),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
          ),
        ],
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isEnabled,
    required this.isSaving,
    required this.onPressed,
  });

  final bool isEnabled;
  final bool isSaving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox.square(
      dimension: 44,
      // The swell and glow arrive on the keystroke that makes the task saveable,
      // so "ready to save" is visible without reading anything.
      child: AnimatedScale(
        scale: isEnabled ? 1 : 0.88,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.4),
                      blurRadius: 14,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: IconButton.filled(
            onPressed: isEnabled ? onPressed : null,
            tooltip: 'Save task',
            style: IconButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              disabledBackgroundColor: colors.surfaceContainerHighest,
              disabledForegroundColor: colors.onSurfaceVariant,
            ),
            icon: isSaving
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onPrimary,
                    ),
                  )
                : const Icon(Icons.arrow_upward_rounded, size: 20),
          ),
        ),
      ),
    );
  }
}

/// Critical first, so the menu reads P1 to P4 the way it is typed.
const List<TaskPriority> _priorityOrder = [
  TaskPriority.critical,
  TaskPriority.high,
  TaskPriority.medium,
  TaskPriority.low,
];

String _priorityLabel(TaskPriority priority) => switch (priority) {
  TaskPriority.critical => 'P1',
  TaskPriority.high => 'P2',
  TaskPriority.medium => 'P3',
  TaskPriority.low => 'P4',
};

/// [_dueLabel] names the day, and the time only when it is not the default 09:00 —
/// the pill has to stay short enough to read at a glance.
String _dueLabel(DateTime date) {
  final isDefaultTime = date.hour == 9 && date.minute == 0;
  if (isDefaultTime) return date.relativeLabel;

  return '${date.relativeLabel} ${DateFormat('h:mm a').format(date)}';
}
