part of 'projects_bloc.dart';

/// [PendingDelete] is a project the user has asked to delete, and what deleting it
/// would take with it (Requirement 10.4).
///
/// It exists as state rather than as a value passed to a dialog because the counts
/// come from the database, and a widget that queries the database is a widget doing
/// the repository's job. The screen renders a confirmation whenever this is present.
class PendingDelete extends Equatable {
  const PendingDelete({required this.project, required this.contents});

  final Project project;
  final ProjectContents contents;

  @override
  List<Object?> get props => [
        project,
        contents.projects,
        contents.tasks,
        contents.documents,
        contents.attachments,
      ];
}

/// [ProjectsState] holds everything the Projects screens render.
///
/// [projects] is the complete flat list. The tree — roots, children, breadcrumbs,
/// and the descendants a delete would cascade to — is derived from it by [tree], so
/// nothing on screen can disagree with the parent ids in the rows.
class ProjectsState extends Equatable {
  const ProjectsState({
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.projects = const <Project>[],
    this.query = '',
    this.pendingDelete,
  });

  final bool isLoading;
  final String error;
  final String message;
  final List<Project> projects;
  final String query;

  /// The delete awaiting the user's confirmation, or null.
  final PendingDelete? pendingDelete;

  /// [tree] is the project hierarchy, rebuilt from [projects].
  ///
  /// Recomputed on read rather than cached: it is a few map insertions over a list
  /// that is tens of items long at most, and a cached tree is one more thing that
  /// can be stale.
  ProjectTree get tree => ProjectTree(projects);

  /// [roots] are the top-level projects — what the Library hub lists.
  ///
  /// Under a search, the flat matching list is what the user wants: someone typing
  /// a name is looking for a project, not for the branch it happens to hang from.
  List<Project> get roots {
    if (query.isNotBlank) return visibleProjects;
    return tree.roots;
  }

  /// [visibleProjects] is every project at any depth matching the search query.
  List<Project> get visibleProjects => [
        for (final project in projects)
          if (project.matches(query)) project,
      ];

  bool get isFiltered => query.isNotBlank;

  /// [childrenOf] are the direct sub-projects of a project (Requirement 10.2).
  List<Project> childrenOf(String id) => tree.childrenOf(id);

  /// [byId] resolves a project, or null once it has been deleted — which is what a
  /// detail screen still on the stack reads to know it should leave.
  Project? byId(String? id) => tree.byId(id);

  /// [ancestorsOf] is the breadcrumb on a sub-project's screen, nearest parent
  /// first.
  List<Project> ancestorsOf(String id) => tree.ancestorsOf(id);

  ProjectsState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    List<Project>? projects,
    String? query,
    PendingDelete? pendingDelete,
    bool clearPendingDelete = false,
  }) =>
      ProjectsState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        projects: projects ?? this.projects,
        query: query ?? this.query,
        pendingDelete:
            clearPendingDelete ? null : (pendingDelete ?? this.pendingDelete),
      );

  @override
  List<Object?> get props => [
        isLoading,
        error,
        message,
        projects,
        query,
        pendingDelete,
      ];
}
