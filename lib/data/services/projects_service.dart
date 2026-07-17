import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/daos/projects_dao.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/project.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:uuid/uuid.dart';

/// [ProjectContents] is what deleting a project would destroy (Requirement 10.4).
///
/// [projects] counts the sub-projects that would go with it, so the confirmation
/// can name them rather than leaving the user to discover them.
class ProjectContents {
  const ProjectContents({
    required this.projects,
    required this.tasks,
    required this.documents,
    required this.attachments,
  });

  final int projects;
  final int tasks;
  final int documents;
  final int attachments;

  /// [isEmpty] is a project with nothing under it, so it is deleted without a
  /// confirmation — there is nothing to warn about.
  bool get isEmpty =>
      projects == 0 && tasks == 0 && documents == 0 && attachments == 0;

  /// [summary] is the human sentence the dialog shows: "3 tasks and 1 sub-project".
  String get summary {
    final parts = [
      if (projects > 0) _plural(projects, 'sub-project'),
      if (tasks > 0) _plural(tasks, 'task'),
      if (documents > 0) _plural(documents, 'document'),
      if (attachments > 0) _plural(attachments, 'attachment'),
    ];

    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first;

    return '${parts.take(parts.length - 1).join(', ')} and ${parts.last}';
  }

  static String _plural(int count, String noun) =>
      count == 1 ? '1 $noun' : '$count ${noun}s';
}

/// [ProjectsService] is the Projects sub-feature's persistence layer
/// (Requirement 10).
class ProjectsService {
  ProjectsService({required this.dao});

  final ProjectsDao dao;

  static const Uuid _uuid = Uuid();

  Stream<List<Project>> watchAll() =>
      dao.watchAll().map((rows) => rows.map(Project.fromEntry).toList());

  /// [watchTasksForProject] streams the tasks filed under a project
  /// (Requirement 10.3).
  Stream<List<Task>> watchTasksForProject(String projectId) =>
      dao.watchTasksForProject(projectId).map(
            (rows) => rows.map(Task.fromEntry).toList(),
          );

  Future<JsonResponse> create(Project project) async {
    try {
      if (project.name.isBlank) {
        return JsonResponse.failure(
          statusCode: 400,
          message: 'A project needs a name.',
        );
      }

      final now = DateTime.now();

      final prepared = project.copyWith(
        id: project.id.isBlank ? _uuid.v4() : project.id,
        name: project.name.trim(),
        createdAt: now,
        updatedAt: now,
      );

      await dao.upsert(prepared.toCompanion());

      return JsonResponse.created(message: 'Project created.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not create the project.',
      );
    }
  }

  Future<JsonResponse> update(Project project) async {
    try {
      if (project.name.isBlank) {
        return JsonResponse.failure(
          statusCode: 400,
          message: 'A project needs a name.',
        );
      }

      final prepared = project.copyWith(
        name: project.name.trim(),
        updatedAt: DateTime.now(),
      );

      await dao.upsert(prepared.toCompanion());

      return JsonResponse.success(message: 'Project updated.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not update the project.',
      );
    }
  }

  /// [contentsOf] is the counts the confirmation dialog reads (Requirement 10.4).
  ///
  /// [tree] is passed in because descendants are a fact about the whole project
  /// list, which this service does not hold — the bloc streams it.
  Future<JsonResponse> contentsOf({
    required Project project,
    required ProjectTree tree,
  }) async {
    try {
      final descendants = tree.descendantsOf(project.id);
      final ids = [project.id, for (final child in descendants) child.id];

      final counts = await dao.contentCounts(ids);

      return JsonResponse.success(
        message: 'Loaded successfully.',
        data: ProjectContents(
          projects: descendants.length,
          tasks: counts.tasks,
          documents: counts.documents,
          attachments: counts.attachments,
        ),
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not read the project.',
      );
    }
  }

  /// [delete] removes a project and everything under it (Requirement 10.4).
  ///
  /// Sub-projects are resolved from [tree] and deleted with it; deleting only the
  /// tapped row would strand its children under a parent that no longer exists,
  /// on no screen and reachable by nothing.
  ///
  /// The confirmation is the caller's and is not optional — this is the
  /// destructive path, and the user must already have seen what [contentsOf] found.
  Future<JsonResponse> delete({
    required Project project,
    required ProjectTree tree,
  }) async {
    try {
      final descendants = tree.descendantsOf(project.id);
      final ids = [project.id, for (final child in descendants) child.id];

      await dao.deleteCascade(ids);

      return JsonResponse.success(message: 'Project deleted.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not delete the project.',
      );
    }
  }

  /// [moveProject] re-parents a project (Requirement 10.2).
  ///
  /// Refused when it would put a project inside its own descendant, which would
  /// detach that whole branch from the tree — see [ProjectTree.canReparent].
  Future<JsonResponse> moveProject({
    required Project project,
    required String? parentProjectId,
    required ProjectTree tree,
  }) async {
    try {
      if (!tree.canReparent(project, parentProjectId)) {
        return JsonResponse.failure(
          statusCode: 400,
          message: 'A project cannot be moved inside itself.',
        );
      }

      final prepared = project.copyWith(
        parentProjectId: parentProjectId,
        clearParentProjectId: parentProjectId == null,
        updatedAt: DateTime.now(),
      );

      await dao.upsert(prepared.toCompanion());

      return JsonResponse.success(message: 'Project moved.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not move the project.',
      );
    }
  }
}
