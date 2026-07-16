part of 'projects_bloc.dart';

/// [ProjectsEvent] is the base class for every Projects event.
abstract class ProjectsEvent extends Equatable {
  const ProjectsEvent();

  @override
  List<Object?> get props => [];
}

/// [WatchProjectsEvent] subscribes to the projects. Fired once.
class WatchProjectsEvent extends ProjectsEvent {
  const WatchProjectsEvent();
}

/// [SearchProjectsEvent] is the in-module search.
class SearchProjectsEvent extends ProjectsEvent {
  const SearchProjectsEvent({required this.query});

  final String query;

  @override
  List<Object?> get props => [query];
}

/// [SaveProjectEvent] creates or updates, depending on [isEditing].
///
/// A sub-project is not a different event: it is a project whose
/// [Project.parentProjectId] is set (Requirement 10.2).
class SaveProjectEvent extends ProjectsEvent {
  const SaveProjectEvent({required this.project, this.isEditing = false});

  final Project project;
  final bool isEditing;

  @override
  List<Object?> get props => [project, isEditing];
}

/// [MoveProjectEvent] re-parents a project. A null [parentProjectId] moves it back
/// to the top level.
class MoveProjectEvent extends ProjectsEvent {
  const MoveProjectEvent({required this.project, this.parentProjectId});

  final Project project;
  final String? parentProjectId;

  @override
  List<Object?> get props => [project, parentProjectId];
}

/// [ConfirmDeleteProjectEvent] asks what deleting [project] would destroy
/// (Requirement 10.4).
///
/// It **deletes nothing**. It puts a [PendingDelete] on the state, the screen shows
/// the confirmation, and only the user's agreement dispatches [DeleteProjectEvent].
class ConfirmDeleteProjectEvent extends ProjectsEvent {
  const ConfirmDeleteProjectEvent({required this.project});

  final Project project;

  @override
  List<Object?> get props => [project];
}

/// [DeleteProjectEvent] deletes a project and everything filed under it — its
/// sub-projects, tasks, documents and attachments (Requirement 10.4).
class DeleteProjectEvent extends ProjectsEvent {
  const DeleteProjectEvent({required this.project});

  final Project project;

  @override
  List<Object?> get props => [project];
}

/// [CancelDeleteProjectEvent] dismisses the confirmation.
class CancelDeleteProjectEvent extends ProjectsEvent {
  const CancelDeleteProjectEvent();
}
