import 'package:drift/drift.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/database/tables/tables.dart';
import 'package:everything_app/data/database/watch_extensions.dart';

part 'attachments_dao.g.dart';

/// [AttachmentsDao] is every statement against the polymorphic `attachments`
/// table (Requirement 12.2).
///
/// [watchFor] is scoped by owner rather than streaming the whole table like the
/// feature DAOs: attachments have no screen of their own and are always read as
/// "this project's files", so a whole-table stream would hand every listener
/// rows it must then filter out.
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
  /// Library's share of the Storage Usage section (Requirement 25.4). Summed in
  /// SQL so a few hundred attachments are not pulled into memory to add up.
  Future<int> totalSizeBytes() async {
    final total = attachmentsTable.sizeBytes.sum();
    final query = selectOnly(attachmentsTable)..addColumns([total]);
    final row = await query.getSingleOrNull();
    return row?.read(total) ?? 0;
  }
}
