import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/entity/briefing_facts.dart';
import 'package:everything_app/data/models/search_result.dart';

/// [AiPrompt] builds every prompt the model is given (design.md §5.2). Pure and
/// static, so what the model may see and say is unit-testable.
///
/// Every prompt is grounded: the model is only ever handed app data and asked to
/// phrase it back, never asked a question about the world. It can be wrong about
/// what it was given, but it cannot invent a transaction that does not exist.
///
/// A vault row's searchable content is its name only (its FTS source declares no
/// body column), so a vault [SearchResult] carries a title and nothing else — no
/// decrypted secret can reach [answer]'s context. [briefing] is the one
/// multi-source prompt, so grounding is enforced by the instruction plus
/// [BriefingFacts] being a closed list no vault row, balance or transaction can
/// enter.
class AiPrompt {
  const AiPrompt._();

  /// Standing rule for [answer]. States "only from the list" twice and in two
  /// ways: the model must not fill a gap in the search results with something
  /// plausible, since these answers are about the user's own money and tasks.
  static const String answerSystemInstruction =
      'You are a concise assistant inside a personal organiser app. '
      'Answer ONLY using the numbered items given to you. '
      'Never invent an item, a number, a date or a detail that is not in that '
      'list. If the list does not answer the question, say that you could not '
      'find it. Reply in at most three short sentences, with no preamble.';

  /// Standing rule for [briefing]. "Do not give advice" is load-bearing: this is
  /// an organiser, not a life coach.
  static const String briefingSystemInstruction =
      'You write one short daily briefing for the owner of a personal organiser '
      'app. Use ONLY the facts given to you. Never invent a task, a number, a '
      'date, a headline or a weather reading. Do not give advice, opinions or '
      'encouragement. Two or three sentences of plain prose, no Markdown, no '
      'preamble.';

  /// Standing rule for [summarize].
  static const String summarySystemInstruction =
      'You summarise a single document for its own author. '
      'Use only what the document says. Do not add facts, opinions or advice. '
      'Reply with at most three sentences of plain prose, no Markdown, no '
      'preamble.';

  /// How much of a document the summariser is shown. The model's context is 2048
  /// tokens at roughly four characters each; truncating here is why an oversized
  /// document yields a short summary rather than a failure inside the tokenizer.
  static const int maxDocumentChars = 4000;

  /// How many search hits ground an answer. Ranking already puts the good ones
  /// first, so the tail is only noise.
  static const int maxGroundingResults = 8;

  /// How many task titles the briefing is shown.
  static const int maxBriefingTasks = 6;

  /// How many headlines the briefing is shown. [Article] carries no body, so a
  /// headline can only be named here, never explained.
  static const int maxBriefingHeadlines = 3;

  /// Builds a question prompt grounded in [results]. Results are numbered and
  /// module-labelled so a hallucinated item is visibly absent from a list the
  /// user could have read themselves.
  static String answer({
    required String question,
    required List<SearchResult> results,
  }) {
    final items = results.take(maxGroundingResults).toList();

    final buffer = StringBuffer()
      ..writeln('Question: ${question.trim()}')
      ..writeln()
      ..writeln('Items found in the user\'s data:');

    for (var index = 0; index < items.length; index++) {
      final result = items[index];
      buffer.writeln(
        '${index + 1}. [${result.module.label}] ${result.title.trim()}',
      );
    }

    buffer
      ..writeln()
      ..write('Answer the question using only these items.');

    return buffer.toString();
  }

  /// Builds the daily briefing prompt from [facts]. A heading whose source has
  /// nothing to say is omitted entirely rather than emitted empty — an empty
  /// `Tasks:` heading invites the model to fill it in.
  static String briefing({required BriefingFacts facts}) {
    final buffer = StringBuffer()
      ..writeln('Now: ${facts.greeting}, ${facts.now.dashboardDate}, '
          '${facts.now.timeLabel}. Season: ${facts.season.label}.');

    final weather = facts.weather;
    if (weather != null) {
      final place = facts.city ?? weather.city;
      buffer.writeln(
        'Weather: $place, ${weather.temperature}C, ${weather.description}.',
      );
    }

    if (facts.taskCount > 0) {
      buffer.writeln(
        'Tasks: ${facts.taskCount} due today, ${facts.overdueCount} overdue.',
      );
      for (final title in facts.taskTitles.take(maxBriefingTasks)) {
        buffer.writeln('- ${title.trim()}');
      }
    }

    final headlines = facts.headlines.take(maxBriefingHeadlines).toList();
    if (headlines.isNotEmpty) {
      buffer.writeln('Headlines:');
      for (final headline in headlines) {
        buffer.writeln('- ${headline.trim()}');
      }
    }

    buffer
      ..writeln()
      ..write('Write the briefing.');

    return buffer.toString();
  }

  /// Builds a summary prompt for one document's [title] and [body].
  static String summarize({required String title, required String body}) {
    final trimmed = body.trim();
    final capped = trimmed.length <= maxDocumentChars
        ? trimmed
        : trimmed.substring(0, maxDocumentChars);

    return 'Document title: ${title.trim()}\n\n'
        'Document:\n$capped\n\n'
        'Summarise this document.';
  }
}
