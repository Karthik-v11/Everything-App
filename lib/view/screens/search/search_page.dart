import 'package:everything_app/bloc/search/search_bloc.dart';
import 'package:everything_app/core/route/routes.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/search_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// [SearchPage] is Global Search (Requirement 17).
///
/// A full-screen route above the shell: search spans all four tabs, so it is not
/// a child of any one of them. The field auto-focuses so the keyboard is up the
/// moment it opens, and results appear as the user types (Requirement 17.2),
/// grouped by module.
///
/// Tapping a result opens the module that owns it. There is no per-item detail
/// route for the list modules — as elsewhere in the app — so a task or a bookmark
/// result lands on its list; a project and a document, which are addressable,
/// open directly.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) =>
      context.read<SearchBloc>().add(SearchQueryChanged(query: value));

  void _runRecent(String query) {
    _controller
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    context.read<SearchBloc>()
      ..add(SearchQueryChanged(query: query))
      ..add(SubmitSearch(query: query));
    _focusNode.requestFocus();
  }

  void _openResult(SearchResult result) {
    // Record the query the user acted on, then hand off to the owning module.
    final query = _controller.text.trim();
    if (query.isNotBlank) {
      context.read<SearchBloc>().add(SubmitSearch(query: query));
    }

    switch (result.module) {
      case SearchModule.tasks:
        context.goNamed(tasksRoute);
      case SearchModule.transactions:
        context.goNamed(transactionsRoute);
      case SearchModule.bookmarks:
        context.goNamed(bookmarksRoute);
      case SearchModule.toBuy:
        context.goNamed(toBuyRoute);
      case SearchModule.watchlist:
        context.goNamed(watchlistRoute);
      case SearchModule.vault:
        // The vault challenges before it renders a row (Requirement 9.2); the
        // result gave away only a title, never the contents.
        context.goNamed(vaultRoute);
      case SearchModule.projects:
        context.goNamed(projectRoute, pathParameters: {'id': result.id});
      case SearchModule.documents:
        context.goNamed(documentRoute, pathParameters: {'id': result.id});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (value) =>
              context.read<SearchBloc>().add(SubmitSearch(query: value)),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: 'Search everything',
            hintStyle: context.texts.titleMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          style: context.texts.titleMedium,
        ),
        actions: [
          BlocBuilder<SearchBloc, SearchState>(
            buildWhen: (previous, current) =>
                previous.query.isNotEmpty != current.query.isNotEmpty,
            builder: (context, state) {
              if (state.query.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _controller.clear();
                  _onChanged('');
                  _focusNode.requestFocus();
                },
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<SearchBloc, SearchState>(
        listenWhen: (previous, current) => previous.error != current.error,
        listener: (context, state) {
          if (state.error.isNotEmpty) {
            context.showSnack(state.error, isError: true);
          }
        },
        builder: (context, state) {
          if (!state.hasQuery) {
            return _RecentSearches(
              searches: state.recentSearches,
              onTap: _runRecent,
              onRemove: (query) =>
                  context.read<SearchBloc>().add(RemoveRecentSearch(query: query)),
              onClear: () =>
                  context.read<SearchBloc>().add(const ClearRecentSearches()),
            );
          }

          if (state.isEmptyResult) {
            return _EmptyResults(query: state.query);
          }

          return _Results(groups: state.groups, onTap: _openResult);
        },
      ),
    );
  }
}

/// [_RecentSearches] is the resting state before anything is typed
/// (Requirement 17).
class _RecentSearches extends StatelessWidget {
  const _RecentSearches({
    required this.searches,
    required this.onTap,
    required this.onRemove,
    required this.onClear,
  });

  final List<String> searches;
  final void Function(String query) onTap;
  final void Function(String query) onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (searches.isEmpty) {
      return const _Hint(
        icon: Icons.search_rounded,
        title: 'Search everything',
        message: 'Tasks, finance, bookmarks, watchlist, vault, projects and '
            'documents — all from here.',
      );
    }

    return ListView(
      padding: responsivePadding(context).copyWith(top: 12, bottom: 24),
      children: [
        Row(
          children: [
            Expanded(child: Text('Recent', style: context.texts.labelMedium)),
            TextButton(onPressed: onClear, child: const Text('Clear')),
          ],
        ),
        for (final query in searches)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history_rounded),
            title: Text(query),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => onRemove(query),
            ),
            onTap: () => onTap(query),
          ),
      ],
    );
  }
}

/// [_Results] is the grouped, ranked results (Requirement 17.2).
class _Results extends StatelessWidget {
  const _Results({required this.groups, required this.onTap});

  final List<SearchResultGroup> groups;
  final void Function(SearchResult result) onTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: responsivePadding(context).copyWith(top: 8, bottom: 24),
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(group.module.icon, size: 16, color: context.colors.primary),
                const Gap(8),
                Text(
                  group.module.label,
                  style: context.texts.labelMedium
                      ?.copyWith(color: context.colors.primary),
                ),
                const Gap(6),
                Text(
                  '${group.results.length}',
                  style: context.texts.labelSmall,
                ),
              ],
            ),
          ),
          for (final result in group.results)
            _ResultTile(result: result, onTap: () => onTap(result)),
          const Gap(8),
        ],
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result, required this.onTap});

  final SearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        title: Text(
          result.title.isBlank ? 'Untitled' : result.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: result.subtitle.isBlank
            ? null
            : Text(
                result.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return _Hint(
      icon: Icons.search_off_rounded,
      title: 'No matches',
      message: 'Nothing found for "$query".',
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: responsivePadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: context.colors.onSurfaceVariant),
            const Gap(12),
            Text(title, style: context.texts.titleMedium),
            const Gap(6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.texts.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
