part of 'documents_bloc.dart';

/// [DocumentsState] holds the document list the Library and project screens
/// render.
class DocumentsState extends Equatable {
  const DocumentsState({
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.documents = const <Document>[],
    this.query = '',
  });

  final bool isLoading;
  final String error;
  final String message;
  final List<Document> documents;
  final String query;

  /// [documentsForProject] are the documents filed under one project
  /// (Requirement 10.1), newest edit first — the order the stream already
  /// arrives in.
  List<Document> documentsForProject(String projectId) => [
        for (final document in documents)
          if (document.projectId == projectId) document,
      ];

  /// [visibleDocuments] is every document matching the search query.
  List<Document> get visibleDocuments => [
        for (final document in documents)
          if (document.matches(query)) document,
      ];

  bool get isFiltered => query.isNotBlank;

  DocumentsState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    List<Document>? documents,
    String? query,
  }) =>
      DocumentsState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        documents: documents ?? this.documents,
        query: query ?? this.query,
      );

  @override
  List<Object?> get props => [isLoading, error, message, documents, query];
}
