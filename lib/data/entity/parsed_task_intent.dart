import 'package:everything_app/data/entity/ai_intent.dart';
import 'package:everything_app/data/entity/quick_task_params.dart';
import 'package:everything_app/data/models/category.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:uuid/uuid.dart';

/// [ParsedTaskIntent] is the assistant's reading of a line meant to create a task
/// (Requirement 16.2, Property 14).
///
/// The stable contract between the AI layer and the rest of the app: the
/// rule-based parser and the on-device model fill the same shape, so nothing
/// downstream changes when the implementation is swapped.
class ParsedTaskIntent {
  ParsedTaskIntent({
    required this.title,
    required this.confidence,
    this.dueDate,
    this.priority,
    this.categoryId,
    this.recurrence,
    this.reminderOffset,
    List<String>? tags,
  }) : tags = tags ?? <String>[];

  final String title;
  final DateTime? dueDate;
  final TaskPriority? priority;
  final String? categoryId;
  final RecurrenceRule? recurrence;
  final List<String> tags;

  /// How long before [dueDate] to be reminded, as written. Kept as an offset
  /// rather than a moment so it means the same thing here as in the sheet; it
  /// becomes an absolute [Reminder] in [toTask].
  final Duration? reminderOffset;

  /// 0–1 confidence that this line was a task worth creating. A line the parser
  /// could pull no name out of scores low, which is what triggers the sheet's
  /// clarifying question rather than saving a nameless task (Requirement 16.7).
  final double confidence;

  /// [isConfidentAt] gates automatic creation against the user's threshold
  /// (Requirement 25.3). A confident intent always has a non-empty title,
  /// whatever the threshold — which is the first half of Property 14, and is why
  /// the title check sits outside the comparison rather than being folded into
  /// the score.
  bool isConfidentAt(double threshold) =>
      confidence >= threshold && title.trim().isNotEmpty;

  /// [isConfident] is [isConfidentAt] at the shipped default, for the call sites
  /// and tests that have no setting to hand.
  bool get isConfident => isConfidentAt(kAiConfidenceThreshold);

  /// [ParsedTaskIntent.parse] reads [input] into a task intent.
  ///
  /// The heavy lifting — dates, priority, `#category`, `@tags`, recurrence — is
  /// [QuickTaskParams], the same pure parser the quick-add sheet uses (plan §5),
  /// so the assistant and the sheet cannot disagree about what "tomorrow 5pm"
  /// means.
  ///
  /// [categories] resolves `#work`; [now] anchors every relative date and is
  /// injectable so the parse is testable.
  factory ParsedTaskIntent.parse(
    String input, {
    List<Category> categories = const <Category>[],
    DateTime? now,
  }) {
    final params = QuickTaskParams.parse(input, categories: categories, now: now);

    final hasTitle = params.title.trim().isNotEmpty;

    // A line with no name left after the tokens are stripped ("tomorrow 5pm") is
    // not yet a task — score it below the threshold so the sheet asks what to
    // call it. A named line is a task; an extra token (a date, a priority) is
    // corroborating evidence that it was meant as one, so it scores higher.
    final confidence = !hasTitle
        ? 0.2
        : params.hasTokens
            ? 0.95
            : 0.7;

    return ParsedTaskIntent(
      title: params.title,
      dueDate: params.dueDate,
      priority: params.priority,
      categoryId: params.categoryId,
      recurrence: params.recurrence,
      reminderOffset: params.reminderOffset,
      tags: params.tags,
      confidence: confidence,
    );
  }

  /// [toTask] assembles the task to save, minting no task id — the service does
  /// that.
  ///
  /// The defaults match [QuickTaskParams.toTask]: an unstated priority is medium,
  /// the rest are simply absent.
  Task toTask() {
    final now = DateTime.now();

    return Task(
      id: '',
      title: title.trim(),
      dueDate: dueDate,
      priority: priority ?? TaskPriority.medium,
      categoryId: categoryId,
      recurrence: recurrence,
      tags: tags,
      reminders: _reminders,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// [_reminders] is [reminderOffset] resolved against [dueDate]. A reminder has
  /// nothing to be relative to without a due date, so it is dropped rather than
  /// guessed at. The id is minted here because the service mints only the task's.
  List<Reminder> get _reminders {
    final due = dueDate;
    final offset = reminderOffset;
    if (due == null || offset == null) return const [];

    return [Reminder(id: const Uuid().v4(), at: due.subtract(offset))];
  }
}
