import 'dart:async';

import 'package:everything_app/bloc/bookmarks/bookmarks_bloc.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/bookmark.dart';
import 'package:everything_app/view/screens/library/bookmark_sheet.dart';
import 'package:everything_app/view/widgets/app_choice_chip.dart';
import 'package:everything_app/view/widgets/bookmark_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

/// [BookmarksPage] is the saved links (Requirement 6).
///
/// Tapping a card **opens the link**; editing is the long-press and the trailing
/// button. A bookmark exists to be followed, and making the common action the
/// primary one is what keeps this from being a list you have to work through a menu
/// to use.
class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  final _search = TextEditingController();

  /// One filter pass per pause, not per keystroke.
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(kSearchDebounce, () {
      if (!mounted) return;
      context.read<BookmarksBloc>().add(SearchBookmarksEvent(query: query));
    });
  }

  /// [_open] follows the link in the device's browser.
  ///
  /// Not a webview: the page belongs to its publisher, and wrapping it in this app's
  /// chrome would make the app look answerable for it — the same call the Dashboard's
  /// news headlines make (Requirement 3.10).
  Future<void> _open(Bookmark bookmark) async {
    final uri = Uri.tryParse(bookmark.url);

    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      context.showSnack('Could not open that link.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookmarks'),
        actions: [
          IconButton(
            onPressed: () => showBookmarkSheet(context),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Save a link',
          ),
        ],
      ),
      body: BlocConsumer<BookmarksBloc, BookmarksState>(
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
          if (state.isLoading && state.bookmarks.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final visible = state.visibleBookmarks;

          return Column(
            children: [
              Padding(
                padding: responsivePadding(context).copyWith(top: 4, bottom: 8),
                child: _SearchField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                ),
              ),
              _Filters(state: state),
              Expanded(
                child: visible.isEmpty
                    ? _Empty(isFiltered: state.isFiltered)
                    : ListView.separated(
                        padding: responsivePadding(context)
                            .copyWith(top: 8, bottom: 120),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const Gap(8),
                        itemBuilder: (context, index) {
                          final bookmark = visible[index];

                          return BookmarkCard(
                            bookmark: bookmark,
                            folder: state.folderOf(bookmark),
                            onOpen: () => _open(bookmark),
                            onTap: () =>
                                showBookmarkSheet(context, bookmark: bookmark),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: const InputDecoration(
        hintText: 'Search title, link or tag',
        prefixIcon: Icon(Icons.search_rounded, size: 18),
        isDense: true,
      ),
    );
  }
}

/// [_Filters] is the source chips and the folder chips.
///
/// Only the sources the user actually has bookmarks in appear — a row offering
/// "Reddit (0)" is a row of dead ends.
class _Filters extends StatelessWidget {
  const _Filters({required this.state});

  final BookmarksState state;

  @override
  Widget build(BuildContext context) {
    final sources = state.sources;
    if (sources.isEmpty && state.folders.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: responsivePadding(context),
        children: [
          for (final source in sources) ...[
            AppChoiceChip(
              label: '${source.label} ${state.countOf(source)}',
              isSelected: state.source == source,
              avatarIcon: source.icon,
              onSelected: (isSelected) => context.read<BookmarksBloc>().add(
                    FilterBookmarksEvent(
                      source: isSelected ? source : null,
                      folderId: state.folderId,
                    ),
                  ),
            ),
            const Gap(8),
          ],
          for (final folder in state.folders) ...[
            AppChoiceChip(
              label: folder.name,
              isSelected: state.folderId == folder.id,
              avatarIcon: Icons.folder_outlined,
              onSelected: (isSelected) => context.read<BookmarksBloc>().add(
                    FilterBookmarksEvent(
                      source: state.source,
                      folderId: isSelected ? folder.id : null,
                    ),
                  ),
            ),
            const Gap(8),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.isFiltered});

  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isFiltered ? 'Nothing matched' : 'No bookmarks yet',
              style: context.texts.titleMedium,
            ),
            const Gap(6),
            Text(
              isFiltered
                  ? 'Try a different search or clear the filters.'
                  : 'Paste a link and it is saved with its title, '
                      'icon and preview.',
              textAlign: TextAlign.center,
              style: context.texts.bodySmall,
            ),
            if (!isFiltered) ...[
              const Gap(16),
              FilledButton.icon(
                onPressed: () => showBookmarkSheet(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Save a link'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
