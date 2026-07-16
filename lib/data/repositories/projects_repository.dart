import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/project.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/data/services/projects_service.dart';

/// [ProjectsRepository] defines the contract for Projects (Requirement 10).
abstract class ProjectsRepository {
  /// [watchAll] streams every project at every depth; the tree is rebuilt in
  /// memory from it.
  Stream<List<Project>> watchAll();

  /// [watchTasksForProject] streams the tasks filed under a project
  /// (Requirement 10.3).
  Stream<List<Task>> watchTasksForProject(String projectId);

  /// [create] adds a project or a sub-project.
  Future<JsonResponse> create(Project project);

  /// [update] saves an edited project.
  Future<JsonResponse> update(Project project);

  /// [contentsOf] is what deleting a project would take with it — the counts the
  /// confirmation reads (Requirement 10.4).
  Future<JsonResponse> contentsOf({
    required Project project,
    required ProjectTree tree,
  });

  /// [delete] removes a project and everything under it, sub-projects included.
  Future<JsonResponse> delete({
    required Project project,
    required ProjectTree tree,
  });

  /// [moveProject] re-parents a project, refusing a move into its own descendant.
  Future<JsonResponse> moveProject({
    required Project project,
    required String? parentProjectId,
    required ProjectTree tree,
  });
}

class ProjectsRepositoryImpl implements ProjectsRepository {
  const ProjectsRepositoryImpl({required this.projectsService});

  final ProjectsService projectsService;

  @override
  Stream<List<Project>> watchAll() => projectsService.watchAll();

  @override
  Stream<List<Task>> watchTasksForProject(String projectId) =>
      projectsService.watchTasksForProject(projectId);

  @override
  Future<JsonResponse> create(Project project) => projectsService.create(project);

  @override
  Future<JsonResponse> update(Project project) => projectsService.update(project);

  @override
  Future<JsonResponse> contentsOf({
    required Project project,
    required ProjectTree tree,
  }) =>
      projectsService.contentsOf(project: project, tree: tree);

  @override
  Future<JsonResponse> delete({
    required Project project,
    required ProjectTree tree,
  }) =>
      projectsService.delete(project: project, tree: tree);

  @override
  Future<JsonResponse> moveProject({
    required Project project,
    required String? parentProjectId,
    required ProjectTree tree,
  }) =>
      projectsService.moveProject(
        project: project,
        parentProjectId: parentProjectId,
        tree: tree,
      );
}
