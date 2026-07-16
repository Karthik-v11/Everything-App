import 'package:drift/drift.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/database/tables/tables.dart';
import 'package:everything_app/data/database/watch_extensions.dart';

part 'projects_dao.g.dart';

/// [ProjectsDao] is every SQL statement the Projects sub-feature issues
/// (Requirement 10).
///
/// It reaches four tables rather than one because a project is a *container*: its
/// contents live in the tasks, documents and attachments tables and point back at
/// it. Counting and deleting those contents is the whole of Requirement 10.4, and
/// it cannot be done from the projects table alone.
@DriftAccessor(
  tables: [ProjectsTable, TasksTable, DocumentsTable, AttachmentsTable],
)
class ProjectsDao extends DatabaseAccessor<AppDatabase>
    with _$ProjectsDaoMixin {
  ProjectsDao(super.db);

  // ── Projects ───────────────────────────────────────────────────────────────

  /// [watchAll] streams every project, at every depth.
  ///
  /// The tree is rebuilt in memory from this one flat list (see [ProjectTree]).
  /// Querying one level at a time would mean a query per expanded node, and a
  /// screen that has to ask the database again every time a disclosure arrow is
  /// tapped.
  Stream<List<ProjectEntry>> watchAll() => (select(projectsTable)
        ..orderBy([(p) => OrderingTerm(expression: p.createdAt)]))
      .watch()
      .distinctList();

  Future<ProjectEntry?> findById(String id) =>
      (select(projectsTable)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<void> upsert(ProjectsTableCompanion project) =>
      into(projectsTable).insertOnConflictUpdate(project);

  // ── Contents ───────────────────────────────────────────────────────────────

  /// [watchTasksForProject] streams the tasks filed under [projectId]
  /// (Requirement 10.3).
  Stream<List<TaskEntry>> watchTasksForProject(String projectId) =>
      (select(tasksTable)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([
              (t) => OrderingTerm(expression: t.dueDate.isNull()),
              (t) => OrderingTerm(expression: t.dueDate),
            ]))
          .watch()
          .distinctList();

  /// [contentCounts] is what a project actually holds, across every table that
  /// points at it — including the projects [projectIds] themselves nest.
  ///
  /// The delete confirmation reads this. Requirement 10.4 asks for a confirmation
  /// before permanently removing "the project and all its contents", and a dialog
  /// that says "Delete project?" without saying that it is also about to delete
  /// eleven tasks is not the confirmation that requirement is asking for.
  Future<({int tasks, int documents, int attachments})> contentCounts(
    List<String> projectIds,
  ) async {
    if (projectIds.isEmpty) {
      return (tasks: 0, documents: 0, attachments: 0);
    }

    final taskCount = tasksTable.id.count();
    final taskQuery = selectOnly(tasksTable)
      ..addColumns([taskCount])
      ..where(tasksTable.projectId.isIn(projectIds));

    final documentCount = documentsTable.id.count();
    final documentQuery = selectOnly(documentsTable)
      ..addColumns([documentCount])
      ..where(documentsTable.projectId.isIn(projectIds));

    final attachmentCount = attachmentsTable.id.count();
    final attachmentQuery = selectOnly(attachmentsTable)
      ..addColumns([attachmentCount])
      ..where(
        attachmentsTable.ownerType.equals('project') &
            attachmentsTable.ownerId.isIn(projectIds),
      );

    final (tasks, documents, attachments) = await (
      taskQuery.getSingle(),
      documentQuery.getSingle(),
      attachmentQuery.getSingle(),
    ).wait;

    return (
      tasks: tasks.read(taskCount) ?? 0,
      documents: documents.read(documentCount) ?? 0,
      attachments: attachments.read(attachmentCount) ?? 0,
    );
  }

  /// [deleteCascade] removes [projectIds] and everything filed under them
  /// (Requirement 10.4).
  ///
  /// [projectIds] must already include the descendants — the caller resolves the
  /// tree, because the tree is a fact about the whole project list and this method
  /// only has the ids it was handed.
  ///
  /// One transaction: a delete that removed a project's tasks and then failed to
  /// remove the project would leave a container whose contents had silently
  /// vanished, which is worse than either outcome on its own.
  Future<void> deleteCascade(List<String> projectIds) async {
    if (projectIds.isEmpty) return;

    await transaction(() async {
      await (delete(tasksTable)..where((t) => t.projectId.isIn(projectIds)))
          .go();

      await (delete(documentsTable)
            ..where((d) => d.projectId.isIn(projectIds)))
          .go();

      await (delete(attachmentsTable)
            ..where(
              (a) =>
                  a.ownerType.equals('project') & a.ownerId.isIn(projectIds),
            ))
          .go();

      await (delete(projectsTable)..where((p) => p.id.isIn(projectIds))).go();
    });
  }
}
