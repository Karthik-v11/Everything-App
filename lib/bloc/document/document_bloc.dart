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
/// Style A: it accumulates the live title, body, editor/preview mode and dirty
/// flag across many keystroke events. The list of documents lives in
/// [DocumentsBloc]; this bloc owns exactly the one open in the editor.
///
/// **Auto-save.** Requirement 11.2 asks for a save every 30 seconds. A periodic
/// timer, started on load, dispatches [SaveDocumentEvent] on each tick; the
/// handler writes only when the document is dirty, so an idle editor makes no
/// writes. The saved snapshot is built from the live state at the instant the
/// save fires and is written unchanged — no defaulting of an empty title, no
/// trimming — so the stored content is structurally equal to what was on screen
/// (Property 12).
///
/// The document carries a stable id from the moment it opens — minted here for a
/// new document — so a create and an update take the same upsert and the
/// auto-save never has to tell them apart.
///
/// Events:
/// 1) [LoadDocumentEvent] — open a document by id, or start a new one.
/// 2) [ChangeDocumentTitleEvent] / [ChangeDocumentContentEvent] — live edits.
/// 3) [TogglePreviewEvent] — switch between the editor and the rendered preview.
/// 4) [SaveDocumentEvent] — persist the current state (auto or manual).
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

  /// The auto-save clock (Requirement 11.2). Held so it can be cancelled when the
  /// editor is torn down or a different document is loaded — a stray timer firing
  /// after close would try to emit on a closed bloc.
  Timer? _autoSaveTimer;

  /// [autoSaveInterval] is exposed so a test can drive the cadence explicitly
  /// rather than waiting 30 real seconds.
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
              // A new document opened at this id. `createdAt` is stamped now so
              // the first auto-save writes a complete row.
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
  /// It no-ops when nothing has changed since the last write, and when the
  /// document is still empty — an untouched editor should not leave a blank row
  /// behind. Otherwise it snapshots the live title and body *exactly* and upserts
  /// them (Property 12).
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
