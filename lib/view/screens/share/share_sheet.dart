import 'package:everything_app/bloc/projects/projects_bloc.dart';
import 'package:everything_app/bloc/share/share_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/project.dart';
import 'package:everything_app/data/models/shared_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [showShareSheet] opens the chooser for content shared in from another app
/// (Requirement 12.2).
///
/// A modal sheet on the root navigator, like the task, transaction and AI sheets:
/// a share arrives over whatever screen the user was last on, and it has no
/// business being a route — there is nothing to go Back to and nothing to deep
/// link at.
///
/// [BlocProvider.value] re-provides the bloc across the route boundary, the same
/// idiom the backups sheet uses.
Future<void> showShareSheet(BuildContext context) {
  final bloc = context.read<ShareBloc>();

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BlocProvider<ShareBloc>.value(
      value: bloc,
      child: const ShareSheet(),
    ),
  );
}

/// [ShareSheet] asks where a share should go, and files it there.
///
/// The chooser exists because the destination is genuinely ambiguous: a link is
/// usually a bookmark, but "read this later" is a task, and only the person who
/// shared it knows which they meant. It offers only the destinations that fit
/// what arrived (see [ShareDestination.isAvailableFor]) rather than showing
/// options that would fail on tap.
class ShareSheet extends StatelessWidget {
  const ShareSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ShareBloc, ShareState>(
      listenWhen: (previous, current) =>
          previous.message != current.message ||
          previous.error != current.error ||
          previous.isChooserOpen != current.isChooserOpen,
      listener: (context, state) {
        if (state.error.isNotEmpty) {
          context.showSnack(state.error, isError: true);
          return;
        }

        // Filed: confirm and close. The sheet is dismissed from the listener
        // rather than the handler because the bloc is app-scoped and knows
        // nothing about a route being on the stack.
        if (state.message.isNotEmpty) {
          context.showSnack(state.message);
        }
        if (!state.isChooserOpen && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
        final items = state.pending;
        if (items.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: responsivePadding(context).copyWith(bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                items.length == 1 ? 'Shared with Everything' : 'Shared items',
                style: context.texts.titleMedium,
              ),
              const Gap(12),
              _SharedPreview(items: items),
              const Gap(20),
              Text('SAVE AS', style: context.texts.labelSmall),
              const Gap(4),
              for (final destination in state.destinations)
                _DestinationTile(
                  destination: destination,
                  isEnabled: !state.isLoading,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// [_SharedPreview] shows what is about to be filed.
///
/// Named so the user can tell a mis-share from the right one before it lands
/// somewhere — a share sheet tapped by accident is common, and this is the last
/// point at which it costs nothing.
class _SharedPreview extends StatelessWidget {
  const _SharedPreview({required this.items});

  final List<SharedItem> items;

  @override
  Widget build(BuildContext context) {
    final first = items.first;
    final extra = items.length - 1;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(_iconFor(first.kind), size: 20, color: context.colors.primary),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  first.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium,
                ),
                const Gap(2),
                Text(
                  extra > 0
                      ? '${first.subtitle}  ·  +$extra more'
                      : first.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(SharedKind kind) => switch (kind) {
        SharedKind.url => Icons.link_rounded,
        SharedKind.text => Icons.notes_rounded,
        SharedKind.file => Icons.insert_drive_file_outlined,
      };
}

/// [_DestinationTile] is one option in the chooser.
class _DestinationTile extends StatelessWidget {
  const _DestinationTile({required this.destination, required this.isEnabled});

  final ShareDestination destination;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(destination.icon),
      title: Text(destination.label),
      subtitle: Text(destination.description, style: context.texts.bodySmall),
      trailing: const Icon(Icons.chevron_right_rounded),
      enabled: isEnabled,
      onTap: isEnabled ? () => _choose(context) : null,
    );
  }

  Future<void> _choose(BuildContext context) async {
    final bloc = context.read<ShareBloc>();

    // A project file needs a project. Asked for here rather than in the bloc
    // because it is a second question to the user, and only this one destination
    // has it.
    if (destination == ShareDestination.projectFile) {
      final projects = context.read<ProjectsBloc>().state.projects;

      if (projects.isEmpty) {
        context.showSnack('Create a project first.', isError: true);
        return;
      }

      final projectId = await showDialog<String>(
        context: context,
        builder: (_) => _ProjectPicker(projects: projects),
      );
      if (projectId == null) return;

      bloc.add(
        ShareDestinationChosen(destination: destination, projectId: projectId),
      );
      return;
    }

    bloc.add(ShareDestinationChosen(destination: destination));
  }
}

/// [_ProjectPicker] asks which project a shared file belongs to.
class _ProjectPicker extends StatelessWidget {
  const _ProjectPicker({required this.projects});

  final List<Project> projects;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Attach to'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: projects.length,
          itemBuilder: (context, index) {
            final project = projects[index];
            return ListTile(
              title: Text(project.name),
              onTap: () => Navigator.of(context).pop(project.id),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
