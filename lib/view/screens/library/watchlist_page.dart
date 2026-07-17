import 'dart:async';

import 'package:everything_app/bloc/watchlist/watchlist_bloc.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/watchlist_item.dart';
import 'package:everything_app/view/screens/library/watchlist_sheet.dart';
import 'package:everything_app/view/widgets/app_choice_chip.dart';
import 'package:everything_app/view/widgets/watchlist_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [WatchlistPage] tracks movies, series, anime, manga, books and games
/// (Requirement 8).
class WatchlistPage extends StatefulWidget {
  const WatchlistPage({super.key});

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  final _search = TextEditingController();

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
      context.read<WatchlistBloc>().add(SearchWatchlistEvent(query: query));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watchlist'),
        actions: [
          IconButton(
            onPressed: () => showWatchlistSheet(context),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Track something',
                                  color: context.colors.primary,

          ),
        ],
      ),
      body: BlocConsumer<WatchlistBloc, WatchlistState>(
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
          if (state.isLoading && state.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final visible = state.visibleItems;

          return Column(
            children: [
              Padding(
                padding: responsivePadding(context).copyWith(top: 4, bottom: 8),
                child: TextField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Search your watchlist',
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    isDense: true,
                  ),
                ),
              ),
              _StatusFilters(state: state),
              _TypeFilters(state: state),
              Expanded(
                child: visible.isEmpty
                    ? _Empty(isFiltered: state.isFiltered)
                    : ListView.separated(
                        padding: responsivePadding(context)
                            .copyWith(top: 8, bottom: 120),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const Gap(8),
                        itemBuilder: (context, index) {
                          final item = visible[index];

                          return WatchlistCard(
                            item: item,
                            onTap: () =>
                                showWatchlistSheet(context, item: item),
                            // One tap is one more episode. The clamp and the
                            // auto-complete at the total are the model's, so this
                            // can just say "one more" and be right.
                            onIncrement: () =>
                                context.read<WatchlistBloc>().add(
                                      SetWatchlistProgressEvent(
                                        item: item,
                                        progress:
                                            (item.currentProgress ?? 0) + 1,
                                      ),
                                    ),
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

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({required this.state});

  final WatchlistState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: responsivePadding(context),
        children: [
          for (final status in WatchStatus.values) ...[
            AppChoiceChip(
              label: '${status.label} ${state.countOfStatus(status)}',
              isSelected: state.status == status,
              onSelected: (isSelected) => context.read<WatchlistBloc>().add(
                    FilterWatchlistEvent(
                      status: isSelected ? status : null,
                      mediaType: state.mediaType,
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

/// [_TypeFilters] shows only the media types the user actually has entries in.
class _TypeFilters extends StatelessWidget {
  const _TypeFilters({required this.state});

  final WatchlistState state;

  @override
  Widget build(BuildContext context) {
    final types = state.mediaTypes;
    if (types.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: responsivePadding(context),
        children: [
          for (final type in types) ...[
            AppChoiceChip(
              label: type.label,
              isSelected: state.mediaType == type,
              avatarIcon: type.icon,
              onSelected: (isSelected) => context.read<WatchlistBloc>().add(
                    FilterWatchlistEvent(
                      mediaType: isSelected ? type : null,
                      status: state.status,
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
              isFiltered ? 'Nothing matched' : 'Nothing tracked yet',
              style: context.texts.titleMedium,
            ),
            const Gap(6),
            Text(
              isFiltered
                  ? 'Try a different search or clear the filters.'
                  : 'Movies, series, anime, manga, books and games — '
                      'with where you got to.',
              textAlign: TextAlign.center,
              style: context.texts.bodySmall,
            ),
            if (!isFiltered) ...[
              const Gap(16),
              FilledButton.icon(
                onPressed: () => showWatchlistSheet(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Track something'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
