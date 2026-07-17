import 'package:everything_app/data/entity/ai_intent.dart';
import 'package:everything_app/data/entity/ai_prompt.dart';
import 'package:everything_app/data/entity/parsed_ai_inputs.dart';
import 'package:everything_app/data/entity/parsed_task_intent.dart';
import 'package:everything_app/data/entity/parsed_transaction_intent.dart';
import 'package:everything_app/data/models/document.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/search_result.dart';
import 'package:everything_app/data/models/transaction.dart';
import 'package:everything_app/data/models/vault_item.dart';
import 'package:everything_app/data/models/watchlist_item.dart';
import 'package:everything_app/data/repositories/ai_repository.dart';
import 'package:everything_app/data/repositories/documents_repository.dart';
import 'package:everything_app/data/repositories/model_backed_ai_repository.dart';
import 'package:everything_app/data/repositories/text_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// The generation engine behind the assistant's interface.
///
/// ## What earns a test here, and what deliberately does not
///
/// Not the model itself. A network call to Gemini cannot run in CI, and
/// asserting that a model writes a good sentence is not a test — it is a spike,
/// and the plan says to run that against a real key on a device.
///
/// What earns a test is the **boundary** — the [TextEngine] seam — which is
/// where every decision here actually lives:
///
/// 1) **The parsers must never reach the model.** This is the phase's central
///    claim — that a model backs prose and nothing else — and it is exactly the
///    kind of claim that decays silently: someone adds a `parseTaskIntent`
///    override, the previews get slow, and nothing fails. So the fake model
///    *throws* if a parser touches it.
/// 2) **Grounding.** An answer may only contain what the app's own search
///    returned. Phase 10 promised the model "does not get licence to invent";
///    the test is that the model is never called without search running first,
///    and never called at all when search found nothing.
/// 3) **Every failure falls back.** Not loaded, failed, blank — all three must
///    produce the rule-based answer rather than an error or an empty screen. A
///    blank response is the one a naive implementation ships broken.
void main() {
  group('ModelBackedAiRepository — the parsers never reach the model', () {
    // The whole point of the phase's scoping: a model that is loaded and would
    // answer anything must still not be consulted by a single parse path.
    final repository = ModelBackedAiRepository(
      delegate: _FakeRuleBasedAi(),
      engine: _ExplodingEngine(),
      documentsRepository: _FakeDocuments(),
    );

    test('classifyIntent delegates', () {
      expect(repository.classifyIntent('Buy milk tomorrow'), AiIntent.task);
    });

    test('parseTaskIntent delegates', () async {
      final intent = await repository.parseTaskIntent('Buy milk');
      expect(intent.title, 'rule-based task');
    });

    test('parseTransactionIntent delegates', () async {
      final intent = await repository.parseTransactionIntent('Spent 500');
      expect(intent.amountMinor, 50000);
    });

    test('every remaining parse path delegates', () async {
      // Named individually rather than looped, because the failure this guards
      // against is a *new* override added to one of them — and a loop over the
      // ones that exist today would not notice.
      expect((await repository.parseBookmark('x')).url, 'https://rule.based');
      expect((await repository.parseToBuy('x')).name, 'rule-based item');
      expect((await repository.parseWatch('x')).title, 'rule-based title');
      expect((await repository.parseVault('x')).name, 'rule-based secret');
      expect((await repository.parseProject('x')).name, 'rule-based project');
    });

    test('searchWithAI delegates — the index is the app\'s, not the model\'s',
        () async {
      final results = await repository.searchWithAI('passport');
      expect(results, hasLength(2));
    });
  });

  group('ModelBackedAiRepository.answerQuestion — grounded', () {
    test('the model only ever sees what search returned', () async {
      final engine = _RecordingEngine(response: 'You have two tasks about rent.');
      final repository = ModelBackedAiRepository(
        delegate: _FakeRuleBasedAi(),
        engine: engine,
        documentsRepository: _FakeDocuments(),
      );

      final answer = await repository.answerQuestion('what about rent?');

      expect(answer, 'You have two tasks about rent.');

      // The prompt must carry the search hits and nothing the model was left to
      // supply itself.
      expect(engine.lastPrompt, contains('Pay rent'));
      expect(engine.lastPrompt, contains('Renew passport'));
      expect(engine.lastPrompt, contains('what about rent?'));

      // And it must be told, in the system instruction, that the list is all it
      // has. This is the sentence standing between a grounded answer and an
      // invented one.
      expect(engine.lastSystemInstruction, contains('ONLY'));
    });

    test('an empty search never reaches the model at all', () async {
      // Asking a model to explain an empty list is how it starts filling one in.
      final engine = _ExplodingEngine();
      final repository = ModelBackedAiRepository(
        delegate: _FakeRuleBasedAi(results: const []),
        engine: engine,
        documentsRepository: _FakeDocuments(),
      );

      final answer = await repository.answerQuestion('anything about rent?');

      expect(answer, 'rule-based answer');
    });

    test('an unloaded model falls back and never searches for nothing',
        () async {
      final repository = ModelBackedAiRepository(
        delegate: _FakeRuleBasedAi(),
        engine: _ExplodingEngine(isLoaded: false),
        documentsRepository: _FakeDocuments(),
      );

      expect(await repository.answerQuestion('rent'), 'rule-based answer');
    });

    test('a failed generation falls back to the rule-based answer', () async {
      final repository = ModelBackedAiRepository(
        delegate: _FakeRuleBasedAi(),
        engine: _RecordingEngine(isSuccess: false),
        documentsRepository: _FakeDocuments(),
      );

      expect(await repository.answerQuestion('rent'), 'rule-based answer');
    });

    test('a blank generation falls back rather than answering with nothing',
        () async {
      // The failure a naive implementation ships: `success` is true, the string
      // is empty, and the user is shown an answer that is not there.
      final repository = ModelBackedAiRepository(
        delegate: _FakeRuleBasedAi(),
        engine: _RecordingEngine(response: '   \n  '),
        documentsRepository: _FakeDocuments(),
      );

      expect(await repository.answerQuestion('rent'), 'rule-based answer');
    });
  });

  group('ModelBackedAiRepository.summarizeDocument', () {
    test('the model is given the document and summarises it', () async {
      final engine = _RecordingEngine(response: 'A note about the roof.');
      final repository = ModelBackedAiRepository(
        delegate: _FakeRuleBasedAi(),
        engine: engine,
        documentsRepository: _FakeDocuments(),
      );

      final summary = await repository.summarizeDocument('doc-1');

      expect(summary, 'A note about the roof.');
      expect(engine.lastPrompt, contains('The roof leaks'));
    });

    test('a missing document falls back — one owner for the wording', () async {
      final repository = ModelBackedAiRepository(
        delegate: _FakeRuleBasedAi(),
        engine: _ExplodingEngine(),
        documentsRepository: _FakeDocuments(isFound: false),
      );

      expect(
        await repository.summarizeDocument('missing'),
        'rule-based summary',
      );
    });

    test('an empty document never reaches the model', () async {
      final repository = ModelBackedAiRepository(
        delegate: _FakeRuleBasedAi(),
        engine: _ExplodingEngine(),
        documentsRepository: _FakeDocuments(content: '   '),
      );

      expect(await repository.summarizeDocument('doc-1'), 'rule-based summary');
    });

    test('an unloaded model summarises extractively', () async {
      final repository = ModelBackedAiRepository(
        delegate: _FakeRuleBasedAi(),
        engine: _ExplodingEngine(isLoaded: false),
        documentsRepository: _FakeDocuments(),
      );

      expect(await repository.summarizeDocument('doc-1'), 'rule-based summary');
    });
  });

  group('ModelBackedAiRepository.isModelLoaded', () {
    test('reports the model, not the assistant', () async {
      expect(
        ModelBackedAiRepository(
          delegate: _FakeRuleBasedAi(),
          engine: _ExplodingEngine(isLoaded: false),
          documentsRepository: _FakeDocuments(),
        ).isModelLoaded,
        isFalse,
      );
      expect(
        ModelBackedAiRepository(
          delegate: _FakeRuleBasedAi(),
          engine: _ExplodingEngine(),
          documentsRepository: _FakeDocuments(),
        ).isModelLoaded,
        isTrue,
      );
    });
  });

  group('AiPrompt — what the model is allowed to see', () {
    test('an answer prompt carries every hit, numbered and labelled', () {
      final prompt = AiPrompt.answer(
        question: 'rent?',
        results: _results,
      );

      expect(prompt, contains('1. [Tasks] Pay rent'));
      expect(prompt, contains('2. [Tasks] Renew passport'));
    });

    test('the grounding list is capped', () {
      final prompt = AiPrompt.answer(
        question: 'everything',
        results: List.generate(
          40,
          (index) => SearchResult(
            module: SearchModule.tasks,
            id: '$index',
            title: 'Task $index',
          ),
        ),
      );

      expect(prompt, contains('Task 0'));
      expect(prompt, isNot(contains('Task ${AiPrompt.maxGroundingResults}')));
    });

    test('a long document is truncated rather than overflowing the context', () {
      // An oversized document must produce a short summary, not a native failure
      // deep inside the tokenizer.
      final prompt = AiPrompt.summarize(
        title: 'Long',
        body: 'a' * (AiPrompt.maxDocumentChars * 2),
      );

      expect(prompt.length, lessThan(AiPrompt.maxDocumentChars + 200));
    });

    test('both system instructions forbid inventing', () {
      expect(AiPrompt.answerSystemInstruction, contains('Never invent'));
      expect(AiPrompt.summarySystemInstruction, contains('Do not add facts'));
    });
  });
}

const List<SearchResult> _results = [
  SearchResult(module: SearchModule.tasks, id: 't1', title: 'Pay rent'),
  SearchResult(module: SearchModule.tasks, id: 't2', title: 'Renew passport'),
];

/// [_FakeRuleBasedAi] stands in for Phase 10's engine. Every method returns a
/// recognisable constant, so a test can tell "the delegate answered" from "the
/// model answered" without ambiguity.
class _FakeRuleBasedAi implements AiRepository {
  _FakeRuleBasedAi({this.results = _results});

  final List<SearchResult> results;

  @override
  AiIntent classifyIntent(String input) => AiIntent.task;

  @override
  Future<ParsedTaskIntent> parseTaskIntent(String input) async =>
      ParsedTaskIntent(title: 'rule-based task', confidence: 1);

  @override
  Future<ParsedTransactionIntent> parseTransactionIntent(String input) async =>
      ParsedTransactionIntent(
        title: 'rule-based expense',
        amountMinor: 50000,
        category: 'Food',
        type: TransactionType.expense,
        date: DateTime(2026),
        confidence: 1,
      );

  @override
  Future<ParsedBookmarkInput> parseBookmark(String input) async =>
      const ParsedBookmarkInput(url: 'https://rule.based', confidence: 1);

  @override
  Future<ParsedToBuyInput> parseToBuy(String input) async =>
      const ParsedToBuyInput(name: 'rule-based item', confidence: 1);

  @override
  Future<ParsedWatchInput> parseWatch(String input) async =>
      const ParsedWatchInput(
        title: 'rule-based title',
        mediaType: MediaType.movie,
        confidence: 1,
      );

  @override
  Future<ParsedVaultInput> parseVault(String input) async =>
      const ParsedVaultInput(
        name: 'rule-based secret',
        type: VaultItemType.password,
        confidence: 1,
      );

  @override
  Future<ParsedProjectInput> parseProject(String input) async =>
      const ParsedProjectInput(name: 'rule-based project', confidence: 1);

  @override
  Future<String> summarizeDocument(String documentId) async =>
      'rule-based summary';

  @override
  Future<List<SearchResult>> searchWithAI(String query) async => results;

  @override
  Future<String> answerQuestion(String question) async => 'rule-based answer';

  @override
  bool get isModelLoaded => true;
}

/// [_ExplodingEngine] fails the test if it is generated from.
///
/// This is what makes "the parsers never reach the model" an assertion rather
/// than a comment: a future override that routes a parse through the model turns
/// a green suite red at that call, naming the line that did it.
class _ExplodingEngine implements TextEngine {
  _ExplodingEngine({this.isLoaded = true});

  @override
  final bool isLoaded;

  @override
  Future<JsonResponse> generate(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens = 256,
  }) async {
    fail('The model was consulted on a path that must never reach it.');
  }
}

/// [_RecordingEngine] answers, and remembers what it was asked — which is how
/// the grounding assertions read the prompt the model would actually have seen.
class _RecordingEngine extends _ExplodingEngine {
  _RecordingEngine({this.response = 'generated', this.isSuccess = true});

  final String response;
  final bool isSuccess;

  String? lastPrompt;
  String? lastSystemInstruction;

  @override
  Future<JsonResponse> generate(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens = 256,
  }) async {
    lastPrompt = prompt;
    lastSystemInstruction = systemInstruction;

    return isSuccess
        ? JsonResponse.success(message: 'ok', data: response)
        : JsonResponse.failure(statusCode: 500, message: 'Error: no.');
  }
}

class _FakeDocuments implements DocumentsRepository {
  _FakeDocuments({this.isFound = true, this.content = 'The roof leaks.'});

  final bool isFound;
  final String content;

  @override
  Future<JsonResponse> findById(String id) async => JsonResponse.success(
        message: 'ok',
        data: isFound
            ? Document(
                id: id,
                title: 'Roof',
                content: content,
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              )
            : null,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
