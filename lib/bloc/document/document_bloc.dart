import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/models/document.dart';
import 'package:everything_app/data/repositories/documents_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

part 'document_event.dart';
part 'document_state.dart';

/// [DocumentBloc] is the editor for a single document (Requirement 11).
///
/// The list of documents lives in [DocumentsBloc]; this bloc owns exactly the one
/// open in the editor.
///
/// Auto-save (Requirement 11.2): a periodic timer started on load dispatches
/// [SaveDocumentEvent]; the handler writes only when dirty, so an idle editor makes
/// no writes. The snapshot is written unchanged — no defaulting or trimming — so the
/// stored content is structurally equal to what was on screen (Property 12).
///
/// The document carries a stable id from the moment it opens, minted here when new,
/// so create and update take the same upsert and auto-save never tells them apart.
class DocumentBloc extends Bloc<DocumentEvent, DocumentState> {
  DocumentBloc({required this.repository}) : super(const DocumentState()) {
    on<LoadDocumentEvent>(_onLoadDocumentEvent);
    on<ChangeDocumentTitleEvent>(_onChangeDocumentTitleEvent);
    on<ChangeDocumentContentEvent>(_onChangeDocumentContentEvent);
    on<TogglePreviewEvent>(_onTogglePreviewEvent);
    on<SaveDocumentEvent>(_onSaveDocumentEvent);
  }

  final DocumentsRepository repository;

  static const Uuid _uuid = Uuid();

  /// The auto-save clock (Requirement 11.2). Held so it can be cancelled on close or
  /// reload — a stray tick would try to emit on a closed bloc.
  Timer? _autoSaveTimer;

  /// Exposed so a test can drive the cadence rather than waiting 30 real seconds.
  static const Duration autoSaveInterval = Duration(seconds: 30);

  FutureOr<void> _onLoadDocumentEvent(
    LoadDocumentEvent event,
    Emitter<DocumentState> emit,
  ) async {
    emit(const DocumentState(isLoading: true));

    try {
      final response = await repository.findById(event.documentId);
      final existing = response.data;

      final document = existing is Document
          ? existing
          : Document(
              // `createdAt` is stamped now so the first auto-save writes a
              // complete row.
              id: event.documentId.isBlank ? _uuid.v4() : event.documentId,
              title: '',
              content: '',
              projectId: event.projectId,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );

      emit(
        DocumentState(
          document: document,
          title: document.title,
          content: document.content,
          lastSavedAt: existing is Document ? document.updatedAt : null,
        ),
      );

      _startAutoSave();
    } on Exception {
      emit(const DocumentState(error: 'Could not open the document.'));
    }
  }

  FutureOr<void> _onChangeDocumentTitleEvent(
    ChangeDocumentTitleEvent event,
    Emitter<DocumentState> emit,
  ) {
    emit(state.copyWith(title: event.title, isDirty: true));
  }

  FutureOr<void> _onChangeDocumentContentEvent(
    ChangeDocumentContentEvent event,
    Emitter<DocumentState> emit,
  ) {
    emit(state.copyWith(content: event.content, isDirty: true));
  }

  FutureOr<void> _onTogglePreviewEvent(
    TogglePreviewEvent event,
    Emitter<DocumentState> emit,
  ) {
    emit(state.copyWith(isPreview: !state.isPreview));
  }

  /// [_onSaveDocumentEvent] writes the current state (Requirement 11.2).
  ///
  /// No-ops when nothing changed, and when the document is still empty — an
  /// untouched editor should not leave a blank row behind. Otherwise it snapshots
  /// the live title and body exactly and upserts them (Property 12).
  FutureOr<void> _onSaveDocumentEvent(
    SaveDocumentEvent event,
    Emitter<DocumentState> emit,
  ) async {
    final document = state.document;
    if (document == null) return;
    if (!state.isDirty) return;
    if (state.title.isBlank && state.content.isBlank) return;

    final now = DateTime.now();
    final snapshot = document.copyWith(
      title: state.title,
      content: state.content,
      updatedAt: now,
      lastAutoSavedAt: event.isAuto ? now : document.lastAutoSavedAt,
    );

    emit(state.copyWith(isSaving: true, error: ''));

    try {
      final response = await repository.save(snapshot);

      if (response.success) {
        emit(
          state.copyWith(
            document: snapshot,
            isSaving: false,
            isDirty: false,
            lastSavedAt: now,
          ),
        );
      } else {
        emit(state.copyWith(isSaving: false, error: response.message));
      }
    } on Exception {
      emit(state.copyWith(isSaving: false, error: 'Could not save.'));
    }
  }

  void _startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(
      autoSaveInterval,
      (_) => add(const SaveDocumentEvent(isAuto: true)),
    );
  }

  @override
  Future<void> close() {
    _autoSaveTimer?.cancel();
    return super.close();
  }
}
