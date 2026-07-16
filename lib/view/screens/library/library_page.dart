import 'package:everything_app/bloc/bookmarks/bookmarks_bloc.dart';
import 'package:everything_app/bloc/documents/documents_bloc.dart';
import 'package:everything_app/bloc/projects/projects_bloc.dart';
import 'package:everything_app/bloc/to_buy/to_buy_bloc.dart';
import 'package:everything_app/bloc/vault/vault_bloc.dart';
import 'package:everything_app/bloc/watchlist/watchlist_bloc.dart';
import 'package:everything_app/core/route/routes.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/document.dart';
import 'package:everything_app/data/models/watchlist_item.dart';
import 'package:everything_app/view/screens/library/project_sheet.dart';
import 'package:everything_app/view/widgets/module_app_bar.dart';
import 'package:everything_app/view/widgets/project_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// [LibraryPage] is the Library hub (Requirements 6–10).
///
/// Four cards for the four collections, then the projects. Each card carries the
/// one number that says whether it is worth opening — how many bookmarks, how many
/// things still to buy, how many titles being watched, how many items in the vault.
/// A row of names with no counts is a menu; a row of names with counts is a status.
///
/// The vault card is the exception: it shows a count and nothing else, and it is
/// the only one whose screen asks who you are before it renders (Requirement 9.2).
///
/// Projects live on the hub rather than behind a fifth card because they are the
/// only one of the five that is a *container* — the others are lists you open, and
/// a project is a thing you work inside.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // Outside the list, so the header stays put while the page scrolls under
          // it — the same shape as the other three tabs.
          Padding(
            padding: responsivePadding(context),
            child: const ModuleAppBar(title: 'Library'),
          ),
          const Expanded(child: _Body()),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: responsivePadding(context).copyWith(bottom: 140),
      children: [
        const Gap(4),
        Text('Collections', style: context.texts.titleMedium),
        const Gap(12),
        const _Collections(),
        const Gap(28),
        const _ProjectsSection(),
        const Gap(28),
        const _NotesSection(),
      ],
    );
  }
}

/// [_Collections] is the four tiles, laid out two to a row.
///
/// Each subscribes to its own bloc for its count rather than the hub reading all
/// four: a bookmark saved elsewhere rebuilds the bookmarks tile and nothing else.
/// A 2×2 grid rather than a stack of full-width rows: the four are peers, and a
/// grid reads as "pick one" where a list reads as "work down these in order".
class _Collections extends StatelessWidget {
  const _Collections();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: BlocBuilder<BookmarksBloc, BookmarksState>(
                buildWhen: (previous, current) =>
                    previous.bookmarks.length != current.bookmarks.length,
                builder: (context, state) => _CollectionTile(
                  title: 'Bookmarks',
                  subtitle: 'Links, videos and repos.',
                  icon: Icons.bookmark_outline_rounded,
                  count: state.bookmarks.length,
                  unit: 'saved',
                  onTap: () => context.pushNamed(bookmarksRoute),
                ),
              ),
            ),
            const Gap(10),
            Expanded(
              child: BlocBuilder<ToBuyBloc, ToBuyState>(
                buildWhen: (previous, current) =>
                    previous.items != current.items,
                builder: (context, state) {
                  final pending =
                      state.items.where((i) => !i.isPurchased).length;

                  return _CollectionTile(
                    title: 'To Buys',
                    subtitle: 'What to pick up, and where.',
                    icon: Icons.shopping_bag_outlined,
                    count: pending,
                    unit: 'to buy',
                    onTap: () => context.pushNamed(toBuyRoute),
                  );
                },
              ),
            ),
          ],
        ),
        const Gap(10),
        Row(
          children: [
            Expanded(
              child: BlocBuilder<WatchlistBloc, WatchlistState>(
                buildWhen: (previous, current) =>
                    previous.items != current.items,
                builder: (context, state) {
                  // What is being watched *now* — the number the user is actually
                  // keeping. A lifetime total counts the things they finished in
                  // 2019.
                  final watching = state.countOfStatus(WatchStatus.watching);

                  return _CollectionTile(
                    title: 'Watchlist',
                    subtitle: 'Films, series, books, games.',
                    icon: Icons.play_circle_outline_rounded,
                    count: watching,
                    unit: 'in progress',
                    onTap: () => context.pushNamed(watchlistRoute),
                  );
                },
              ),
            ),
            const Gap(10),
            Expanded(
              child: BlocBuilder<VaultBloc, VaultState>(
                buildWhen: (previous, current) =>
                    previous.items.length != current.items.length,
                builder: (context, state) => _CollectionTile(
                  title: 'Vault',
                  subtitle: 'Passwords and IDs, encrypted.',
                  icon: Icons.lock_outline_rounded,
                  count: state.items.length,
                  unit: 'items',
                  // The one tile that says what opening it will cost you. The
                  // screen behind it asks for a fingerprint or a PIN before it
                  // renders a single row (Requirement 9.2), and being told that
                  // here is friendlier than being challenged without warning.
                  isLocked: true,
                  onTap: () => context.pushNamed(vaultRoute),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// [_CollectionTile] is one of the four: an icon chip, the number that says
/// whether it is worth opening, and the name under it.
///
/// The count leads — it is the one thing that changes and the reason to tap in —
/// with the accent reserved for the icon chip and the lock badge so the tiles read
/// as one set rather than four competing colours.
class _CollectionTile extends StatelessWidget {
  const _CollectionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.count,
    required this.unit,
    required this.onTap,
    this.isLocked = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final int count;
  final String unit;
  final VoidCallback onTap;
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final isEmpty = count == 0;

    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 148,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, size: 19, color: colors.primary),
                  ),
                  const Spacer(),
                  if (isLocked)
                    Icon(
                      Icons.shield_outlined,
                      size: 15,
                      color: colors.primary,
                    ),
                ],
              ),
              const Spacer(),
              // The count reads as one phrase — "12 saved" — rather than a bare
              // number the reader has to work the meaning of out of the tile it is
              // sitting on.
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$count',
                    style: texts.headlineMedium?.copyWith(
                      color: isEmpty ? colors.onSurfaceVariant : colors.onSurface,
                    ),
                  ),
                  const Gap(6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(unit, style: texts.labelSmall),
                  ),
                ],
              ),
              const Gap(4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: texts.labelLarge,
              ),
              // Text(
              //   subtitle,
              //   maxLines: 1,
              //   overflow: TextOverflow.ellipsis,
              //   style: texts.bodySmall,
              // ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [_ProjectsSection] is the projects, under an Add Project button
/// (Requirement 10).
///
/// Only the roots are listed. A sub-project belongs on its parent's screen, and a
/// hub that flattened the tree would say nothing about which project a piece of work
/// is actually part of.
class _ProjectsSection extends StatelessWidget {
  const _ProjectsSection();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProjectsBloc, ProjectsState>(
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
      builder: (context, state) {
        final roots = state.tree.roots;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Projects', style: context.texts.titleMedium),
                ),
                FilledButton.icon(
                  onPressed: () => showProjectSheet(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Project'),
                ),
              ],
            ),
            const Gap(12),
            if (roots.isEmpty)
              const _EmptyProjects()
            else
              for (final project in roots)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ProjectCard(
                    project: project,
                    subProjectCount: state.childrenOf(project.id).length,
                    onTap: () => context.pushNamed(
                      projectRoute,
                      pathParameters: {'id': project.id},
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text('No projects yet', style: context.texts.titleMedium),
          const Gap(6),
          Text(
            'A project holds the tasks, documents and links that belong '
            'to one piece of work.',
            textAlign: TextAlign.center,
            style: context.texts.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// [_NotesSection] shows standalone documents — notes created via the AI
/// assistant or the document writer that are not filed under any project.
///
/// These would otherwise be invisible: project screens only show their own
/// documents, and there is no top-level "Documents" collection on the Library
/// hub. Surfacing them here makes the AI's "Note" intent's output discoverable.
class _NotesSection extends StatelessWidget {
  const _NotesSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DocumentsBloc, DocumentsState>(
      builder: (context, state) {
        final notes = [
          for (final doc in state.documents)
            if (doc.projectId == null) doc,
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Notes', style: context.texts.titleMedium),
                ),
                if (notes.isNotEmpty)
                  Text(
                    '${notes.length}',
                    style: context.texts.labelSmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const Gap(12),
            if (notes.isEmpty)
              _EmptyNotes()
            else
              for (final doc in notes.take(10))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _NoteTile(document: doc),
                ),
          ],
        );
      },
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            Icons.description_outlined,
            size: 28,
            color: context.colors.onSurfaceVariant,
          ),
          const Gap(8),
          Text('No notes yet', style: context.texts.titleSmall),
          const Gap(4),
          Text(
            'Ask the AI to save a note, or create one from a project.',
            textAlign: TextAlign.center,
            style: context.texts.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.pushNamed(
          documentRoute,
          pathParameters: {'id': document.id},
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const Gap(12),
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
                      const Gap(2),
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
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
