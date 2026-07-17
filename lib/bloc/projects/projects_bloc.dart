import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/models/project.dart';
import 'package:everything_app/data/repositories/projects_repository.dart';
import 'package:everything_app/data/services/projects_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'projects_event.dart';
part 'projects_state.dart';

/// [ProjectsBloc] owns the Projects sub-feature (Requirement 10).
///
/// It streams every project at every depth and rebuilds the tree in memory
/// ([ProjectTree]), so one flat query serves the hub's root list, a project's
/// children, its breadcrumb and the cascade a delete would take.
class ProjectsBloc extends Bloc<ProjectsEvent, ProjectsState> {
  ProjectsBloc({required this.repository}) : super(const ProjectsState()) {
    on<WatchProjectsEvent>(_onWatchProjectsEvent);
    on<SearchProjectsEvent>(_onSearchProjectsEvent);
    on<SaveProjectEvent>(_onSaveProjectEvent);
    on<MoveProjectEvent>(_onMoveProjectEvent);
    on<ConfirmDeleteProjectEvent>(_onConfirmDeleteProjectEvent);
    on<DeleteProjectEvent>(_onDeleteProjectEvent);
    on<CancelDeleteProjectEvent>(_onCancelDeleteProjectEvent);
  }

  final ProjectsRepository repository;

  FutureOr<void> _onWatchProjectsEvent(
    WatchProjectsEvent event,
    Emitter<ProjectsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: '', message: ''));

    await emit.forEach<List<Project>>(
      repository.watchAll(),
      onData: (projects) =>
          state.copyWith(isLoading: false, projects: projects, error: ''),
      onError: (_, _) => state.copyWith(
        isLoading: false,
        error: 'Could not load your projects.',
      ),
    );
  }

  FutureOr<void> _onSearchProjectsEvent(
    SearchProjectsEvent event,
    Emitter<ProjectsState> emit,
  ) {
    emit(state.copyWith(query: event.query));
  }

  FutureOr<void> _onSaveProjectEvent(
    SaveProjectEvent event,
    Emitter<ProjectsState> emit,
  ) async {
    try {
      final response = event.isEditing
          ? await repository.update(event.project)
          : await repository.create(event.project);

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not save the project.'));
    }
  }

  FutureOr<void> _onMoveProjectEvent(
    MoveProjectEvent event,
    Emitter<ProjectsState> emit,
  ) async {
    try {
      final response = await repository.moveProject(
        project: event.project,
        parentProjectId: event.parentProjectId,
        tree: state.tree,
      );

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not move the project.'));
    }
  }

  /// [_onConfirmDeleteProjectEvent] counts what deleting [project] would destroy
  /// (Requirement 10.4).
  ///
  /// This is a read: nothing is deleted until [DeleteProjectEvent], which the user's
  /// confirmation dispatches. The counts go into the state — the screen shows the
  /// confirmation when [ProjectsState.pendingDelete] appears — rather than being
  /// fetched by the dialog.
  FutureOr<void> _onConfirmDeleteProjectEvent(
    ConfirmDeleteProjectEvent event,
    Emitter<ProjectsState> emit,
  ) async {
    try {
      final response = await repository.contentsOf(
        project: event.project,
        tree: state.tree,
      );

      if (!response.success || response.data is! ProjectContents) {
        emit(state.copyWith(error: response.message));
        return;
      }

      emit(
        state.copyWith(
          pendingDelete: PendingDelete(
            project: event.project,
            contents: response.data! as ProjectContents,
          ),
          error: '',
        ),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not read the project.'));
    }
  }

  /// [_onDeleteProjectEvent] deletes a project and everything under it
  /// (Requirement 10.4).
  ///
  /// The confirmation has already happened — [ConfirmDeleteProjectEvent] put the
  /// counts on screen and the user agreed to them.
  FutureOr<void> _onDeleteProjectEvent(
    DeleteProjectEvent event,
    Emitter<ProjectsState> emit,
  ) async {
    try {
      final response = await repository.delete(
        project: event.project,
        tree: state.tree,
      );

      emit(
        response.success
            ? state.copyWith(
                message: response.message,
                error: '',
                clearPendingDelete: true,
              )
            : state.copyWith(
                error: response.message,
                message: '',
                clearPendingDelete: true,
              ),
      );
    } on Exception {
      emit(
        state.copyWith(
          error: 'Could not delete the project.',
          clearPendingDelete: true,
        ),
      );
    }
  }

  FutureOr<void> _onCancelDeleteProjectEvent(
    CancelDeleteProjectEvent event,
    Emitter<ProjectsState> emit,
  ) {
    emit(state.copyWith(clearPendingDelete: true));
  }
}
