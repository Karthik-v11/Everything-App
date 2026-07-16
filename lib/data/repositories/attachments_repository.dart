import 'package:everything_app/data/models/attachment.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/services/attachments_service.dart';

/// [AttachmentsRepository] is the contract for files stored against an owner
/// (Requirement 12.2).
abstract class AttachmentsRepository {
  /// [watchFor] streams one owner's attachments, newest first.
  Stream<List<Attachment>> watchFor({
    required AttachmentOwner ownerType,
    required String ownerId,
  });

  /// [attach] copies a file into the app's own storage and records it.
  ///
  /// [sourcePath] may point into OS-owned temporary storage; the copy is what
  /// makes the attachment outlive it.
  Future<JsonResponse> attach({
    required AttachmentOwner ownerType,
    required String ownerId,
    required String sourcePath,
    required String fileName,
    String? mimeType,
    DateTime? now,
  });

  /// [delete] removes the attachment and the file it points at.
  Future<JsonResponse> delete(String id);

  /// [totalSizeBytes] is what every attachment occupies (Requirement 25.4).
  Future<JsonResponse> totalSizeBytes();
}

class AttachmentsRepositoryImpl implements AttachmentsRepository {
  const AttachmentsRepositoryImpl({required this.attachmentsService});

  final AttachmentsService attachmentsService;

  @override
  Stream<List<Attachment>> watchFor({
    required AttachmentOwner ownerType,
    required String ownerId,
  }) =>
      attachmentsService.watchFor(ownerType: ownerType, ownerId: ownerId);

  @override
  Future<JsonResponse> attach({
    required AttachmentOwner ownerType,
    required String ownerId,
    required String sourcePath,
    required String fileName,
    String? mimeType,
    DateTime? now,
  }) =>
      attachmentsService.attach(
        ownerType: ownerType,
        ownerId: ownerId,
        sourcePath: sourcePath,
        fileName: fileName,
        mimeType: mimeType,
        now: now,
      );

  @override
  Future<JsonResponse> delete(String id) => attachmentsService.delete(id);

  @override
  Future<JsonResponse> totalSizeBytes() => attachmentsService.totalSizeBytes();
}
