import 'package:everything_app/data/models/search_result.dart';

/// [AiPrompt] builds the two prompts the on-device model is ever given
/// (Phase 13).
///
/// Pure and static — no plugin, no database, no clock — which is what makes the
/// one piece of real judgement in this phase unit-testable: **what the model is
/// allowed to see, and what it is told it may say.**
///
/// ## Both prompts are grounded, and that is the whole safety argument
///
/// Phase 10 chose a rule-based engine that "physically cannot state a fact the
/// database does not hold", and noted that when the model arrived it could
/// "phrase the same grounded results more fluently; it does not get licence to
/// invent new ones". This class is where that licence is withheld. Neither
/// prompt asks the model a question about the world: [answer] hands it rows the
/// app's own FTS index returned and asks it to read them back; [summarize] hands
/// it one document and asks it to shorten it. A model that knows nothing but
/// what is in the prompt can still be wrong about it, but it cannot invent a
/// transaction that does not exist.
///
/// ## The vault is never in a prompt
///
/// Not enforced here but worth stating where it is visible: a vault row's
/// searchable content is its **name only** (Phase 9, note 2 — its FTS source
/// declares no body column), so a [SearchResult] for a vault item carries a
/// title and nothing else. There is no path by which a decrypted secret reaches
/// [answer]'s context, because the index it draws from never held one.
class AiPrompt {
  const AiPrompt._();

  /// [answerSystemInstruction] is the standing rule for [answer].
  ///
  /// It says "only from the list" twice and in two ways, because the single
  /// thing this model must not do is fill a gap in the search results with
  /// something plausible. The user cannot tell a remembered fact from an
  /// invented one, and this app's answers are about their own money and tasks.
  static const String answerSystemInstruction =
      'You are a concise assistant inside a personal organiser app. '
      'Answer ONLY using the numbered items given to you. '
      'Never invent an item, a number, a date or a detail that is not in that '
      'list. If the list does not answer the question, say that you could not '
      'find it. Reply in at most three short sentences, with no preamble.';

  /// [summarySystemInstruction] is the standing rule for [summarize].
  static const String summarySystemInstruction =
      'You summarise a single document for its own author. '
      'Use only what the document says. Do not add facts, opinions or advice. '
      'Reply with at most three sentences of plain prose, no Markdown, no '
      'preamble.';

  /// How much of a document the summariser is shown.
  ///
  /// The model's context is 2048 tokens and roughly four characters make a
  /// token, so this leaves generous room for the instruction and the answer
  /// while still covering any document someone actually typed. A longer document
  /// is summarised from its opening, which is what an extractive summary would
  /// have done anyway — and truncating here is why an oversized document
  /// produces a short summary rather than a native failure deep inside the
  /// tokenizer.
  static const int maxDocumentChars = 4000;

  /// How many search hits ground an answer. Beyond this the tail is noise the
  /// model has to wade through, and the ranking already put the good ones first
  /// (Phase 9, note 4).
  static const int maxGroundingResults = 8;

  /// [answer] builds a question prompt grounded in [results].
  ///
  /// The results are numbered and labelled with their module, so the model can
  /// say "two tasks and a transaction" without being told the counts — and so a
  /// hallucinated item is visibly absent from a list the user could have read
  /// themselves.
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

  /// [summarize] builds a summary prompt for one document's [title] and [body].
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
