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

/// [ModelBackedAiRepository] puts the on-device model behind the assistant's
/// existing contract (Phase 13).
///
/// It is a **decorator, not a replacement**. Phase 10 built [AiRepository] so
/// that an LLM could be dropped in behind it, and this is that drop-in — but it
/// wraps [AiRepositoryImpl] rather than supplanting it, and forwards all but two
/// of its methods untouched. That is a deliberate narrowing of the phase as
/// planned, and the reasons are worth stating because they are the finding, not
/// a shortcut:
///
/// ## 1. The parsers stay rule-based, because the model would make them worse
///
/// Every `parse*` method returns a **structured** type — a title, a due date, a
/// priority, an amount in minor units. `flutter_gemma` 1.3.0 offers no
/// constrained decoding and no JSON-schema output, so a model-backed parser
/// would prompt for JSON and hope, then fall back to the rule-based parser when
/// the JSON came back malformed. That is strictly worse than the rule-based
/// parser alone: same answers when it works, wrong or slow answers when it does
/// not.
///
/// It is also structurally impossible in one case and impractical in another.
/// [classifyIntent] is **synchronous** and runs on every keystroke — no model
/// can implement it. And [AiBloc] re-parses for the live preview on every
/// debounced keystroke, where the rule-based parser costs microseconds and a
/// generation costs seconds; the interface would survive that swap but the
/// typing experience would not.
///
/// ## 2. The model backs the two paths where the rule-based engine has a ceiling
///
/// Phase 10 said so itself. [answerQuestion] is "the honest ceiling of a
/// rule-based engine" — a count and three bullets — and [summarizeDocument] is
/// extractive, lifting opening sentences verbatim. Both are **prose**, both are
/// slow-path (one deliberate submit, not a keystroke), and both are exactly what
/// a small LLM is good at. That is where the 584 MB earns its place, and nowhere
/// else.
///
/// ## 3. Grounding is kept, and enforced by the fallback's own shape
///
/// The model is never asked a question about the world. [answerQuestion] runs
/// the app's own FTS search first — through [delegate], so it is the same index,
/// the same ranking and the same query cleaning Global Search uses — and the
/// model only ever phrases rows that search returned. Phase 10's promise that
/// the model "does not get licence to invent new ones" is kept by never handing
/// it the opportunity: see [AiPrompt].
///
/// ## 4. Every failure degrades to Phase 10, silently
///
/// No model downloaded, model not loaded, generation failed, generation came
/// back blank — all four fall through to [delegate], which is the app's shipped,
/// complete engine. There is no error state and nothing for the user to act on,
/// because nothing they did has failed. This is the same posture Phase 7 took
/// for bookmark metadata: an enrichment that does not arrive is not a fault.
class ModelBackedAiRepository implements AiRepository {
  const ModelBackedAiRepository({
    required this.delegate,
    required this.engine,
    required this.documentsRepository,
  });

  /// The rule-based engine (Phase 10). It answers everything this class does not
  /// override, and every path this class gives up on.
  final AiRepository delegate;

  final TextEngine engine;

  /// Read directly because [AiRepository] hands back a *finished* summary, not
  /// the document — so the raw text the model needs cannot come through
  /// [delegate]. It is the same repository [AiService] reads, so both engines
  /// summarise the same document.
  final DocumentsRepository documentsRepository;

  // ── The two the model backs ──────────────────────────────────────────────

  /// [answerQuestion] answers from the app's own search index, phrased by the
  /// model when there is one (Requirement 16).
  ///
  /// The search runs **first and always**, and its results are the only thing the
  /// model is shown. So the set of facts an answer can contain is identical
  /// whether the model is loaded or not; the model changes the wording, never the
  /// substance.
  @override
  Future<String> answerQuestion(String question) async {
    if (!engine.isLoaded) return delegate.answerQuestion(question);

    final results = await delegate.searchWithAI(question);

    // Nothing found is not a question for a model: there is nothing to phrase,
    // and asking it to explain an empty list is how it starts inventing one.
    if (results.isEmpty) return delegate.answerQuestion(question);

    final generated = await _generate(
      prompt: AiPrompt.answer(question: question, results: results),
      systemInstruction: AiPrompt.answerSystemInstruction,
    );

    // The fallback re-runs the search rather than reformatting the results here.
    // That is one extra FTS query — a few milliseconds, on a path that only runs
    // when the model has already failed — and it buys a single owner for the
    // rule-based wording instead of a second copy of it that can drift.
    return generated ?? await delegate.answerQuestion(question);
  }

  /// [summarizeDocument] summarises a document with the model when there is one,
  /// and extractively when there is not (Requirement 16.6).
  ///
  /// The trade this makes is real and worth naming: Phase 10's extractive
  /// summary "can never misstate what the document says" because it lifts
  /// sentences verbatim. A generated summary can. It is bounded — the model sees
  /// one document and is told to use only that document — but it is a genuine
  /// change in kind, and it is why the on-device model is a switch the user turns
  /// on rather than the default.
  @override
  Future<String> summarizeDocument(String documentId) async {
    if (!engine.isLoaded) return delegate.summarizeDocument(documentId);

    final response = await documentsRepository.findById(documentId);
    final document = response.data;

    // A missing or empty document has established wording in the delegate
    // ("That document could not be found.", "This document is empty.") — one
    // owner for it rather than two that can disagree.
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

  /// [isModelLoaded] reports the **model**, honestly — which is what the field is
  /// named after.
  ///
  /// It is not "the assistant works": the assistant always works, because every
  /// path here falls back to the rule-based engine. Nothing reads this today; it
  /// has been interface surface since Phase 10 waiting for an implementation with
  /// a real answer, and this is the first one that has it.
  @override
  bool get isModelLoaded => engine.isLoaded;

  /// [_generate] returns the model's text, or null for every reason it might not
  /// have any — which the callers turn into the rule-based answer.
  ///
  /// A blank response counts as a failure. A small model asked to summarise
  /// something it has nothing to say about can return an empty string, and an
  /// empty summary shown as a summary reads as a broken document rather than a
  /// quiet fallback.
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

  // ── Everything else is Phase 10, untouched ───────────────────────────────

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
