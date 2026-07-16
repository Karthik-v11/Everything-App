import 'package:everything_app/bloc/bookmarks/bookmarks_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/bookmark.dart';
import 'package:everything_app/data/models/folder.dart';
import 'package:everything_app/view/widgets/option_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [showBookmarkSheet] opens the save/edit sheet (Requirement 6.1).
///
/// The root navigator, so the sheet covers the bottom navigation and the AI dock
/// rather than being clipped into the shell's body.
Future<void> showBookmarkSheet(BuildContext context, {Bookmark? bookmark}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BookmarkSheet(bookmark: bookmark),
  );
}

/// [BookmarkSheet] saves or edits a bookmark.
///
/// The **URL is the only required field**, and it is the one the caret opens in.
/// Everything else — the title, the source type, the thumbnail — is derived from it
/// the moment it is pasted, so the common case is paste-and-save. The title field
/// shows the derived title as its *hint*, not its text, which is what lets an empty
/// field mean "use the one you worked out" rather than "this bookmark has no name".
class BookmarkSheet extends StatefulWidget {
  const BookmarkSheet({this.bookmark, super.key});

  final Bookmark? bookmark;

  @override
  State<BookmarkSheet> createState() => _BookmarkSheetState();
}

class _BookmarkSheetState extends State<BookmarkSheet> {
  final _url = TextEditingController();
  final _title = TextEditingController();
  final _tags = TextEditingController();

  /// Read once, in [initState]: the folder list does not change while the sheet is
  /// open, and watching the bloc would rebuild the sheet on every keystroke.
  late final List<Folder> _folders;

  String? _folderId;

  /// What the URL currently implies. Recomputed as the URL is typed, because it is
  /// what the title hint and the source pill show.
  UrlMetadata? _derived;

  Bookmark? get _original => widget.bookmark;

  bool get _isEditing => _original != null;

  bool get _isValid => UrlMetadata.isValid(_url.text);

  @override
  void initState() {
    super.initState();

    _folders = context.read<BookmarksBloc>().state.folders;

    final existing = _original;
    if (existing == null) return;

    _url.text = existing.url;
    _title.text = existing.title;
    _tags.text = existing.tags.join(', ');
    _folderId = existing.folderId;
    _derived = UrlMetadata.read(existing.url);
  }

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    _tags.dispose();
    super.dispose();
  }

  /// [_readUrl] re-derives what the link says about itself, on every keystroke —
  /// the source pill and the title hint are the feedback, so they have to move while
  /// the URL is still being typed rather than at save.
  void _readUrl() {
    setState(() {
      _derived = _isValid ? UrlMetadata.read(_url.text) : null;
    });
  }

  void _submit() {
    if (!_isValid) {
      context.showSnack("That doesn't look like a link.", isError: true);
      return;
    }

    final tags = [
      for (final tag in _tags.text.split(','))
        if (tag.trim().isNotEmpty) tag.trim(),
    ];

    final bookmark = Bookmark(
      id: _original?.id ?? '',
      url: _url.text.trim(),
      // Blank is not an error: the service fills it in from the URL, which is what
      // the hint has been showing all along.
      title: _title.text.trim(),
      thumbnailUrl: _original?.thumbnailUrl,
      sourceType: _derived?.source ?? BookmarkSource.website,
      tags: tags,
      folderId: _folderId,
      savedAt: _original?.savedAt ?? DateTime.now(),
    );

    context.read<BookmarksBloc>().add(
          SaveBookmarkEvent(bookmark: bookmark, isEditing: _isEditing),
        );

    Navigator.of(context).pop();
  }

  void _delete() {
    context.read<BookmarksBloc>().add(
          DeleteBookmarkEvent(id: _original!.id),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final source = _derived?.source;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _url,
                autofocus: !_isEditing,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                style: context.texts.titleMedium,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Paste a link',
                  prefixIcon: source == null
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            source.icon,
                            size: 20,
                            color: colors.primary,
                          ),
                        ),
                  prefixIconConstraints: const BoxConstraints(),
                ),
                onChanged: (_) => _readUrl(),
              ),
              const Gap(6),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  // The derived title as a *hint*, so leaving it alone accepts it and
                  // the field never has to be cleared to get the right answer.
                  hintText: _derived?.title ?? 'Title',
                ),
                onSubmitted: (_) => _submit(),
              ),
              const Gap(12),
              TextField(
                controller: _tags,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(
                  hintText: 'Tags, comma separated',
                  isDense: true,
                ),
                onSubmitted: (_) => _submit(),
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          OptionPillMenu<String>(
                            icon: Icons.folder_outlined,
                            label: _folderName ?? 'Folder',
                            isSet: _folderId != null,
                            accent: colors.primary,
                            onSelected: (id) => setState(
                              () => _folderId = id.isEmpty ? null : id,
                            ),
                            entries: [
                              const PillOption(
                                value: '',
                                label: 'No folder',
                                icon: Icons.folder_off_outlined,
                              ),
                              if (_folders.isNotEmpty) const PillDivider(),
                              for (final folder in _folders)
                                PillOption(
                                  value: folder.id,
                                  label: folder.name,
                                  icon: Icons.folder_outlined,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Gap(8),
                  SizedBox.square(
                    dimension: 44,
                    child: IconButton.filled(
                      onPressed: _isValid ? _submit : null,
                      tooltip: 'Save bookmark',
                      style: IconButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        disabledBackgroundColor: colors.surfaceContainerHighest,
                        disabledForegroundColor: colors.onSurfaceVariant,
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                    ),
                  ),
                ],
              ),
              if (_isEditing) ...[
                const Gap(4),
                TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete bookmark'),
                  style: TextButton.styleFrom(foregroundColor: colors.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String? get _folderName {
    for (final folder in _folders) {
      if (folder.id == _folderId) return folder.name;
    }
    return null;
  }
}
