import 'package:everything_app/core/utils/extensions.dart';
import 'package:flutter/material.dart';

/// [FloatingAiDock] is the AI button visible on every screen (Requirement 2.2).
///
/// Tapping the orb opens the AI assistant sheet directly — the unified
/// natural-language entry point for tasks, expenses, notes, bookmarks, and
/// everything else the assistant can create or search.
class FloatingAiDock extends StatelessWidget {
  const FloatingAiDock({
    required this.onAskAI,
    super.key,
  });

  final VoidCallback onAskAI;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      label: 'Open AI assistant',
      child: Material(
        color: colors.surfaceContainerHigh,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onAskAI,
          child: const SizedBox.square(
            dimension: 64,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}
