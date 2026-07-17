import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:everything_app/data/database/app_database.dart';

/// [AttachmentOwner] is what an attachment hangs off.
///
/// The `attachments` table is polymorphic — `ownerType` + `ownerId` — so this
/// enum is the closed set of legal `ownerType` values. A raw string would let a
/// typo file an attachment against an owner nothing ever queries.
///
/// Only [project] is written today (Requirement 12.2); the other three are what
/// the column was designed for.
enum AttachmentOwner {
  task,
  transaction,
  project,
  document;

  static AttachmentOwner fromName(String? name) =>
      AttachmentOwner.values.firstWhere(
        (value) => value.name == name,
        orElse: () => AttachmentOwner.project,
      );
}

/// [Attachment] is a file stored alongside an owner (Requirement 12.2).
///
/// [filePath] points at a copy inside the app's own documents directory, never at
/// the path the OS handed the share intent — see `AttachmentsService.attach` for
/// why that distinction is the whole point of this type.
class Attachment extends Equatable {
  const Attachment({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.filePath,
    required this.fileName,
    required this.createdAt,
    this.mimeType,
    this.sizeBytes,
  });

  final String id;
  final AttachmentOwner ownerType;
  final String ownerId;
  final String filePath;
  final String fileName;
  final String? mimeType;
  final int? sizeBytes;
  final DateTime createdAt;

  factory Attachment.fromEntry(AttachmentEntry entry) => Attachment(
        id: entry.id,
        ownerType: AttachmentOwner.fromName(entry.ownerType),
        ownerId: entry.ownerId,
        filePath: entry.filePath,
        fileName: entry.fileName,
        mimeType: entry.mimeType,
        sizeBytes: entry.sizeBytes,
        createdAt: entry.createdAt,
      );

  AttachmentsTableCompanion toCompanion() => AttachmentsTableCompanion.insert(
        id: id,
        ownerType: ownerType.name,
        ownerId: ownerId,
        filePath: filePath,
        fileName: fileName,
        mimeType: Value(mimeType),
        sizeBytes: Value(sizeBytes),
        createdAt: createdAt,
      );

  Attachment copyWith({
    String? id,
    AttachmentOwner? ownerType,
    String? ownerId,
    String? filePath,
    String? fileName,
    String? mimeType,
    int? sizeBytes,
    DateTime? createdAt,
  }) =>
      Attachment(
        id: id ?? this.id,
        ownerType: ownerType ?? this.ownerType,
        ownerId: ownerId ?? this.ownerId,
        filePath: filePath ?? this.filePath,
        fileName: fileName ?? this.fileName,
        mimeType: mimeType ?? this.mimeType,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  List<Object?> get props => [
        id,
        ownerType,
        ownerId,
        filePath,
        fileName,
        mimeType,
        sizeBytes,
        createdAt,
      ];
}
