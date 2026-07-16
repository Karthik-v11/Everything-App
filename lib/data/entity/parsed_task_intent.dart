import 'package:everything_app/data/entity/ai_intent.dart';
import 'package:everything_app/data/entity/quick_task_params.dart';
import 'package:everything_app/data/models/category.dart';
import 'package:everything_app/data/models/task.dart';

/// [ParsedTaskIntent] is the assistant's reading of a line meant to create a task
/// (Requirement 16.2, Property 14).
///
/// It is the stable contract between the AI layer and the rest of the app: the
/// rule-based parser fills it today, and Phase 13's on-device model fills the same
/// shape tomorrow, so nothing downstream — the bloc, the sheet, the test — changes
/// when the implementation is swapped.
///
/// It lives under `data/entity/` beside [QuickTaskParams], the pure parser it is
/// built on, and like it is a plain value rather than an Equatable model: it is an
/// inbound parse, never persisted and never streamed.
class ParsedTaskIntent {
  ParsedTaskIntent({
    required this.title,
    required this.confidence,
    this.dueDate,
    this.priority,
    this.categoryId,
    this.recurrence,
    List<String>? tags,
  }) : tags = tags ?? <String>[];

  final String title;
  final DateTime? dueDate;
  final TaskPriority? priority;
  final String? categoryId;
  final RecurrenceRule? recurrence;
  final List<String> tags;

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
  /// [QuickTaskParams], the same pure parser the quick-add sheet uses (plan §5,
  /// Phase 3): the assistant and the sheet cannot disagree about what
  /// "tomorrow 5pm" means because they read it with the same code.
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
      tags: params.tags,
      confidence: confidence,
    );
  }

  /// [toTask] assembles the task to save, minting no id — the service does that.
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
      createdAt: now,
      updatedAt: now,
    );
  }
}
