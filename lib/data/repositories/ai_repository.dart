import 'package:everything_app/data/entity/ai_intent.dart';
import 'package:everything_app/data/entity/parsed_ai_inputs.dart';
import 'package:everything_app/data/entity/parsed_task_intent.dart';
import 'package:everything_app/data/entity/parsed_transaction_intent.dart';
import 'package:everything_app/data/models/search_result.dart';
import 'package:everything_app/data/services/ai_service.dart';

/// [AiRepository] is the assistant's contract (Requirement 16), defined exactly as
/// `design.md`'s `IAIRepository` sketches it.
///
/// It is the one repository that returns bare domain types rather than
/// `Future<JsonResponse>` — a deliberate exception the plan calls out (Phase 10).
/// The whole point of the interface is that Phase 13 can drop an on-device model
/// in behind it with **no** change to the bloc, the sheet, or the tests, so the
/// signatures are frozen to what both a rule-based engine and a model can return.
///
/// It deliberately does **not** create anything: parsing and answering are its
/// job, and persistence stays with the feature repositories the bloc already
/// owns, so a parsed task is saved by `TasksRepository` under the same validation
/// as one from the quick-add sheet.
abstract class AiRepository {
  /// [classifyIntent] guesses what a line is for, so the sheet can preselect the
  /// right mode. Pure and synchronous — it runs on every keystroke.
  AiIntent classifyIntent(String input);

  /// [parseTaskIntent] reads a line into a task intent (Requirement 16.2).
  Future<ParsedTaskIntent> parseTaskIntent(String input);

  /// [parseTransactionIntent] reads a line into a transaction intent
  /// (Requirement 16.3).
  Future<ParsedTransactionIntent> parseTransactionIntent(String input);

  /// [parseBookmark] reads a line into a bookmark URL.
  Future<ParsedBookmarkInput> parseBookmark(String input);

  /// [parseToBuy] reads a line into a to-buy item.
  Future<ParsedToBuyInput> parseToBuy(String input);

  /// [parseWatch] reads a line into a watchlist entry.
  Future<ParsedWatchInput> parseWatch(String input);

  /// [parseVault] reads a line into a vault item.
  Future<ParsedVaultInput> parseVault(String input);

  /// [parseProject] reads a line into a project name.
  Future<ParsedProjectInput> parseProject(String input);

  /// [summarizeDocument] returns a short summary of a stored document
  /// (Requirement 16.6).
  Future<String> summarizeDocument(String documentId);

  /// [searchWithAI] answers a natural-language search over every module
  /// (Requirement 16.5).
  Future<List<SearchResult>> searchWithAI(String query);

  /// [answerQuestion] answers a question about stored information, grounded in
  /// what search returns.
  Future<String> answerQuestion(String question);

  /// [isModelLoaded] is whether the assistant is ready. The rule-based engine
  /// always is; a model-backed one may not be.
  bool get isModelLoaded;
}

class AiRepositoryImpl implements AiRepository {
  const AiRepositoryImpl({required this.aiService});

  final AiService aiService;

  @override
  AiIntent classifyIntent(String input) => AiService.classify(input);

  @override
  Future<ParsedTaskIntent> parseTaskIntent(String input) =>
      aiService.parseTaskIntent(input);

  @override
  Future<ParsedTransactionIntent> parseTransactionIntent(String input) =>
      aiService.parseTransactionIntent(input);

  @override
  Future<ParsedBookmarkInput> parseBookmark(String input) =>
      aiService.parseBookmark(input);

  @override
  Future<ParsedToBuyInput> parseToBuy(String input) =>
      aiService.parseToBuy(input);

  @override
  Future<ParsedWatchInput> parseWatch(String input) =>
      aiService.parseWatch(input);

  @override
  Future<ParsedVaultInput> parseVault(String input) =>
      aiService.parseVault(input);

  @override
  Future<ParsedProjectInput> parseProject(String input) =>
      aiService.parseProject(input);

  @override
  Future<String> summarizeDocument(String documentId) =>
      aiService.summarizeDocument(documentId);

  @override
  Future<List<SearchResult>> searchWithAI(String query) =>
      aiService.searchWithAI(query);

  @override
  Future<String> answerQuestion(String question) =>
      aiService.answerQuestion(question);

  @override
  bool get isModelLoaded => aiService.isModelLoaded;
}
