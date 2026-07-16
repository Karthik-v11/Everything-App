part of 'document_bloc.dart';

/// [DocumentEvent] is the base class for every editor event.
abstract class DocumentEvent extends Equatable {
  const DocumentEvent();

  @override
  List<Object?> get props => [];
}

/// [LoadDocumentEvent] opens the document at [documentId], or starts a new one
/// there when the id is not yet in the database.
///
/// [projectId] files a *new* document under its project (Requirement 10.1); it is
/// ignored when the document already exists, whose parent is already recorded.
class LoadDocumentEvent extends DocumentEvent {
  const LoadDocumentEvent({required this.documentId, this.projectId});

  final String documentId;
  final String? projectId;

  @override
  List<Object?> get props => [documentId, projectId];
}

/// [ChangeDocumentTitleEvent] records a live title edit.
class ChangeDocumentTitleEvent extends DocumentEvent {
  const ChangeDocumentTitleEvent({required this.title});

  final String title;

  @override
  List<Object?> get props => [title];
}

/// [ChangeDocumentContentEvent] records a live body edit.
class ChangeDocumentContentEvent extends DocumentEvent {
  const ChangeDocumentContentEvent({required this.content});

  final String content;

  @override
  List<Object?> get props => [content];
}

/// [TogglePreviewEvent] switches between the Markdown editor and its rendered
/// preview (Requirement 11.5).
class TogglePreviewEvent extends DocumentEvent {
  const TogglePreviewEvent();
}

/// [SaveDocumentEvent] persists the current state (Requirement 11.2).
///
/// [isAuto] distinguishes the 30-second timer's save from a manual one, so only
/// the timer stamps [Document.lastAutoSavedAt]. The write itself is identical.
class SaveDocumentEvent extends DocumentEvent {
  const SaveDocumentEvent({this.isAuto = false});

  final bool isAuto;

  @override
  List<Object?> get props => [isAuto];
}
