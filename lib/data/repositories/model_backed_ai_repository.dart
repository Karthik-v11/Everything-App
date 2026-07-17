import 'package:everything_app/data/entity/ai_intent.dart';
import 'package:everything_app/data/entity/ai_prompt.dart';
import 'package:everything_app/data/entity/parsed_ai_inputs.dart';
import 'package:everything_app/data/entity/parsed_task_intent.dart';
import 'package:everything_app/data/entity/parsed_transaction_intent.dart';
import 'package:everything_app/data/models/document.dart';
import 'package:everything_app/data/models/search_result.dart';
import 'package:everything_app/data/repositories/ai_repository.dart';
import 'package:everything_app/data/repositories/documents_repository.dart';
import 'package:everything_app/data/repositories/text_engine.dart';

/// Decorates the rule-based [AiRepository] with a [TextEngine], which backs only
/// the two prose paths ([answerQuestion], [summarizeDocument]).
///
/// The `parse*` methods return structured types and stay rule-based: they must
/// be instant, deterministic and offline, and [classifyIntent] is synchronous.
/// Any engine failure falls through to [delegate], which is a complete engine,
/// so there is no error state.
class ModelBackedAiRepository implements AiRepository {
  const ModelBackedAiRepository({
    required this.delegate,
    required this.engine,
    required this.documentsRepository,
  });

  /// Answers every path this class does not override.
  final AiRepository delegate;

  final TextEngine engine;

  /// Read directly: [AiRepository] returns a finished summary, not the raw text
  /// the model needs.
  final DocumentsRepository documentsRepository;

  /// Answers from the app's own FTS index, phrased by the model (Requirement 16).
  /// Search runs first and its results are all the model is shown, so the model
  /// changes the wording, never the facts.
  @override
  Future<String> answerQuestion(String question) async {
    if (!engine.isLoaded) return delegate.answerQuestion(question);

    final results = await delegate.searchWithAI(question);

    // An empty result set gives the model nothing to phrase, which is where it
    // starts inventing facts.
    if (results.isEmpty) return delegate.answerQuestion(question);

    final generated = await _generate(
      prompt: AiPrompt.answer(question: question, results: results),
      systemInstruction: AiPrompt.answerSystemInstruction,
    );

    // Re-runs the search rather than reformatting results here, keeping one
    // owner for the rule-based wording.
    return generated ?? await delegate.answerQuestion(question);
  }

  /// Summarises with the model, or extractively without one (Requirement 16.6).
  /// A generated summary can misstate the document where the extractive one
  /// cannot, which is why the model is opt-in.
  @override
  Future<String> summarizeDocument(String documentId) async {
    if (!engine.isLoaded) return delegate.summarizeDocument(documentId);

    final response = await documentsRepository.findById(documentId);
    final document = response.data;

    // The delegate owns the wording for a missing or empty document.
    if (!response.success || document is! Document) {
      return delegate.summarizeDocument(documentId);
    }
    if (document.content.trim().isEmpty) {
      return delegate.summarizeDocument(documentId);
    }

    final generated = await _generate(
      prompt: AiPrompt.summarize(
        title: document.displayTitle,
        body: document.content,
      ),
      systemInstruction: AiPrompt.summarySystemInstruction,
    );

    return generated ?? await delegate.summarizeDocument(documentId);
  }

  /// Reports the model, not the assistant — which works regardless, via [delegate].
  @override
  bool get isModelLoaded => engine.isLoaded;

  /// Returns the model's text, or null for any failure — including a blank
  /// response, which a small model can return and which reads as a broken
  /// document if shown.
  Future<String?> _generate({
    required String prompt,
    required String systemInstruction,
  }) async {
    final response = await engine.generate(
      prompt,
      systemInstruction: systemInstruction,
    );

    final text = response.data;
    if (!response.success || text is! String || text.trim().isEmpty) return null;
    return text.trim();
  }

  @override
  AiIntent classifyIntent(String input) => delegate.classifyIntent(input);

  @override
  Future<ParsedTaskIntent> parseTaskIntent(String input) =>
      delegate.parseTaskIntent(input);

  @override
  Future<ParsedTransactionIntent> parseTransactionIntent(String input) =>
      delegate.parseTransactionIntent(input);

  @override
  Future<ParsedBookmarkInput> parseBookmark(String input) =>
      delegate.parseBookmark(input);

  @override
  Future<ParsedToBuyInput> parseToBuy(String input) => delegate.parseToBuy(input);

  @override
  Future<ParsedWatchInput> parseWatch(String input) => delegate.parseWatch(input);

  @override
  Future<ParsedVaultInput> parseVault(String input) => delegate.parseVault(input);

  @override
  Future<ParsedProjectInput> parseProject(String input) =>
      delegate.parseProject(input);

  @override
  Future<List<SearchResult>> searchWithAI(String query) =>
      delegate.searchWithAI(query);
}
