import 'package:everything_app/data/models/document.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/services/documents_service.dart';

/// [DocumentsRepository] defines the contract for the Document Writer
/// (Requirement 11).
abstract class DocumentsRepository {
  /// [watchAll] streams every document; screens filter it by project id.
  Stream<List<Document>> watchAll();

  /// [findById] loads one document, or a success with `null` data when the id is
  /// not yet in the database.
  Future<JsonResponse> findById(String id);

  /// [save] creates or updates a document (Requirement 11.2).
  Future<JsonResponse> save(Document document);

  /// [delete] removes a document.
  Future<JsonResponse> delete(String id);
}

class DocumentsRepositoryImpl implements DocumentsRepository {
  const DocumentsRepositoryImpl({required this.documentsService});

  final DocumentsService documentsService;

  @override
  Stream<List<Document>> watchAll() => documentsService.watchAll();

  @override
  Future<JsonResponse> findById(String id) => documentsService.findById(id);

  @override
  Future<JsonResponse> save(Document document) =>
      documentsService.save(document);

  @override
  Future<JsonResponse> delete(String id) => documentsService.delete(id);
}
