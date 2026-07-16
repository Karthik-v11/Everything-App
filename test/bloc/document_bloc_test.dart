import 'package:bloc_test/bloc_test.dart';
import 'package:everything_app/bloc/document/document_bloc.dart';
import 'package:everything_app/data/models/document.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/repositories/documents_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Property 12 — Document auto-save preserves content.
///
/// The one thing that must hold about the editor: what a save writes is
/// *structurally equal* to the live buffer at the instant it fires — no content
/// lost, none silently reshaped (no defaulted title, no trimmed body). The bloc
/// snapshots [DocumentState.title]/[DocumentState.content] verbatim, so this is
/// asserted against the document the fake repository is actually handed, not a
/// round-trip that would pass on any implementation that stored *something*.
void main() {
  late _FakeDocumentsRepository repository;

  setUp(() {
    repository = _FakeDocumentsRepository();
  });

  DocumentBloc build() => DocumentBloc(repository: repository);

  const id = 'doc-1';

  // Content chosen to catch mutation: leading/trailing whitespace the bloc must
  // not trim, and Markdown the plain-text export would strip but the store must
  // keep.
  const typed = '  # Heading\n\n- [ ] a task\n\n**bold** and `code`  ';

  blocTest<DocumentBloc, DocumentState>(
    'auto-save writes the live content and title byte-for-byte (Property 12)',
    build: build,
    act: (bloc) => bloc
      ..add(const LoadDocumentEvent(documentId: id, projectId: 'project-1'))
      ..add(const ChangeDocumentTitleEvent(title: 'My notes'))
      ..add(const ChangeDocumentContentEvent(content: typed))
      ..add(const SaveDocumentEvent(isAuto: true)),
    verify: (bloc) {
      final saved = repository.saved.single;
      // The snapshot equals the in-memory state at trigger time.
      expect(saved.content, typed);
      expect(saved.content, bloc.state.content);
      expect(saved.title, 'My notes');
      expect(saved.title, bloc.state.title);
      // A new document keeps the id it opened at and is filed under its project.
      expect(saved.id, id);
      expect(saved.projectId, 'project-1');
      // The write clears the dirty flag and records when it happened.
      expect(bloc.state.isDirty, isFalse);
      expect(bloc.state.lastSavedAt, isNotNull);
    },
  );

  blocTest<DocumentBloc, DocumentState>(
    'a clean editor writes nothing — the 30s tick is a no-op when unchanged',
    build: build,
    act: (bloc) => bloc
      ..add(const LoadDocumentEvent(documentId: id))
      ..add(const SaveDocumentEvent(isAuto: true)),
    verify: (_) => expect(repository.saved, isEmpty),
  );

  blocTest<DocumentBloc, DocumentState>(
    'an untouched blank document is never persisted',
    build: build,
    act: (bloc) => bloc
      ..add(const LoadDocumentEvent(documentId: id))
      // Whitespace-only content leaves nothing worth a row behind.
      ..add(const ChangeDocumentContentEvent(content: '   '))
      ..add(const SaveDocumentEvent(isAuto: true)),
    verify: (_) => expect(repository.saved, isEmpty),
  );

  blocTest<DocumentBloc, DocumentState>(
    'only the auto-save stamps lastAutoSavedAt; a manual save leaves it',
    build: build,
    act: (bloc) => bloc
      ..add(const LoadDocumentEvent(documentId: id))
      ..add(const ChangeDocumentContentEvent(content: 'body'))
      ..add(const SaveDocumentEvent()),
    verify: (_) {
      final saved = repository.saved.single;
      expect(saved.content, 'body');
      expect(saved.lastAutoSavedAt, isNull);
    },
  );

  blocTest<DocumentBloc, DocumentState>(
    'resuming an existing document loads its stored content, not a blank one',
    build: build,
    setUp: () => repository.existing = Document(
      id: id,
      title: 'Existing',
      content: 'stored body',
      projectId: 'project-1',
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    ),
    act: (bloc) => bloc.add(const LoadDocumentEvent(documentId: id)),
    verify: (bloc) {
      expect(bloc.state.title, 'Existing');
      expect(bloc.state.content, 'stored body');
      expect(bloc.state.isDirty, isFalse);
    },
  );
}

/// [_FakeDocumentsRepository] records every document it is asked to save and can
/// be primed with one existing document for a resume.
class _FakeDocumentsRepository implements DocumentsRepository {
  final List<Document> saved = [];
  Document? existing;

  @override
  Future<JsonResponse> save(Document document) async {
    saved.add(document);
    return JsonResponse.success(message: 'Saved.', data: document);
  }

  @override
  Future<JsonResponse> findById(String id) async => JsonResponse.success(
        message: 'Loaded.',
        data: existing,
      );

  @override
  Future<JsonResponse> delete(String id) async =>
      JsonResponse.success(message: 'Deleted.');

  @override
  Stream<List<Document>> watchAll() => const Stream.empty();
}
