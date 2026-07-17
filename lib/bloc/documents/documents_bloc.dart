import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/models/document.dart';
import 'package:everything_app/data/repositories/documents_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'documents_event.dart';
part 'documents_state.dart';

/// [DocumentsBloc] owns the list of documents (Requirement 11).
///
/// It streams every document and screens filter it ([documentsForProject]), so a
/// document saved in the editor refreshes the project screen behind it with no
/// reload.
///
/// Editing a single document belongs to [DocumentBloc], so a save failure in the
/// editor never puts an error on the state the list renders from.
class DocumentsBloc extends Bloc<DocumentsEvent, DocumentsState> {
  DocumentsBloc({required this.repository}) : super(const DocumentsState()) {
    on<WatchDocumentsEvent>(_onWatchDocumentsEvent);
    on<SearchDocumentsEvent>(_onSearchDocumentsEvent);
    on<DeleteDocumentEvent>(_onDeleteDocumentEvent);
  }

  final DocumentsRepository repository;

  FutureOr<void> _onWatchDocumentsEvent(
    WatchDocumentsEvent event,
    Emitter<DocumentsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: '', message: ''));

    await emit.forEach<List<Document>>(
      repository.watchAll(),
      onData: (documents) =>
          state.copyWith(isLoading: false, documents: documents, error: ''),
      onError: (_, _) => state.copyWith(
        isLoading: false,
        error: 'Could not load your documents.',
      ),
    );
  }

  FutureOr<void> _onSearchDocumentsEvent(
    SearchDocumentsEvent event,
    Emitter<DocumentsState> emit,
  ) {
    emit(state.copyWith(query: event.query));
  }

  FutureOr<void> _onDeleteDocumentEvent(
    DeleteDocumentEvent event,
    Emitter<DocumentsState> emit,
  ) async {
    try {
      final response = await repository.delete(event.document.id);

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not delete the document.'));
    }
  }
}
