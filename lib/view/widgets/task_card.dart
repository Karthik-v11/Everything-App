import 'package:clock/clock.dart';
import 'package:everything_app/core/utils/app_colors.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/models/category.dart';
import 'package:everything_app/data/models/project.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:flutter/material.dart';

/// One row in the task list (Requirement 4.3): title, a due-status line and a
/// category chip beneath it, and an urgency-tinted check ring on the right.
///
/// The ring is hand-drawn rather than a Material [Checkbox] because it is tinted
/// by urgency. Its semantics are declared explicitly, so it is still a checkbox
/// to a screen reader.
///
/// Shared with the Tasks module and restyled in place rather than forked, so the
/// card behaves identically on every screen (Requirement 3.5).
///
/// [task] is the task. [category] is its resolved category, or null. [project] is
/// the project it is filed under, or null when it is unfiled.
/// [onToggle] fires with the new completion state. [onTap] opens the task.
class TaskCard extends StatelessWidget {
  const TaskCard({
    required this.task,
    required this.onToggle,
    required this.onTap,
    this.category,
    this.project,
    super.key,
  });

  final Task task;
  final Category? category;
  final Project? project;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final priority = taskPriorityColor(task);
    final deadline = taskDeadlineColor(context, task);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),        
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            color: task.isCompleted ? priority.withValues(alpha: 0.35) : priority,
            padding: const EdgeInsets.only(left: 4),
            child: Material(
              color: colors.surfaceContainer,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              task.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: texts.titleMedium?.copyWith(
                                decoration: task.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: task.isCompleted
                                    ? colors.onSurfaceVariant
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _MetaRow(
                              task: task,
                              category: category,
                              project: project,
                              deadline: deadline,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _CheckRing(
                        isCompleted: task.isCompleted,
                        color: priority,
                        onToggle: onToggle,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The fixed colour of a task's priority (Requirement 4.4). A completed task
/// drops to grey so a finished P1 does not compete with an open one.
Color taskPriorityColor(Task task) =>
    task.isCompleted ? AppColors.darkTextSecondary : task.priority.color;

/// The colour of the row's due-status line. Tracks the deadline, not the
/// priority — the two are deliberately allowed to disagree, so a low-priority
/// task that is late still reads as late.
///
/// Per-day and read off [clock] to match [DateTimeX.dueStatus]: the colour and
/// the words it tints must never disagree.
Color taskDeadlineColor(BuildContext context, Task task) {
  final due = task.dueDate;
  if (task.isCompleted || due == null) return context.colors.onSurfaceVariant;

  final today = clock.now().dateOnly;
  if (due.dateOnly.isBefore(today)) return AppColors.overdue;
  if (due.dateOnly == today) return AppColors.warning;
  if (due.dateOnly.difference(today).inDays <= 2) return AppColors.priorityLow;

  return context.colors.onSurfaceVariant;
}

/// [_MetaRow] is the due-status, project and category line under the title.
class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.task,
    required this.category,
    required this.project,
    required this.deadline,
  });

  final Task task;
  final Category? category;
  final Project? project;
  final Color deadline;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final due = task.dueDate;
    // The time is only shown on the due day itself; on any other day "Due in 3
    // days" is all it would convey.
    final showTime = due != null &&
        due.dateOnly == clock.now().dateOnly &&
        !task.isCompleted;

    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (due != null)
          Text(
            due.dueStatus,
            style: context.texts.labelSmall?.copyWith(
              color: deadline,
              fontWeight: task.isOverdue ? FontWeight.w700 : null,
            ),
          ),
        if (showTime)
          _Meta(
            icon: Icons.schedule_rounded,
            label: due.timeLabel,
            color: deadline,
          ),
        // Project precedes category: it is the coarser bucket and the one the
        // user chose by hand.
        if (project != null)
          _Meta(
            icon: Icons.workspaces_outline,
            label: project!.name,
            color: project!.color ?? colors.onSurfaceVariant,
          ),
        if (category != null)
          _Meta(
            icon: Icons.label_rounded,
            label: category!.name,
            color: category!.color,
          ),
        if (task.subtaskProgress != null)
          _Meta(
            icon: Icons.checklist_rounded,
            label: task.subtaskProgress!,
            color: colors.onSurfaceVariant,
          ),
        if (task.isRecurring)
          _Meta(
            icon: Icons.repeat_rounded,
            label: task.recurrence!.frequency.name.capitalized,
            color: colors.onSurfaceVariant,
          ),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: context.texts.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// The urgency-tinted circle.
///
/// Completing is a local database write, so the fill is immediate and the
/// animation only overlays state that has already been applied (CLAUDE.md §12).
class _CheckRing extends StatelessWidget {
  const _CheckRing({
    required this.isCompleted,
    required this.color,
    required this.onToggle,
  });

  final bool isCompleted;
  final Color color;
  final ValueChanged<bool> onToggle;

  static const double _size = 26;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: isCompleted,
      label: 'Completed',
      child: InkWell(
        onTap: () => onToggle(!isCompleted),
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted ? color : Colors.transparent,
              border: Border.all(color: color, width: 1.6),
            ),
            child: AnimatedScale(
              scale: isCompleted ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: Icon(
                Icons.check_rounded,
                size: 16,
                color: context.colors.surfaceContainer,
              ),
            ), 
          ),
        ),
      ),
    );
  }
}
