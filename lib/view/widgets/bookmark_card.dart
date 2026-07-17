import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/bookmark.dart';
import 'package:everything_app/data/models/folder.dart';
import 'package:flutter/material.dart';

/// [BookmarkCard] is one saved link (Requirement 6).
///
/// The thumbnail is the one thing on this screen that comes from the network, and
/// it is the one thing allowed to be missing: `errorBuilder` falls back to the
/// source's icon, so a bookmark saved offline, or one whose image has since 404'd,
/// looks deliberate rather than broken. There is no loading spinner for the same
/// reason — a grid of spinners is worse than a grid of icons that fill in.
class BookmarkCard extends StatelessWidget {
  const BookmarkCard({
    required this.bookmark,
    required this.folder,
    required this.onTap,
    required this.onOpen,
    super.key,
  });

  final Bookmark bookmark;
  final Folder? folder;

  /// Edit — the sheet.
  final VoidCallback onTap;

  /// Open the link in the browser. The card's primary action: a bookmark exists to
  /// be followed, and editing it is the rarer thing.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumbnail(bookmark: bookmark),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      bookmark.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: texts.labelLarge,
                    ),
                    const Gap(5),
                    Row(
                      children: [
                        Icon(
                          bookmark.sourceType.icon,
                          size: 12,
                          color: colors.onSurfaceVariant,
                        ),
                        const Gap(5),
                        Flexible(
                          child: Text(
                            bookmark.host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: texts.labelSmall,
                          ),
                        ),
                        if (folder != null) ...[
                          const Gap(8),
                          Icon(
                            Icons.folder_outlined,
                            size: 12,
                            color: colors.onSurfaceVariant,
                          ),
                          const Gap(4),
                          Flexible(
                            child: Text(
                              folder!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: texts.labelSmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (bookmark.tags.isNotEmpty) ...[
                      const Gap(8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final tag in bookmark.tags)
                            _Tag(label: tag),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Gap(4),
              IconButton(
                onPressed: onTap,
                icon: const Icon(Icons.more_horiz_rounded, size: 18),
                color: colors.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
                tooltip: 'Edit bookmark',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [_Thumbnail] is the preview image, or the source's icon when there is none.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.bookmark});

  final Bookmark bookmark;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final url = bookmark.thumbnailUrl;

    final fallback = Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        bookmark.sourceType.icon,
        size: 22,
        color: colors.onSurfaceVariant,
      ),
    );

    if (url == null || url.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        // Decode to the display box rather than the source resolution.
        cacheWidth: (_size * MediaQuery.devicePixelRatioOf(context)).round(),
        // No spinner and no error state: offline, the image simply never arrives
        // and the icon is what the card was always going to show.
        errorBuilder: (context, error, stackTrace) => fallback,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            frame == null && !wasSynchronouslyLoaded ? fallback : child,
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: context.texts.labelSmall?.copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }
}
