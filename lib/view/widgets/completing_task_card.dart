import 'package:everything_app/bloc/tasks/tasks_bloc.dart';
import 'package:everything_app/data/models/category.dart';
import 'package:everything_app/data/models/project.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/view/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A [TaskCard] that plays its own exit when ticked, for lists a completed task
/// leaves (the Tasks module, the Dashboard agenda).
///
/// Those lists show tasks of one completion state, so the write also drops the
/// row. The exit plays first — tick and grey, slide out, collapse — and the write
/// is dispatched at the end, or the row would vanish mid-tap with no
/// acknowledgement that the tick landed.
///
/// The card is fed a locally completed copy of [task] for the duration: the
/// database row is still pending until the dispatch, but the ring, strikethrough
/// and priority bar must read as done from the moment of the tap
/// (Requirement 4.6).
///
/// Use [TaskCard] directly for lists a completed task stays in, such as the
/// project page.
class CompletingTaskCard extends StatefulWidget {
  const CompletingTaskCard({
    required this.task,
    required this.onTap,
    this.category,
    this.project,
    super.key,
  });

  final Task task;
  final Category? category;
  final Project? project;
  final VoidCallback onTap;

  @override
  State<CompletingTaskCard> createState() => _CompletingTaskCardState();
}

class _CompletingTaskCardState extends State<CompletingTaskCard>
    with SingleTickerProviderStateMixin {
  /// How long the completed card holds still before it leaves, so the tick and
  /// the grey are seen as a result of the tap rather than as part of the exit.
  static const _hold = Duration(milliseconds: 120);

  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// The slide and the collapse overlap: the row is still clearing the edge as
  /// the space under it starts closing, which reads as one movement.
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(1, 0),
  ).animate(
    CurvedAnimation(
      parent: _exit,
      curve: const Interval(0, 0.65, curve: Curves.easeOutCubic),
    ),
  );

  late final Animation<double> _fade = Tween<double>(begin: 1, end: 0).animate(
    CurvedAnimation(parent: _exit, curve: const Interval(0, 0.65)),
  );

  late final Animation<double> _collapse =
      Tween<double>(begin: 1, end: 0).animate(
    CurvedAnimation(
      parent: _exit,
      curve: const Interval(0.45, 1, curve: Curves.easeOutCubic),
    ),
  );

  /// The state the row is leaving towards, or null while it is staying put. It
  /// also latches the row: a second tap mid-exit has nothing left to toggle.
  bool? _leavingAs;

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  Future<void> _onToggle(bool isCompleted) async {
    if (_leavingAs != null) return;

    // With animations off there is no exit to play, and holding the write back
    // for one would only delay the row disappearing.
    if (MediaQuery.disableAnimationsOf(context)) {
      _dispatch(isCompleted);
      return;
    }

    setState(() => _leavingAs = isCompleted);

    await Future<void>.delayed(_hold);
    if (!mounted) return;

    await _exit.forward();
    if (!mounted) return;

    _dispatch(isCompleted);
  }

  void _dispatch(bool isCompleted) => context.read<TasksBloc>().add(
        ToggleTaskCompletionEvent(task: widget.task, isCompleted: isCompleted),
      );

  @override
  Widget build(BuildContext context) {
    final leavingAs = _leavingAs;
    final task = leavingAs == null
        ? widget.task
        : widget.task.copyWith(
            status: leavingAs ? TaskStatus.completed : TaskStatus.pending,
          );

    return SizeTransition(
      sizeFactor: _collapse,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: TaskCard(
            task: task,
            category: widget.category,
            project: widget.project,
            onToggle: _onToggle,
            onTap: widget.onTap,
          ),
        ),
      ),
    );
  }
}
