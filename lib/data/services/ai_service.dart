import 'package:everything_app/data/entity/ai_intent.dart';
import 'package:everything_app/data/entity/parsed_ai_inputs.dart';
import 'package:everything_app/data/entity/parsed_task_intent.dart';
import 'package:everything_app/data/entity/parsed_transaction_intent.dart';
import 'package:everything_app/data/models/bookmark.dart';
import 'package:everything_app/data/models/category.dart';
import 'package:everything_app/data/models/document.dart';
import 'package:everything_app/data/models/search_result.dart';
import 'package:everything_app/data/models/vault_item.dart';
import 'package:everything_app/data/models/watchlist_item.dart';
import 'package:everything_app/data/repositories/documents_repository.dart';
import 'package:everything_app/data/repositories/search_repository.dart';
import 'package:everything_app/data/repositories/tasks_repository.dart';

/// [AiService] is the assistant's rule-based engine (Requirement 16, Phase 10).
///
/// It is deliberately *not* backed by a model. Everything here is deterministic —
/// regex, a keyword lexicon, and the app's own search index — which makes it
/// instant, offline, private, and free of any download. Phase 13 replaces this one
/// class with a `flutter_gemma`-backed one behind the identical [AiRepository]
/// interface; nothing above this layer knows which is running, so the rule-based
/// engine is a complete, shippable fallback rather than a stopgap.
///
/// Unusually for a service it composes other *repositories* rather than a single
/// DAO: the assistant reads a task's categories, the search index, and a document
/// through the same contracts the feature modules use, so it can never see the
/// data differently from the screen that owns it. Parsing itself is pushed down
/// into the pure [ParsedTaskIntent] / [ParsedTransactionIntent] value types, which
/// are unit-testable with no dependencies at all.
class AiService {
  AiService({
    required this.tasksRepository,
    required this.searchRepository,
    required this.documentsRepository,
  });

  final TasksRepository tasksRepository;
  final SearchRepository searchRepository;
  final DocumentsRepository documentsRepository;

  /// [isModelLoaded] is always true: the rule-based engine has nothing to load, so
  /// the sheet never has to gate on a model warming up. Phase 13's model-backed
  /// implementation answers this honestly and the sheet's readiness check starts
  /// to matter then, without changing.
  bool get isModelLoaded => true;

  // ── Classification ───────────────────────────────────────────────────────

  static final RegExp _questionOpener = RegExp(
    r"^(what|when|where|which|who|whose|why|how|do i|did i|have i|"
    r"is there|are there|list|tell me|show me the)\b",
    caseSensitive: false,
  );

  static final RegExp _searchOpener = RegExp(
    r"^(find|search|look for|show me|where'?s|where is)\b",
    caseSensitive: false,
  );

  static final RegExp _noteOpener = RegExp(
    r'^(note|write down|write a note|remember that|remember to jot|jot)\b',
    caseSensitive: false,
  );

  static final RegExp _hasNumber = RegExp(r'\d');

  /// Verbs and markers strong enough to call a line money — deliberately *not*
  /// including "buy"/"bought", which read as a to-do far more often than a spend
  /// ("Buy milk tomorrow" is a task, not an expense).
  static final RegExp _moneyMarker = RegExp(
    r'(₹|\$|\brs\.?\b|\binr\b|\bspent\b|\bspend\b|\bpaid\b|\bpay\b|'
    r'\breceived\b|\bcredited\b|\bearned\b|\bsalary\b|\bincome\b|'
    r'\binvested\b|\bdeposited\b|\brefund\b|\bcashback\b)',
    caseSensitive: false,
  );

  /// URL patterns: a standalone URL or a known domain signals a bookmark.
  static final RegExp _urlPattern = RegExp(
    r'(https?://\S+|'
    r'\b\S+\.(com|org|net|io|dev|co|in|edu|gov)\b|'
    r'\b(github|youtube|youtu\.be|reddit|twitter|x\.com|instagram|'
    r'medium|substack|dev\.to|wikipedia|notion)\b)',
    caseSensitive: false,
  );

  static final RegExp _bookmarkOpener = RegExp(
    r'^(save|bookmark|clip|save link|add link)\b',
    caseSensitive: false,
  );

  static final RegExp _toBuyOpener = RegExp(
    r'^(buy|need to (get|buy|pick up|grab|order)|'
    r'pick up|get|order|grab|shopping list|add to (cart|list)|'
    r'remember to (buy|get|pick up|grab|order))\b',
    caseSensitive: false,
  );

  static final RegExp _watchOpener = RegExp(
    r'^(watch|reading|read|playing|play|started watching|'
    r'started reading|started playing|add (to my )?watchlist|'
    r'want to watch|want to read|want to play|'
    r'plan to watch|plan to read|plan to play)\b',
    caseSensitive: false,
  );

  static final RegExp _vaultOpener = RegExp(
    r'^(save|add|store|remember) (my )?'
    r'(password|credential|login|account number|card|'
    r'bank (details?|account)|ifsc|pin|cvv)\b',
    caseSensitive: false,
  );

  static final RegExp _projectOpener = RegExp(
    r'^(start|create|new|begin) (a )?(project|workspace|repo)\b',
    caseSensitive: false,
  );

  /// [classify] guesses what one line is for (Requirement 16), which the sheet
  /// uses only as the default mode. It is pure and synchronous so the sheet can
  /// re-guess on every keystroke without a round trip; the user's manual pick
  /// always wins over it.
  static AiIntent classify(String input) {
    final text = input.trim();
    if (text.isEmpty) return AiIntent.task;

    if (_noteOpener.hasMatch(text)) return AiIntent.note;
    if (_searchOpener.hasMatch(text)) return AiIntent.search;
    if (text.endsWith('?') || _questionOpener.hasMatch(text)) {
      return AiIntent.question;
    }

    // URL present — likely a bookmark.
    if (_urlPattern.hasMatch(text) || _bookmarkOpener.hasMatch(text)) {
      return AiIntent.bookmark;
    }

    // Vault-related: "save my password for Gmail".
    if (_vaultOpener.hasMatch(text)) return AiIntent.vaultItem;

    // Shopping intent.
    if (_toBuyOpener.hasMatch(text)) return AiIntent.toBuy;

    // Media consumption.
    if (_watchOpener.hasMatch(text)) return AiIntent.watchItem;

    // Project creation.
    if (_projectOpener.hasMatch(text)) return AiIntent.project;

    // A number alone is not money — a time or a quantity has one too. It takes a
    // currency marker or a spend/earn verb to read the line as a transaction.
    if (_hasNumber.hasMatch(text) && _moneyMarker.hasMatch(text)) {
      return AiIntent.expense;
    }

    return AiIntent.task;
  }

  // ── Parsing ──────────────────────────────────────────────────────────────

  /// [parseTaskIntent] resolves `#category` tokens against the user's real
  /// categories, then hands the line to the pure parser (Requirement 16.2).
  Future<ParsedTaskIntent> parseTaskIntent(String input) async {
    final categories = await _categories();
    return ParsedTaskIntent.parse(input, categories: categories);
  }

  /// [parseTransactionIntent] needs nothing from the database — the category
  /// lexicon is a constant — but stays async to match the interface the model
  /// implementation will need (Requirement 16.3).
  Future<ParsedTransactionIntent> parseTransactionIntent(String input) async =>
      ParsedTransactionIntent.parse(input);

  // ── Bookmark parsing ─────────────────────────────────────────────────────

  static final RegExp _urlExtractor = RegExp(
    r'(https?://\S+)',
    caseSensitive: false,
  );

  /// [parseBookmark] extracts a URL from the input.
  Future<ParsedBookmarkInput> parseBookmark(String input) async {
    final text = input.trim();

    // Direct URL.
    final urlMatch = _urlExtractor.firstMatch(text);
    if (urlMatch != null) {
      final url = UrlMetadata.normalize(urlMatch.group(1)!);
      if (UrlMetadata.isValid(url)) {
        return ParsedBookmarkInput(url: url, confidence: 0.95);
      }
    }

    // Bare domain.
    final domainMatch = _urlPattern.firstMatch(text);
    if (domainMatch != null) {
      final candidate = domainMatch.group(0)!;
      if (candidate.contains('.') && !candidate.contains(' ')) {
        final url = UrlMetadata.normalize(candidate);
        if (UrlMetadata.isValid(url)) {
          return ParsedBookmarkInput(url: url, confidence: 0.8);
        }
      }
    }

    return ParsedBookmarkInput(url: '', confidence: 0.2);
  }

  // ── To-buy parsing ───────────────────────────────────────────────────────

  static final RegExp _toBuyCleaner = RegExp(
    r'^(buy|need to (get|buy|pick up|grab|order)|'
    r'pick up|get|order|grab|add to (cart|list)|'
    r'remember to (buy|get|pick up|grab|order))\b',
    caseSensitive: false,
  );

  static final RegExp _storePattern = RegExp(
    r'\b(from|at|on)\s+(.+)$',
    caseSensitive: false,
  );

  static final RegExp _priceInText = RegExp(
    r'(₹|rs\.?|inr|\$)?\s?(\d[\d,]*(?:\.\d+)?)\s?(k|lac|lakh|l)?\b',
    caseSensitive: false,
  );

  /// [parseToBuy] extracts the item name, optional store, and optional price.
  Future<ParsedToBuyInput> parseToBuy(String input) async {
    var text = input.trim();
    text = text.replaceFirst(_toBuyCleaner, '').trim();

    // Extract store: "from Amazon" or "at DMart".
    String? store;
    final storeMatch = _storePattern.firstMatch(text);
    if (storeMatch != null) {
      store = storeMatch.group(2)?.trim();
      text = text.substring(0, storeMatch.start).trim();
    }

    // Extract price if present.
    int? priceMinor;
    final priceMatch = _priceInText.firstMatch(text);
    if (priceMatch != null) {
      final digits = priceMatch.group(2)!.replaceAll(',', '');
      final value = double.tryParse(digits);
      if (value != null) {
        final suffix = priceMatch.group(3)?.toLowerCase();
        final multiplier = switch (suffix) {
          'k' => 1000,
          'l' || 'lac' || 'lakh' => 100000,
          _ => 1,
        };
        priceMinor = (value * multiplier * 100).round();
        text = text.replaceFirst(_priceInText, '').trim();
      }
    }

    final name = text.trim();
    final confidence = name.isEmpty ? 0.2 : 0.85;

    return ParsedToBuyInput(
      name: name,
      store: store,
      estimatedPriceMinor: priceMinor,
      confidence: confidence.toDouble(),
    );
  }

  // ── Watch parsing ────────────────────────────────────────────────────────

  static final RegExp _watchCleaner = RegExp(
    r'^(watch|reading|read|playing|play|started watching|'
    r'started reading|started playing|add (to my )?watchlist|'
    r'want to watch|want to read|want to play|'
    r'plan to watch|plan to read|plan to play)\b',
    caseSensitive: false,
  );

  static final RegExp _movieHint = RegExp(
    r'\b(movie|film|cinema|theatre|theater)\b',
    caseSensitive: false,
  );

  static final RegExp _tvHint = RegExp(
    r'\b(tv|series|show|episode|season|netflix|prime|disney|hulu|hbo)\b',
    caseSensitive: false,
  );

  static final RegExp _animeHint = RegExp(r'\b(anime)\b', caseSensitive: false);

  static final RegExp _mangaHint = RegExp(r'\b(manga)\b', caseSensitive: false);

  static final RegExp _bookHint = RegExp(
    r'\b(book|novel|reading|author|chapter)\b',
    caseSensitive: false,
  );

  static final RegExp _gameHint = RegExp(
    r'\b(game|gaming|playstation|ps[45]|xbox|switch|steam)\b',
    caseSensitive: false,
  );

  /// [parseWatch] extracts the title and media type from the input.
  Future<ParsedWatchInput> parseWatch(String input) async {
    var text = input.trim();
    text = text.replaceFirst(_watchCleaner, '').trim();

    final mediaType = _detectMediaType(text);
    final title = text.trim();
    final confidence = title.isEmpty ? 0.2 : 0.8;

    return ParsedWatchInput(
      title: title,
      mediaType: mediaType,
      confidence: confidence.toDouble(),
    );
  }

  static MediaType _detectMediaType(String text) {
    if (_animeHint.hasMatch(text)) return MediaType.anime;
    if (_mangaHint.hasMatch(text)) return MediaType.manga;
    if (_gameHint.hasMatch(text)) return MediaType.game;
    if (_bookHint.hasMatch(text)) return MediaType.book;
    if (_tvHint.hasMatch(text)) return MediaType.tvShow;
    if (_movieHint.hasMatch(text)) return MediaType.movie;
    return MediaType.movie;
  }

  // ── Vault parsing ────────────────────────────────────────────────────────

  static final RegExp _vaultCleaner = RegExp(
    r'^(save|add|store|remember) (my )?',
    caseSensitive: false,
  );

  static final RegExp _passwordHint = RegExp(
    r'(password|passwd|pwd|credential|login)',
    caseSensitive: false,
  );

  static final RegExp _bankHint = RegExp(
    r'(bank|account (number|no)|ifsc)',
    caseSensitive: false,
  );

  static final RegExp _identityHint = RegExp(
    r'(passport|aadhaar|aadhar|pan|driver.?s? ?licence|license|'
    r'voter.?s? ?id|social security|ssn|national id)',
    caseSensitive: false,
  );

  static final RegExp _cardHint = RegExp(
    r'(card|credit|debit|visa|mastercard|amex)',
    caseSensitive: false,
  );

  /// [parseVault] extracts the item name and type from the input.
  Future<ParsedVaultInput> parseVault(String input) async {
    var text = input.trim();
    text = text.replaceFirst(_vaultCleaner, '').trim();

    final type = _detectVaultType(text);
    final name = text.trim();
    final confidence = name.isEmpty ? 0.2 : 0.75;

    return ParsedVaultInput(
      name: name,
      type: type,
      confidence: confidence.toDouble(),
    );
  }

  static VaultItemType _detectVaultType(String text) {
    if (_passwordHint.hasMatch(text)) return VaultItemType.password;
    if (_cardHint.hasMatch(text)) return VaultItemType.card;
    if (_bankHint.hasMatch(text)) return VaultItemType.bankDetail;
    if (_identityHint.hasMatch(text)) return VaultItemType.identity;
    return VaultItemType.document;
  }

  // ── Project parsing ──────────────────────────────────────────────────────

  static final RegExp _projectCleaner = RegExp(
    r'^(start|create|new|begin) (a )?(project|workspace|repo)?\s*',
    caseSensitive: false,
  );

  /// [parseProject] extracts the project name from the input.
  Future<ParsedProjectInput> parseProject(String input) async {
    var text = input.trim();
    text = text.replaceFirst(_projectCleaner, '').trim();

    final name = text.trim();
    final confidence = name.isEmpty ? 0.2 : 0.85;

    return ParsedProjectInput(
      name: name,
      confidence: confidence.toDouble(),
    );
  }

  // ── Search & questions ───────────────────────────────────────────────────

  static final RegExp _fillerPattern = RegExp(
    r"^(find|search|look for|show me|where'?s|where is|what'?s|what is|"
    r"how much did i spend on|how much|do i have|list|tell me about)\s+",
    caseSensitive: false,
  );

  static final RegExp _leadingFluff = RegExp(
    r'^(my|the|a|an|any|all|some)\s+',
    caseSensitive: false,
  );

  /// [searchWithAI] strips the natural-language wrapper off a query — "Find my
  /// passport" → "passport" — then runs it through the same FTS index Global
  /// Search uses (Requirement 16.5, 17). Phase 13's model can rank the same
  /// results more cleverly; the contract does not change.
  Future<List<SearchResult>> searchWithAI(String query) async {
    final cleaned = _stripFiller(query);
    final response = await searchRepository.search(
      cleaned.isEmpty ? query : cleaned,
    );

    if (!response.success) return const <SearchResult>[];
    return response.data! as List<SearchResult>;
  }

  /// [answerQuestion] answers a question about stored data by searching for it and
  /// reporting what was found (Requirement 16, "Answer questions about stored
  /// information"). It is grounded — it only ever says what the search returned —
  /// which is the honest ceiling of a rule-based engine, and a safe one: it cannot
  /// invent a fact the database does not hold.
  Future<String> answerQuestion(String question) async {
    final results = await searchWithAI(question);

    if (results.isEmpty) {
      return "I couldn't find anything about that in your data.";
    }

    final byModule = <SearchModule, int>{};
    for (final result in results) {
      byModule.update(result.module, (count) => count + 1, ifAbsent: () => 1);
    }

    final counts = [
      for (final entry in byModule.entries)
        '${entry.value} ${entry.key.label.toLowerCase()}',
    ].join(', ');

    final examples = results
        .take(3)
        .map((result) => '• ${result.title}')
        .join('\n');

    return 'I found $counts.\n$examples';
  }

  /// [summarizeDocument] gives a short extractive summary of a document
  /// (Requirement 16.6). Extractive, not generative: it lifts the opening lines
  /// verbatim and strips their Markdown, so it can never misstate what the
  /// document says — a rule-based summary that paraphrased would be guessing.
  Future<String> summarizeDocument(String documentId) async {
    final response = await documentsRepository.findById(documentId);

    if (!response.success || response.data == null) {
      return 'That document could not be found.';
    }

    return _summarize(response.data! as Document);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<List<Category>> _categories() async {
    final response = await tasksRepository.categories();
    if (!response.success || response.data == null) return const <Category>[];
    return response.data! as List<Category>;
  }

  static String _stripFiller(String query) {
    var text = query.trim();
    text = text.replaceFirst(_fillerPattern, '');
    text = text.replaceFirst(_leadingFluff, '');
    return text.replaceAll(RegExp(r'[?.!]+$'), '').trim();
  }

  static final RegExp _markdownSyntax = RegExp(r'[#>*_`~\-\[\]()!]');
  static final RegExp _sentenceSplit = RegExp(r'(?<=[.!?])\s+');

  static String _summarize(Document document) {
    final body = document.content
        .split('\n')
        .map((line) => line.replaceAll(_markdownSyntax, '').trim())
        .where((line) => line.isNotEmpty)
        .join(' ')
        .trim();

    if (body.isEmpty) return 'This document is empty.';

    final sentences = body.split(_sentenceSplit);
    final summary = sentences.take(3).join(' ').trim();

    // A body with no sentence punctuation stays one long run — cap it so the
    // summary is a summary rather than the whole document.
    if (summary.length <= 280) return summary;
    return '${summary.substring(0, 277).trimRight()}…';
  }
}
