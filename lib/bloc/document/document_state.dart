part of 'document_bloc.dart';

/// [DocumentState] is the live editor state (Requirement 11).
///
/// [document] is the last persisted form — its id, project and timestamps. [title]
/// and [content] are the *live* values, which diverge from [document] as the user
/// types and are what a save snapshots. [isDirty] is that divergence: true once an
/// edit lands, false again once it is written.
class DocumentState extends Equatable {
  const DocumentState({
    this.isLoading = false,
    this.error = '',
    this.document,
    this.title = '',
    this.content = '',
    this.isPreview = false,
    this.isSaving = false,
    this.isDirty = false,
    this.lastSavedAt,
  });

  final bool isLoading;
  final String error;

  /// The last persisted document, or null before the editor has loaded.
  final Document? document;

  final String title;
  final String content;
  final bool isPreview;
  final bool isSaving;

  /// Whether [title]/[content] have unsaved changes.
  final bool isDirty;

  /// When the document was last written, or null for an unsaved new document.
  final DateTime? lastSavedAt;

  bool get isReady => document != null;

  DocumentState copyWith({
    bool? isLoading,
    String? error,
    Document? document,
    String? title,
    String? content,
    bool? isPreview,
    bool? isSaving,
    bool? isDirty,
    DateTime? lastSavedAt,
  }) =>
      DocumentState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        document: document ?? this.document,
        title: title ?? this.title,
        content: content ?? this.content,
        isPreview: isPreview ?? this.isPreview,
        isSaving: isSaving ?? this.isSaving,
        isDirty: isDirty ?? this.isDirty,
        lastSavedAt: lastSavedAt ?? this.lastSavedAt,
      );

  @override
  List<Object?> get props => [
        isLoading,
        error,
        document,
        title,
        content,
        isPreview,
        isSaving,
        isDirty,
        lastSavedAt,
      ];
}
