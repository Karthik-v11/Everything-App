import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/bloc/event_transformers.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/data/entity/ai_intent.dart';
import 'package:everything_app/data/entity/parsed_ai_inputs.dart';
import 'package:everything_app/data/entity/parsed_task_intent.dart';
import 'package:everything_app/data/entity/parsed_transaction_intent.dart';
import 'package:everything_app/data/models/bookmark.dart';
import 'package:everything_app/data/models/document.dart';
import 'package:everything_app/data/models/project.dart';
import 'package:everything_app/data/models/search_result.dart';
import 'package:everything_app/data/models/to_buy_item.dart';
import 'package:everything_app/data/models/watchlist_item.dart';
import 'package:everything_app/data/repositories/ai_repository.dart';
import 'package:everything_app/data/repositories/bookmarks_repository.dart';
import 'package:everything_app/data/repositories/documents_repository.dart';
import 'package:everything_app/data/repositories/finance_repository.dart';
import 'package:everything_app/data/repositories/projects_repository.dart';
import 'package:everything_app/data/repositories/tasks_repository.dart';
import 'package:everything_app/data/repositories/to_buy_repository.dart';
import 'package:everything_app/data/repositories/watchlist_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

part 'ai_event.dart';
part 'ai_state.dart';

/// [AiBloc] drives the AI assistant sheet (Requirement 16, Phase 10).
///
/// It parses through [AiRepository] but **creates** through the feature
/// repositories — [TasksRepository], [FinanceRepository], [DocumentsRepository],
/// [BookmarksRepository], [ToBuyRepository], [WatchlistRepository],
/// [ProjectsRepository] — because the AI layer deliberately does not persist (see
/// [AiRepository]). So an item the assistant creates is saved by exactly the code
/// the quick-add sheet uses, under the same validation, and reaches every screen
/// through the same DAO stream. The bloc is the composition point where a parsed
/// intent becomes a real entry.
///
/// Style A: it holds the live preview, the chosen mode, search results and an
/// answer across the session, and clears them on [AiOpened].
///
/// Events:
/// 1) [AiOpened] — the sheet opened; start a clean session.
/// 2) [AiInputChanged] — the field changed; re-guess the mode and re-preview.
/// 3) [AiModeSelected] — the user picked a mode, pinning it.
/// 4) [AiSubmitted] — run the mode's action (create / search / answer).
class AiBloc extends Bloc<AiEvent, AiState> {
  AiBloc({
    required this.repository,
    required this.tasksRepository,
    required this.financeRepository,
    required this.documentsRepository,
    required this.bookmarksRepository,
    required this.toBuyRepository,
    required this.watchlistRepository,
    required this.projectsRepository,
  }) : super(const AiState()) {
    on<AiOpened>(_onOpened);
    on<AiInputChanged>(_onInputChanged, transformer: debounce(kSearchDebounce));
    on<AiModeSelected>(_onModeSelected);
    on<AiSubmitted>(_onSubmitted);
    on<ConfigureAiEvent>(_onConfigureAiEvent);
  }

  final AiRepository repository;
  final TasksRepository tasksRepository;
  final FinanceRepository financeRepository;
  final DocumentsRepository documentsRepository;
  final BookmarksRepository bookmarksRepository;
  final ToBuyRepository toBuyRepository;
  final WatchlistRepository watchlistRepository;
  final ProjectsRepository projectsRepository;

  static const Uuid _uuid = Uuid();

  /// [_onOpened] starts a clean session.
  ///
  /// [AiState.confidence] is carried over rather than reset: it is the user's
  /// setting (Requirement 25.3), not part of a session, and `const AiState()`
  /// would quietly put it back to the shipped default every time the sheet was
  /// opened — so the slider would appear to work until the sheet was closed and
  /// reopened.
  FutureOr<void> _onOpened(AiOpened event, Emitter<AiState> emit) {
    emit(AiState(confidence: state.confidence));
  }

  /// [_onConfigureAiEvent] applies the user's confidence threshold, pushed by
  /// [SettingsBloc] (Requirement 25.3).
  ///
  /// It lands in state and is read by the *next* parse, which is what "subsequent
  /// interactions" means — nothing already parsed is re-judged.
  FutureOr<void> _onConfigureAiEvent(
    ConfigureAiEvent event,
    Emitter<AiState> emit,
  ) {
    emit(state.copyWith(confidence: event.confidence));
  }

  FutureOr<void> _onInputChanged(
    AiInputChanged event,
    Emitter<AiState> emit,
  ) async {
    final input = event.input;

    // An empty field is the resting state: drop the preview, results and answer
    // and wait, rather than parsing nothing.
    if (input.isBlank) {
      emit(
        state.copyWith(
          input: '',
          clearTaskPreview: true,
          clearTransactionPreview: true,
          clearBookmarkPreview: true,
          clearToBuyPreview: true,
          clearWatchPreview: true,
          clearVaultPreview: true,
          clearProjectPreview: true,
          results: const [],
          answer: '',
          clarification: '',
          error: '',
        ),
      );
      return;
    }

    // Re-guess the mode unless the user has pinned one.
    final mode =
        state.isModeManual ? state.mode : repository.classifyIntent(input);

    await _emitPreview(input: input, mode: mode, emit: emit);
  }

  FutureOr<void> _onModeSelected(
    AiModeSelected event,
    Emitter<AiState> emit,
  ) async {
    // Switching mode clears the previous mode's read of the line and any results
    // or answer left from it, then re-previews the current text under the new one.
    await _emitPreview(
      input: state.input,
      mode: event.mode,
      isModeManual: true,
      emit: emit,
    );
  }

  /// [_emitPreview] re-parses the current line for the live one-line preview and
  /// emits it, leaving Search and Ask with no preview (their outcome is the
  /// results/answer a submit produces, not something to show ahead of time).
  Future<void> _emitPreview({
    required String input,
    required AiIntent mode,
    required Emitter<AiState> emit,
    bool? isModeManual,
  }) async {
    ParsedTaskIntent? taskPreview;
    ParsedTransactionIntent? transactionPreview;
    ParsedBookmarkInput? bookmarkPreview;
    ParsedToBuyInput? toBuyPreview;
    ParsedWatchInput? watchPreview;
    ParsedVaultInput? vaultPreview;
    ParsedProjectInput? projectPreview;

    if (input.isNotBlank) {
      switch (mode) {
        case AiIntent.task:
          taskPreview = await repository.parseTaskIntent(input);
        case AiIntent.expense:
          transactionPreview = await repository.parseTransactionIntent(input);
        case AiIntent.bookmark:
          bookmarkPreview = await repository.parseBookmark(input);
        case AiIntent.toBuy:
          toBuyPreview = await repository.parseToBuy(input);
        case AiIntent.watchItem:
          watchPreview = await repository.parseWatch(input);
        case AiIntent.vaultItem:
          vaultPreview = await repository.parseVault(input);
        case AiIntent.project:
          projectPreview = await repository.parseProject(input);
        case AiIntent.note:
        case AiIntent.search:
        case AiIntent.question:
          break;
      }
    }

    emit(
      state.copyWith(
        input: input,
        mode: mode,
        isModeManual: isModeManual,
        taskPreview: taskPreview,
        clearTaskPreview: taskPreview == null,
        transactionPreview: transactionPreview,
        clearTransactionPreview: transactionPreview == null,
        bookmarkPreview: bookmarkPreview,
        clearBookmarkPreview: bookmarkPreview == null,
        toBuyPreview: toBuyPreview,
        clearToBuyPreview: toBuyPreview == null,
        watchPreview: watchPreview,
        clearWatchPreview: watchPreview == null,
        vaultPreview: vaultPreview,
        clearVaultPreview: vaultPreview == null,
        projectPreview: projectPreview,
        clearProjectPreview: projectPreview == null,
        results: const [],
        answer: '',
        clarification: '',
        error: '',
      ),
    );
  }

  FutureOr<void> _onSubmitted(
    AiSubmitted event,
    Emitter<AiState> emit,
  ) async {
    final input = event.input.trim();
    if (input.isEmpty) {
      emit(state.copyWith(clarification: 'Type something for me to work with.'));
      return;
    }

    emit(
      state.copyWith(
        isBusy: true,
        error: '',
        clarification: '',
        createdMessage: '',
      ),
    );

    try {
      switch (state.mode) {
        case AiIntent.task:
          await _createTask(input, emit);
        case AiIntent.expense:
          await _createExpense(input, emit);
        case AiIntent.note:
          await _createNote(input, emit);
        case AiIntent.bookmark:
          await _createBookmark(input, emit);
        case AiIntent.toBuy:
          await _createToBuy(input, emit);
        case AiIntent.watchItem:
          await _createWatchItem(input, emit);
        case AiIntent.vaultItem:
          await _createVaultItem(input, emit);
        case AiIntent.project:
          await _createProject(input, emit);
        case AiIntent.search:
          await _runSearch(input, emit);
        case AiIntent.question:
          await _answer(input, emit);
      }
    } catch (_) {
      // Dio errors are already normalised to a failure response, so a throw here
      // is genuinely unexpected — surface it rather than swallow it (CLAUDE.md §0).
      emit(state.copyWith(isBusy: false, error: 'Something went wrong.'));
    }
  }

  Future<void> _createTask(String input, Emitter<AiState> emit) async {
    final intent = await repository.parseTaskIntent(input);

    if (!intent.isConfidentAt(state.confidence)) {
      emit(
        state.copyWith(
          isBusy: false,
          taskPreview: intent,
          clearTransactionPreview: true,
          clarification: 'What should I call this task?',
        ),
      );
      return;
    }

    final response = await tasksRepository.create(intent.toTask());

    emit(
      response.success
          ? state.copyWith(
              isBusy: false,
              createdMessage: 'Task added: ${intent.title.trim()}',
            )
          : state.copyWith(isBusy: false, error: response.message),
    );
  }

  Future<void> _createExpense(String input, Emitter<AiState> emit) async {
    final intent = await repository.parseTransactionIntent(input);

    if (!intent.isConfidentAt(state.confidence)) {
      emit(
        state.copyWith(
          isBusy: false,
          transactionPreview: intent,
          clearTaskPreview: true,
          clarification: 'How much was it?',
        ),
      );
      return;
    }

    final accountId = await _defaultAccountId();
    if (accountId == null) {
      emit(
        state.copyWith(
          isBusy: false,
          error: 'Add an account first, then I can log this.',
        ),
      );
      return;
    }

    final response = await financeRepository.createTransaction(
      intent.toTransaction(accountId: accountId),
    );

    emit(
      response.success
          ? state.copyWith(
              isBusy: false,
              createdMessage:
                  '${intent.type.label} added: '
                  '${Helpers.formatMoney(intent.amountMinor, compact: true)} '
                  '· ${intent.category}',
            )
          : state.copyWith(isBusy: false, error: response.message),
    );
  }

  Future<void> _createNote(String input, Emitter<AiState> emit) async {
    final now = DateTime.now();
    final document = Document(
      id: _uuid.v4(),
      title: _noteTitle(input),
      content: input,
      createdAt: now,
      updatedAt: now,
    );

    final response = await documentsRepository.save(document);

    emit(
      response.success
          ? state.copyWith(
              isBusy: false,
              createdMessage: 'Note saved: ${document.displayTitle}',
            )
          : state.copyWith(isBusy: false, error: response.message),
    );
  }

  Future<void> _createBookmark(String input, Emitter<AiState> emit) async {
    final parsed = await repository.parseBookmark(input);

    if (!parsed.isConfidentAt(state.confidence)) {
      emit(
        state.copyWith(
          isBusy: false,
          bookmarkPreview: parsed,
          clarification: 'What URL should I save?',
        ),
      );
      return;
    }

    final now = DateTime.now();
    final metadata = UrlMetadata.read(parsed.url);
    final bookmark = Bookmark(
      id: _uuid.v4(),
      url: parsed.url,
      title: metadata.title,
      sourceType: metadata.source,
      thumbnailUrl: metadata.thumbnailUrl,
      savedAt: now,
    );

    final response = await bookmarksRepository.create(bookmark);

    emit(
      response.success
          ? state.copyWith(
              isBusy: false,
              createdMessage: 'Bookmark saved: ${bookmark.host}',
            )
          : state.copyWith(isBusy: false, error: response.message),
    );
  }

  Future<void> _createToBuy(String input, Emitter<AiState> emit) async {
    final parsed = await repository.parseToBuy(input);

    if (!parsed.isConfidentAt(state.confidence)) {
      emit(
        state.copyWith(
          isBusy: false,
          toBuyPreview: parsed,
          clarification: 'What do you need to buy?',
        ),
      );
      return;
    }

    final now = DateTime.now();
    final item = ToBuyItem(
      id: _uuid.v4(),
      name: parsed.name,
      store: parsed.store,
      estimatedPriceMinor: parsed.estimatedPriceMinor,
      createdAt: now,
    );

    final response = await toBuyRepository.create(item);

    emit(
      response.success
          ? state.copyWith(
              isBusy: false,
              createdMessage: 'Added to buy: ${item.name}',
            )
          : state.copyWith(isBusy: false, error: response.message),
    );
  }

  Future<void> _createWatchItem(String input, Emitter<AiState> emit) async {
    final parsed = await repository.parseWatch(input);

    if (!parsed.isConfidentAt(state.confidence)) {
      emit(
        state.copyWith(
          isBusy: false,
          watchPreview: parsed,
          clarification: 'What are you watching/reading/playing?',
        ),
      );
      return;
    }

    final now = DateTime.now();
    final item = WatchlistItem(
      id: _uuid.v4(),
      title: parsed.title,
      mediaType: parsed.mediaType,
      createdAt: now,
    );

    final response = await watchlistRepository.create(item);

    emit(
      response.success
          ? state.copyWith(
              isBusy: false,
              createdMessage:
                  'Added to ${parsed.mediaType.label.toLowerCase()} watchlist: '
                  '${item.title}',
            )
          : state.copyWith(isBusy: false, error: response.message),
    );
  }

  Future<void> _createVaultItem(String input, Emitter<AiState> emit) async {
    // Vault items require encryption through the vault service, which is behind
    // the vault's own authentication. The AI cannot create encrypted items
    // directly — the user must add them through the vault screen.
    emit(
      state.copyWith(
        isBusy: false,
        clarification:
            'Vault items need to be added through the Vault screen for '
            'security. Open the Vault to add this.',
      ),
    );
  }

  Future<void> _createProject(String input, Emitter<AiState> emit) async {
    final parsed = await repository.parseProject(input);

    if (!parsed.isConfidentAt(state.confidence)) {
      emit(
        state.copyWith(
          isBusy: false,
          projectPreview: parsed,
          clarification: 'What should the project be called?',
        ),
      );
      return;
    }

    final now = DateTime.now();
    final project = Project(
      id: _uuid.v4(),
      name: parsed.name,
      description: parsed.description,
      createdAt: now,
      updatedAt: now,
    );

    final response = await projectsRepository.create(project);

    emit(
      response.success
          ? state.copyWith(
              isBusy: false,
              createdMessage: 'Project created: ${project.name}',
            )
          : state.copyWith(isBusy: false, error: response.message),
    );
  }

  Future<void> _runSearch(String input, Emitter<AiState> emit) async {
    final results = await repository.searchWithAI(input);
    emit(state.copyWith(isBusy: false, results: results, answer: ''));
  }

  Future<void> _answer(String input, Emitter<AiState> emit) async {
    final answer = await repository.answerQuestion(input);
    emit(state.copyWith(isBusy: false, answer: answer, results: const []));
  }

  /// [_defaultAccountId] is the first account a spend can be filed under, or null
  /// when the user has none — which the caller turns into a prompt to add one.
  Future<String?> _defaultAccountId() async {
    final accounts = await financeRepository.watchAccounts().first;
    for (final account in accounts) {
      if (!account.isArchived) return account.id;
    }
    return null;
  }

  /// [_noteTitle] is the note's first line, capped so a long first paragraph does
  /// not become the title. The body keeps the whole text regardless.
  static String _noteTitle(String input) {
    final firstLine = input.trim().split('\n').first.trim();
    if (firstLine.length <= 60) return firstLine;
    return '${firstLine.substring(0, 57).trimRight()}…';
  }
}
