part of 'documents_bloc.dart';

/// [DocumentsEvent] is the base class for every Documents list event.
abstract class DocumentsEvent extends Equatable {
  const DocumentsEvent();

  @override
  List<Object?> get props => [];
}

/// [WatchDocumentsEvent] subscribes to the documents. Fired once.
class WatchDocumentsEvent extends DocumentsEvent {
  const WatchDocumentsEvent();
}

/// [SearchDocumentsEvent] is the in-module search.
class SearchDocumentsEvent extends DocumentsEvent {
  const SearchDocumentsEvent({required this.query});

  final String query;

  @override
  List<Object?> get props => [query];
}

/// [DeleteDocumentEvent] removes a document.
class DeleteDocumentEvent extends DocumentsEvent {
  const DeleteDocumentEvent({required this.document});

  final Document document;

  @override
  List<Object?> get props => [document];
}
