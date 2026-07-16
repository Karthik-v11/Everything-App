part of 'ai_bloc.dart';

/// [AiState] is everything the AI sheet renders (Requirement 16).
///
/// Style A: it accumulates several independent slices — the chosen mode, the live
/// preview of what will be created, search results, an answer — that different
/// events touch separately, and it holds them for the life of the open sheet. It
/// is not persisted: an assistant session starts fresh each time the dock is
/// opened, which is what [AiOpened] resets it to.
class AiState extends Equatable {
  const AiState({
    this.mode = AiIntent.task,
    this.input = '',
    this.isModeManual = false,
    this.isBusy = false,
    this.error = '',
    this.clarification = '',
    this.taskPreview,
    this.transactionPreview,
    this.bookmarkPreview,
    this.toBuyPreview,
    this.watchPreview,
    this.vaultPreview,
    this.projectPreview,
    this.results = const <SearchResult>[],
    this.answer = '',
    this.createdMessage = '',
    this.confidence = kAiConfidenceThreshold,
  });

  /// The active mode — the branch a submit runs. Preselected by [classifyIntent]
  /// until the user picks one, after which [isModeManual] keeps their choice from
  /// being overridden by the next keystroke.
  final AiIntent mode;
  final String input;
  final bool isModeManual;

  /// True while an action is in flight, which disables the send button.
  final bool isBusy;

  /// A transient failure, shown as an error snack and cleared at the next action.
  final String error;

  /// A gentle prompt shown inline when the parse was too weak to act on —
  /// "What should I call this task?" (Requirement 16.7). Not an error: nothing has
  /// gone wrong, the assistant just needs one more word.
  final String clarification;

  /// The live reading of the input in Task / Expense mode, shown as a one-line
  /// preview so the user sees what will be created before they commit.
  final ParsedTaskIntent? taskPreview;
  final ParsedTransactionIntent? transactionPreview;

  /// Preview fields for library intents.
  final ParsedBookmarkInput? bookmarkPreview;
  final ParsedToBuyInput? toBuyPreview;
  final ParsedWatchInput? watchPreview;
  final ParsedVaultInput? vaultPreview;
  final ParsedProjectInput? projectPreview;

  /// Search results (Search mode) and the answer text (Ask mode) — the two
  /// read-only outcomes the sheet keeps on screen rather than closing on.
  final List<SearchResult> results;
  final String answer;

  /// Set the moment a create succeeds; the sheet snacks it and closes. Cleared
  /// when the sheet reopens ([AiOpened]).
  final String createdMessage;

  /// The score a parse must reach before the assistant acts rather than asks
  /// (Requirements 16.7, 25.3).
  ///
  /// Owned and persisted by [SettingsBloc], pushed here by
  /// [ConfigureAiEvent], and read on the *next* parse — which is what makes a
  /// changed setting apply to subsequent interactions without the sheet needing
  /// to be reopened. It survives [AiOpened], unlike everything else here: it is
  /// the user's setting, not part of a session.
  final double confidence;

  bool get hasResults => results.isNotEmpty;

  bool get hasAnswer => answer.isNotBlank;

  AiState copyWith({
    AiIntent? mode,
    String? input,
    bool? isModeManual,
    bool? isBusy,
    String? error,
    String? clarification,
    ParsedTaskIntent? taskPreview,
    bool clearTaskPreview = false,
    ParsedTransactionIntent? transactionPreview,
    bool clearTransactionPreview = false,
    ParsedBookmarkInput? bookmarkPreview,
    bool clearBookmarkPreview = false,
    ParsedToBuyInput? toBuyPreview,
    bool clearToBuyPreview = false,
    ParsedWatchInput? watchPreview,
    bool clearWatchPreview = false,
    ParsedVaultInput? vaultPreview,
    bool clearVaultPreview = false,
    ParsedProjectInput? projectPreview,
    bool clearProjectPreview = false,
    List<SearchResult>? results,
    String? answer,
    String? createdMessage,
    double? confidence,
  }) =>
      AiState(
        mode: mode ?? this.mode,
        input: input ?? this.input,
        isModeManual: isModeManual ?? this.isModeManual,
        isBusy: isBusy ?? this.isBusy,
        error: error ?? this.error,
        clarification: clarification ?? this.clarification,
        taskPreview: clearTaskPreview ? null : (taskPreview ?? this.taskPreview),
        transactionPreview: clearTransactionPreview
            ? null
            : (transactionPreview ?? this.transactionPreview),
        bookmarkPreview:
            clearBookmarkPreview ? null : (bookmarkPreview ?? this.bookmarkPreview),
        toBuyPreview:
            clearToBuyPreview ? null : (toBuyPreview ?? this.toBuyPreview),
        watchPreview:
            clearWatchPreview ? null : (watchPreview ?? this.watchPreview),
        vaultPreview:
            clearVaultPreview ? null : (vaultPreview ?? this.vaultPreview),
        projectPreview:
            clearProjectPreview ? null : (projectPreview ?? this.projectPreview),
        results: results ?? this.results,
        answer: answer ?? this.answer,
        createdMessage: createdMessage ?? this.createdMessage,
        confidence: confidence ?? this.confidence,
      );

  @override
  List<Object?> get props => [
        mode,
        input,
        isModeManual,
        isBusy,
        error,
        clarification,
        taskPreview,
        transactionPreview,
        bookmarkPreview,
        toBuyPreview,
        watchPreview,
        vaultPreview,
        projectPreview,
        results,
        answer,
        createdMessage,
        confidence,
      ];
}
