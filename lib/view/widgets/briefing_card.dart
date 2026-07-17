import 'dart:math' as math;

import 'package:everything_app/bloc/briefing/briefing_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/view/screens/ai/ai_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [BriefingCard] is the Dashboard's daily briefing (design.md §5.6).
class BriefingCard extends StatelessWidget {
  const BriefingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return BlocBuilder<BriefingBloc, BriefingState>(
      buildWhen: (previous, current) => previous.text != current.text,
      builder: (context, state) {
        return Semantics(
          button: true,
          label: 'Daily briefing. ${state.text} Tap to ask the assistant.',
          child: _GlowBorder(
            child: Material(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(19),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => showAiSheet(context),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Mark(),
                      const Gap(14),
                      // 200ms easeOut, per CLAUDE.md §12: the generated line
                      // replaces the composed one without the card jumping.
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeOut,
                        child: Text(
                          state.text,
                          key: ValueKey(state.text),
                          style: context.texts.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// [_GlowBorder] draws the card's 1.2px outline as a sweep gradient that
/// rotates, plus a soft primary-coloured glow behind the card.
class _GlowBorder extends StatefulWidget {
  const _GlowBorder({required this.child});

  final Widget child;

  @override
  State<_GlowBorder> createState() => _GlowBorderState();
}

class _GlowBorderState extends State<_GlowBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ambient motion: hold the outline still when the platform asks for
    // reduced motion (CLAUDE.md §12).
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: SweepGradient(
              transform: GradientRotation(_controller.value * 2 * math.pi),
              colors: [
                colors.primary.withValues(alpha: 0.15),
                colors.primary.withValues(alpha: 0.85),
                colors.primary.withValues(alpha: 0.15),
                colors.outlineVariant.withValues(alpha: 0.35),
                colors.primary.withValues(alpha: 0.15),
              ],
              stops: const [0.0, 0.15, 0.35, 0.7, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.18),
                blurRadius: 18,
                spreadRadius: -4,
              ),
            ],
          ),
          // The gradient is a border, not a fill: the inset is its width, and
          // the inner surface is what the text actually sits on.
          padding: const EdgeInsets.all(1.2),
          child: child,
        );
      },
    );
  }
}

/// [_Mark] is the asterisk avatar of the reference UI.
class _Mark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surfaceContainerHighest,
        border: Border.all(color: colors.primary.withValues(alpha: 0.6)),
      ),
      child: Icon(Icons.emergency, size: 20, color: colors.onSurface),
    );
  }
}
