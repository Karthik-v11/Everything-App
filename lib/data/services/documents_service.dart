import 'package:everything_app/data/database/daos/documents_dao.dart';
import 'package:everything_app/data/models/document.dart';
import 'package:everything_app/data/models/json_response.dart';

/// [DocumentsService] is the Document Writer's persistence layer
/// (Requirement 11).
class DocumentsService {
  DocumentsService({required this.dao});

  final DocumentsDao dao;

  Stream<List<Document>> watchAll() =>
      dao.watchAll().map((rows) => rows.map(Document.fromEntry).toList());

  /// [findById] returns the document, or a success with `null` data when the id
  /// is unknown — which is how the editor tells a document it is opening for the
  /// first time from one it is resuming.
  Future<JsonResponse> findById(String id) async {
    try {
      final entry = await dao.findById(id);
      return JsonResponse.success(
        message: 'Loaded successfully.',
        data: entry == null ? null : Document.fromEntry(entry),
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not open the document.',
      );
    }
  }

  /// [save] writes a document, creating or updating it (Requirement 11.2).
  ///
  /// A plain upsert: the id is stable from the moment the editor opens, so the
  /// auto-save never has to decide whether the document is new or resumed.
  Future<JsonResponse> save(Document document) async {
    try {
      await dao.upsert(document.toCompanion());
      return JsonResponse.success(message: 'Saved.', data: document);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not save the document.',
      );
    }
  }

  Future<JsonResponse> delete(String id) async {
    try {
      await dao.deleteById(id);
      return JsonResponse.success(message: 'Document deleted.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not delete the document.',
      );
    }
  }
}
