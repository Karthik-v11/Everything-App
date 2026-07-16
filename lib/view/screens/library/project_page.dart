import 'package:everything_app/bloc/documents/documents_bloc.dart';
import 'package:everything_app/bloc/projects/projects_bloc.dart';
import 'package:everything_app/bloc/tasks/tasks_bloc.dart';
import 'package:everything_app/core/route/routes.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/document.dart';
import 'package:everything_app/data/models/project.dart';
import 'package:everything_app/view/screens/library/project_sheet.dart';
import 'package:everything_app/view/screens/tasks/task_sheet.dart';
import 'package:everything_app/view/widgets/project_card.dart';
import 'package:everything_app/view/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

/// [ProjectPage] is one project and everything filed under it (Requirement 10).
///
/// It takes the project's **id**, not the project — a screen reached from a
/// notification, a search result or a restored navigation stack has no object to be
/// handed, and looking it up from the streamed list means the screen also notices
/// when the project it is showing has been deleted from somewhere else.
///
/// The tasks come from [TasksBloc], which already streams every task, rather than
/// from a second query here (Requirement 10.3). One list, filtered — so a task
/// completed on this screen and the same task on the Tasks tab cannot disagree.
class ProjectPage extends StatelessWidget {
  const ProjectPage({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProjectsBloc, ProjectsState>(
      listenWhen: (previous, current) =>
          previous.error != current.error ||
          previous.message != current.message ||
          previous.pendingDelete != current.pendingDelete,
      listener: (context, state) {
        if (state.error.isNotEmpty) {
          context.showSnack(state.error, isError: true);
        } else if (state.message.isNotEmpty) {
          context.showSnack(state.message);
        }

        final pending = state.pendingDelete;
        if (pending != null && pending.project.id == projectId) {
          _confirmDelete(context, pending);
        }
      },
      builder: (context, state) {
        final project = state.byId(projectId);

        // Deleted — from here, from its parent's screen, or from a cascade that took
        // its own parent with it. The screen leaves rather than sitting there showing
        // a project that no longer exists.
        if (project == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final children = state.childrenOf(project.id);
        final ancestors = state.ancestorsOf(project.id);

        return Scaffold(
          appBar: AppBar(
            title: Text(project.name),
            actions: [
              IconButton(
                onPressed: () => showProjectSheet(context, project: project),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit project',
              ),
              IconButton(
                onPressed: () => context.read<ProjectsBloc>().add(
                      ConfirmDeleteProjectEvent(project: project),
                    ),
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Delete project',
              ),
            ],
          ),
          body: ListView(
            padding: responsivePadding(context).copyWith(top: 8, bottom: 120),
            children: [
              if (ancestors.isNotEmpty) ...[
                _Breadcrumb(ancestors: ancestors),
                const Gap(12),
              ],
              if (project.description != null &&
                  project.description!.isNotBlank) ...[
                Text(project.description!, style: context.texts.bodySmall),
                const Gap(20),
              ],
              _SubProjects(project: project, children: children),
              const Gap(24),
              _Tasks(project: project),
              const Gap(24),
              _Documents(project: project),
            ],
          ),
        );
      },
    );
  }

  /// [_confirmDelete] is the confirmation Requirement 10.4 asks for.
  ///
  /// It **names what will be destroyed** — "3 tasks and 1 sub-project" — because a
  /// dialog that only said "Delete project?" would be asking the user to agree to
  /// something they have not been told. The counts come from the database, through
  /// [PendingDelete], so they are what will actually go.
  ///
  /// An empty project skips straight to the delete: there is nothing to warn about,
  /// and a confirmation with nothing in it trains people to dismiss the ones that
  /// matter.
  Future<void> _confirmDelete(
    BuildContext context,
    PendingDelete pending,
  ) async {
    final bloc = context.read<ProjectsBloc>();

    if (pending.contents.isEmpty) {
      bloc.add(DeleteProjectEvent(project: pending.project));
      if (context.mounted) context.pop();
      return;
    }

    final isConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${pending.project.name}?'),
        content: Text(
          'This also deletes ${pending.contents.summary}. '
          'It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: dialogContext.colors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (isConfirmed ?? false) {
      bloc.add(DeleteProjectEvent(project: pending.project));
      if (context.mounted) context.pop();
    } else {
      bloc.add(const CancelDeleteProjectEvent());
    }
  }
}

/// [_Breadcrumb] is the path back up to the root, nearest parent last so it reads
/// left to right.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.ancestors});

  final List<Project> ancestors;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final path = ancestors.reversed.toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < path.length; i++) ...[
            InkWell(
              onTap: () => context.pushReplacementNamed(
                projectRoute,
                pathParameters: {'id': path[i].id},
              ),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(path[i].name, style: context.texts.labelSmall),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 14,
              color: colors.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}

/// [_SubProjects] is the project's children (Requirement 10.2).
class _SubProjects extends StatelessWidget {
  const _SubProjects({required this.project, required this.children});

  final Project project;
  final List<Project> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Sub-projects', style: context.texts.titleMedium),
            ),
            TextButton.icon(
              onPressed: () => showProjectSheet(
                context,
                parentProjectId: project.id,
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add'),
            ),
          ],
        ),
        const Gap(4),
        if (children.isEmpty)
          Text(
            'Break this into smaller projects when it needs it.',
            style: context.texts.bodySmall,
          )
        else
          for (final child in children)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: BlocBuilder<ProjectsBloc, ProjectsState>(
                buildWhen: (previous, current) =>
                    previous.projects != current.projects,
                builder: (context, state) => ProjectCard(
                  project: child,
                  subProjectCount: state.childrenOf(child.id).length,
                  onTap: () => context.pushNamed(
                    projectRoute,
                    pathParameters: {'id': child.id},
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

/// [_Documents] is the documents filed under the project (Requirement 10.1, 11).
///
/// Read from [DocumentsBloc]'s stream and filtered by project id, the same way the
/// tasks are — so a document saved in the editor appears here without a reload.
/// Opening one navigates to the editor by id; a new one mints its id here so the
/// route is addressable from the moment it opens, and carries this project so the
/// blank document is filed correctly.
class _Documents extends StatelessWidget {
  const _Documents({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DocumentsBloc, DocumentsState>(
      listenWhen: (previous, current) =>
          previous.error != current.error ||
          previous.message != current.message,
      listener: (context, state) {
        if (state.error.isNotEmpty) {
          context.showSnack(state.error, isError: true);
        } else if (state.message.isNotEmpty) {
          context.showSnack(state.message);
        }
      },
      buildWhen: (previous, current) => previous.documents != current.documents,
      builder: (context, state) {
        final documents = state.documentsForProject(project.id);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Documents', style: context.texts.titleMedium),
                ),
                TextButton.icon(
                  onPressed: () => _openNew(context),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add'),
                ),
              ],
            ),
            const Gap(4),
            if (documents.isEmpty)
              Text(
                'Notes and write-ups for this project show up here.',
                style: context.texts.bodySmall,
              )
            else
              for (final document in documents)
                _DocumentTile(project: project, document: document),
          ],
        );
      },
    );
  }

  void _openNew(BuildContext context) {
    context.pushNamed(
      documentRoute,
      pathParameters: {'id': const Uuid().v4()},
      queryParameters: {'projectId': project.id},
    );
  }
}

/// [_DocumentTile] is one document in the project's list: its title, a line of the
/// body, and a delete action.
class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.project, required this.document});

  final Project project;
  final Document document;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.pushNamed(
            documentRoute,
            pathParameters: {'id': document.id},
            queryParameters: {'projectId': project.id},
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
                const Gap(14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        document.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.labelLarge,
                      ),
                      if (document.preview.isNotEmpty) ...[
                        const Gap(4),
                        Text(
                          document.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                const Gap(8),
                IconButton(
                  onPressed: () => _confirmDelete(context),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  tooltip: 'Delete document',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final bloc = context.read<DocumentsBloc>();

    final isConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${document.displayTitle}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: dialogContext.colors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (isConfirmed ?? false) {
      bloc.add(DeleteDocumentEvent(document: document));
    }
  }
}

/// [_Tasks] is the tasks filed under the project (Requirement 10.3).
///
/// Read from [TasksBloc]'s existing stream and filtered by project id, rather than
/// queried again here. The checkbox dispatches to the same bloc as the Tasks tab, so
/// completing a task here rolls its recurrence over and cancels its reminder exactly
/// as it would anywhere else — none of which this screen has to know about.
class _Tasks extends StatelessWidget {
  const _Tasks({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TasksBloc, TasksState>(
      buildWhen: (previous, current) => previous.tasks != current.tasks,
      builder: (context, state) {
        final tasks = [
          for (final task in state.tasks)
            if (task.projectId == project.id) task,
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Tasks', style: context.texts.titleMedium),
                ),
                TextButton.icon(
                  onPressed: () => showTaskSheet(context, projectId: project.id),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add'),
                ),
              ],
            ),
            const Gap(4),
            if (tasks.isEmpty)
              Text(
                'Tasks filed under this project show up here.',
                style: context.texts.bodySmall,
              )
            else
              for (final task in tasks)
                TaskCard(
                  task: task,
                  category: state.categoryOf(task),
                  onToggle: (isCompleted) => context.read<TasksBloc>().add(
                        ToggleTaskCompletionEvent(
                          task: task,
                          isCompleted: isCompleted,
                        ),
                      ),
                  onTap: () => showTaskSheet(context, task: task),
                ),
          ],
        );
      },
    );
  }
}
