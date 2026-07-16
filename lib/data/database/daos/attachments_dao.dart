import 'package:drift/drift.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/database/tables/tables.dart';
import 'package:everything_app/data/database/watch_extensions.dart';

part 'attachments_dao.g.dart';

/// [AttachmentsDao] is every statement against the polymorphic `attachments`
/// table (Requirement 12.2).
///
/// The table has existed since Phase 2 and until now had no writer — `ProjectsDao`
/// counts and cascades it, but nothing created a row. A shared file is the first
/// thing that does.
///
/// [watchFor] is scoped by owner rather than streaming the whole table the way the
/// feature DAOs do. Attachments are the one collection with no screen of their
/// own: they are always read as "this project's files", never as a list, so a
/// whole-table stream would hand every listener rows it must then filter out.
@DriftAccessor(tables: [AttachmentsTable])
class AttachmentsDao extends DatabaseAccessor<AppDatabase>
    with _$AttachmentsDaoMixin {
  AttachmentsDao(super.db);

  Stream<List<AttachmentEntry>> watchFor({
    required String ownerType,
    required String ownerId,
  }) =>
      (select(attachmentsTable)
            ..where(
              (a) => a.ownerType.equals(ownerType) & a.ownerId.equals(ownerId),
            )
            ..orderBy([
              (a) =>
                  OrderingTerm(expression: a.createdAt, mode: OrderingMode.desc),
            ]))
          .watch()
          .distinctList();

  Future<AttachmentEntry?> findById(String id) =>
      (select(attachmentsTable)..where((a) => a.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsert(AttachmentsTableCompanion attachment) =>
      into(attachmentsTable).insertOnConflictUpdate(attachment);

  Future<int> deleteById(String id) =>
      (delete(attachmentsTable)..where((a) => a.id.equals(id))).go();

  /// [totalSizeBytes] is what every attachment on the device adds up to — the
  /// Library's share of the Storage Usage section (Requirement 25.4).
  ///
  /// Summed in SQL rather than by reading the rows: this runs on the Settings
  /// screen, and a device with a few hundred attachments should not pull every
  /// row into memory to add one column up.
  Future<int> totalSizeBytes() async {
    final total = attachmentsTable.sizeBytes.sum();
    final query = selectOnly(attachmentsTable)..addColumns([total]);
    final row = await query.getSingleOrNull();
    return row?.read(total) ?? 0;
  }
}
