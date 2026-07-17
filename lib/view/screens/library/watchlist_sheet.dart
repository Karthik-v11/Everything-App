import 'package:everything_app/bloc/watchlist/watchlist_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/watchlist_item.dart';
import 'package:everything_app/view/widgets/option_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [showWatchlistSheet] opens the add/edit sheet (Requirement 8.1).
Future<void> showWatchlistSheet(BuildContext context, {WatchlistItem? item}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => WatchlistSheet(item: item),
  );
}

/// [WatchlistSheet] adds or edits a tracked title.
///
/// The progress and total fields appear only for the types that have them: a movie
/// is watched or it is not, and asking how many episodes of it there are would be
/// asking a question with no answer.
class WatchlistSheet extends StatefulWidget {
  const WatchlistSheet({this.item, super.key});

  final WatchlistItem? item;

  @override
  State<WatchlistSheet> createState() => _WatchlistSheetState();
}

class _WatchlistSheetState extends State<WatchlistSheet> {
  final _title = TextEditingController();
  final _progress = TextEditingController();
  final _total = TextEditingController();

  late MediaType _mediaType;
  late WatchStatus _status;

  double? _rating;

  WatchlistItem? get _original => widget.item;

  bool get _isEditing => _original != null;

  @override
  void initState() {
    super.initState();

    final existing = _original;

    if (existing == null) {
      _mediaType = MediaType.movie;
      _status = WatchStatus.wishlist;
      return;
    }

    _title.text = existing.title;
    _mediaType = existing.mediaType;
    _status = existing.status;
    _rating = existing.rating;
    _progress.text = existing.currentProgress?.toString() ?? '';
    _total.text = existing.total?.toString() ?? '';
  }

  @override
  void dispose() {
    _title.dispose();
    _progress.dispose();
    _total.dispose();
    super.dispose();
  }

  void _submit() {
    if (_title.text.isBlank) {
      context.showSnack('What are you tracking?', isError: true);
      return;
    }

    final total = int.tryParse(_total.text.trim());
    final progress = int.tryParse(_progress.text.trim());

    // The total goes into the field its media type is actually measured against —
    // chapters for a manga or a book, episodes for everything else. Writing it to
    // both would leave two numbers that could disagree the moment the type changed.
    final item = WatchlistItem(
      id: _original?.id ?? '',
      title: _title.text.trim(),
      mediaType: _mediaType,
      status: _status,
      rating: _rating,
      currentProgress: _mediaType.hasProgress ? progress : null,
      totalEpisodes: _mediaType.countsChapters ? null : total,
      totalChapters: _mediaType.countsChapters ? total : null,
      completedAt: _original?.completedAt,
      createdAt: _original?.createdAt ?? DateTime.now(),
    );

    context.read<WatchlistBloc>().add(
          SaveWatchlistItemEvent(item: item, isEditing: _isEditing),
        );

    Navigator.of(context).pop();
  }

  void _delete() {
    context.read<WatchlistBloc>().add(
          DeleteWatchlistItemEvent(id: _original!.id),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

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
                controller: _title,
                autofocus: !_isEditing,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                style: context.texts.titleMedium,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'What are you tracking?',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const Gap(12),
              _TypeRow(
                mediaType: _mediaType,
                onSelected: (type) => setState(() {
                  _mediaType = type;
                  // Progress means nothing for a movie, so switching to one drops the
                  // numbers rather than leaving them to be silently saved as null.
                  if (!type.hasProgress) {
                    _progress.clear();
                    _total.clear();
                  }
                }),
              ),
              if (_mediaType.hasProgress) ...[
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _progress,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          hintText: 'On ${_mediaType.unit}',
                          isDense: true,
                        ),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: TextField(
                        controller: _total,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          hintText: 'of ${_mediaType.unit}s',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const Gap(12),
              _Rating(
                rating: _rating,
                onChanged: (value) => setState(() => _rating = value),
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
                          OptionPillMenu<WatchStatus>(
                            icon: Icons.flag_outlined,
                            label: _status.label,
                            isSet: _status != WatchStatus.wishlist,
                            accent: colors.primary,
                            onSelected: (value) =>
                                setState(() => _status = value),
                            entries: [
                              for (final value in WatchStatus.values)
                                PillOption(value: value, label: value.label),
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
                      onPressed: _title.text.isBlank ? null : _submit,
                      tooltip: 'Save entry',
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
                  label: const Text('Delete entry'),
                  style: TextButton.styleFrom(foregroundColor: colors.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// [_TypeRow] is the six media types (Requirement 8.1).
class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.mediaType, required this.onSelected});

  final MediaType mediaType;
  final ValueChanged<MediaType> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: MediaType.values.length,
        separatorBuilder: (_, _) => const Gap(8),
        itemBuilder: (context, index) {
          final value = MediaType.values[index];
          final isSelected = value == mediaType;

          return Semantics(
            button: true,
            selected: isSelected,
            child: GestureDetector(
              onTap: () => onSelected(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? colors.primary : colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected ? colors.primary : colors.outline,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      value.icon,
                      size: 15,
                      color: isSelected
                          ? colors.onPrimary
                          : colors.onSurfaceVariant,
                    ),
                    const Gap(6),
                    Text(
                      value.label,
                      style: context.texts.labelMedium?.copyWith(
                        color: isSelected
                            ? colors.onPrimary
                            : colors.onSurfaceVariant,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// [_Rating] is the 0–10 score, as a slider.
///
/// A slider rather than ten stars: the scale is out of ten, and ten tappable stars
/// on a phone is a row of targets too small to hit the one you meant. Tapping the
/// label clears it, because "unrated" is a real answer and a slider alone cannot
/// express it.
class _Rating extends StatelessWidget {
  const _Rating({required this.rating, required this.onChanged});

  final double? rating;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = rating;

    return Row(
      children: [
        Icon(
          Icons.star_rounded,
          size: 16,
          color: value == null ? colors.onSurfaceVariant : colors.primary,
        ),
        const Gap(8),
        Expanded(
          child: Slider(
            value: value ?? 0,
            max: 10,
            divisions: 20,
            label: value?.toStringAsFixed(1) ?? 'Unrated',
            onChanged: onChanged,
          ),
        ),
        const Gap(4),
        TextButton(
          onPressed: value == null ? null : () => onChanged(null),
          child: Text(
            value == null ? 'Unrated' : value.toStringAsFixed(1),
            style: context.texts.labelMedium,
          ),
        ),
      ],
    );
  }
}
