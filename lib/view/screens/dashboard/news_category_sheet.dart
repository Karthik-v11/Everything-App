import 'package:everything_app/bloc/news/news_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/article.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The six news categories, opened from the `›` in the Dashboard's Top Stories
/// header. A sheet rather than a route because news lives on the Dashboard and
/// there is no News destination to navigate to (Requirement 3.9).
Future<void> showNewsCategorySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (_) => BlocProvider.value(
      value: context.read<NewsBloc>(),
      child: const NewsCategorySheet(),
    ),
  );
}

class NewsCategorySheet extends StatelessWidget {
  const NewsCategorySheet({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NewsBloc, NewsState>(
      buildWhen: (previous, current) => previous.category != current.category,
      builder: (context, state) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Top Stories', style: context.texts.titleMedium),
                const Gap(12),
                for (final category in NewsCategory.values)
                  _CategoryTile(
                    category: category,
                    isSelected: category == state.category,
                    onTap: () {
                      context.read<NewsBloc>().add(
                            SelectNewsCategoryEvent(category: category),
                          );
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final NewsCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      title: Text(
        category.label,
        style: context.texts.bodyLarge?.copyWith(
          color: isSelected ? colors.primary : null,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_rounded, size: 20, color: colors.primary)
          : null,
    );
  }
}
