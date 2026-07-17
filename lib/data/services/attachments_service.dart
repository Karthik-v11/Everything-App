import 'dart:io';

import 'package:everything_app/data/database/daos/attachments_dao.dart';
import 'package:everything_app/data/models/attachment.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// [AttachmentsService] stores files attached to an owner (Requirement 12.2).
///
/// [attachmentsDirectoryOverride] is a test seam:
/// `getApplicationDocumentsDirectory` needs a platform channel, so a test hands
/// a temp directory instead.
class AttachmentsService {
  AttachmentsService({required this.dao, this.attachmentsDirectoryOverride});

  final AttachmentsDao dao;
  final String? attachmentsDirectoryOverride;

  static const Uuid _uuid = Uuid();

  Stream<List<Attachment>> watchFor({
    required AttachmentOwner ownerType,
    required String ownerId,
  }) =>
      dao
          .watchFor(ownerType: ownerType.name, ownerId: ownerId)
          .map((rows) => rows.map(Attachment.fromEntry).toList());

  /// [attach] copies [sourcePath] into the app's own storage and records it.
  ///
  /// The copy is the point: a share intent hands over a path into a temporary
  /// staging area (Android's `content://` cache, iOS's share-extension container)
  /// that the OS may delete once the share is over, so recording the path yields
  /// an attachment that looks saved and is a dead link by tomorrow.
  ///
  /// The row is written only after the bytes land, so an attachment in the
  /// database always has its file on disk. The reverse — a copied file with no
  /// row, if the insert fails — is left alone: an orphaned file rather than a
  /// broken link, and the storage section counts it.
  Future<JsonResponse> attach({
    required AttachmentOwner ownerType,
    required String ownerId,
    required String sourcePath,
    required String fileName,
    String? mimeType,
    DateTime? now,
  }) async {
    try {
      final source = File(sourcePath);
      if (!source.existsSync()) {
        return JsonResponse.failure(
          statusCode: 404,
          message: 'Error: that file is no longer available.',
        );
      }

      final id = _uuid.v4();
      final directory = Directory(await _attachmentsDirectory());
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }

      // Named by id: two shares of "IMG_0001.jpg" must not overwrite each other,
      // and a name from another app is not one to trust as a path component. The
      // original name is kept in the row and is what the UI shows.
      final destination = '${directory.path}${Platform.pathSeparator}$id'
          '${_extensionOf(fileName)}';

      final copied = await source.copy(destination);

      final attachment = Attachment(
        id: id,
        ownerType: ownerType,
        ownerId: ownerId,
        filePath: copied.path,
        fileName: fileName,
        mimeType: mimeType,
        sizeBytes: await copied.length(),
        createdAt: now ?? DateTime.now(),
      );

      await dao.upsert(attachment.toCompanion());

      return JsonResponse.success(message: 'Attached.', data: attachment);
    } on FileSystemException {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not copy that file.',
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not attach that file.',
      );
    }
  }

  /// [delete] removes the row and the file it points at.
  ///
  /// The row goes first: a file with no row is dead weight the storage count
  /// still reports, while a row whose file is gone is a broken link nothing can
  /// fix. An already-vanished file is not an error — the row going is the ask.
  Future<JsonResponse> delete(String id) async {
    try {
      final entry = await dao.findById(id);
      if (entry == null) {
        return JsonResponse.success(message: 'Attachment deleted.');
      }

      await dao.deleteById(id);

      final file = File(entry.filePath);
      if (file.existsSync()) await file.delete();

      return JsonResponse.success(message: 'Attachment deleted.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not delete that attachment.',
      );
    }
  }

  /// [totalSizeBytes] is what attachments occupy, for Requirement 25.4.
  Future<JsonResponse> totalSizeBytes() async {
    try {
      return JsonResponse.success(
        message: 'Loaded successfully.',
        data: await dao.totalSizeBytes(),
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not measure attachment storage.',
      );
    }
  }

  Future<String> _attachmentsDirectory() async {
    final override = attachmentsDirectoryOverride;
    if (override != null) return override;

    final documents = await getApplicationDocumentsDirectory();
    return '${documents.path}${Platform.pathSeparator}attachments';
  }

  /// [_extensionOf] keeps the original extension on the stored copy, so the OS
  /// can still pick a viewer for it when it is opened.
  static String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return '';

    final extension = fileName.substring(dot);
    // An "extension" with a separator in it is a path, not a suffix.
    return extension.contains('/') || extension.contains(r'$') ? '' : extension;
  }
}
