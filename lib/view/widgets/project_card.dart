import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/project.dart';
import 'package:flutter/material.dart';

/// [ProjectCard] is one project, on the hub or on a parent's screen
/// (Requirement 10).
///
/// [subProjectCount] is shown rather than a total of everything inside, because it
/// is the only number that says something about the *shape* of the project — a
/// count of its tasks would duplicate what the Tasks tab already says, and would
/// need a second query per card to produce.
class ProjectCard extends StatelessWidget {
  const ProjectCard({
    required this.project,
    required this.subProjectCount,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final Project project;
  final int subProjectCount;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    final accent = project.color ?? colors.primary;
    final description = project.description;

    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The project's colour, as a spine down the left edge rather than a
              // dot: it is what tells two projects apart at a glance in a list, and a
              // dot at this size is a smudge.
              Container(width: 3, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              project.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: texts.labelLarge,
                            ),
                            if (description != null &&
                                description.isNotBlank) ...[
                              const Gap(4),
                              Text(
                                description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: texts.bodySmall,
                              ),
                            ],
                            if (subProjectCount > 0) ...[
                              const Gap(8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.account_tree_outlined,
                                    size: 13,
                                    color: colors.onSurfaceVariant,
                                  ),
                                  const Gap(5),
                                  Text(
                                    subProjectCount == 1
                                        ? '1 sub-project'
                                        : '$subProjectCount sub-projects',
                                    style: texts.labelSmall,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Gap(8),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
