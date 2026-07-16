import 'package:everything_app/core/utils/app_colors.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/models/category.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:flutter/material.dart';

/// [TaskCard] is one row in the task list (Requirement 4.3).
///
/// Matches the reference UI: a round checkbox, the title, a due-status line and a
/// category chip beneath it, and a priority marker on the right.
///
/// [task] is the task. [category] is its resolved category, or null.
/// [onToggle] fires with the new completion state. [onTap] opens the task.
class TaskCard extends StatelessWidget {
  const TaskCard({
    required this.task,
    required this.onToggle,
    required this.onTap,
    this.category,
    super.key,
  });

  final Task task;
  final Category? category;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: task.isCompleted,
              onChanged: (value) => onToggle(value ?? false),
            ),
            const SizedBox(width: 8),
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
                      decoration:
                          task.isCompleted ? TextDecoration.lineThrough : null,
                      color: task.isCompleted ? colors.onSurfaceVariant : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _MetaRow(task: task, category: category),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _PriorityMarker(priority: task.priority),
          ],
        ),
      ),
    );
  }
}

/// [_MetaRow] is the due-status and category line under the title.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.task, required this.category});

  final Task task;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final due = task.dueDate;
    final isOverdue = task.isOverdue;

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (due != null)
          _Meta(
            icon: isOverdue
                ? Icons.event_busy_rounded
                : Icons.calendar_today_rounded,
            label: isOverdue ? 'Overdue' : due.relativeLabel,
            color: isOverdue ? AppColors.overdue : colors.onSurfaceVariant,
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
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: context.texts.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// [_PriorityMarker] is the coloured badge on the right of the card.
class _PriorityMarker extends StatelessWidget {
  const _PriorityMarker({required this.priority});

  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${priority.name.capitalized} priority',
      child: Icon(Icons.brightness_1_rounded, size: 14, color: priority.color),
    );
  }
}
