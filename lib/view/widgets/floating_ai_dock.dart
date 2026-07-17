import 'package:everything_app/core/utils/extensions.dart';
import 'package:flutter/material.dart';

/// The app's mark for the assistant.
///
/// A constant rather than an inline [Icon]: the briefing card wears the same mark
/// to say its prose and the assistant behind the orb are one entity.
const IconData kAiGlyph = Icons.emergency;

/// The AI button visible on every screen (Requirement 2.2). Tapping the orb opens
/// the assistant sheet — the unified natural-language entry point.
///
/// It rests in the accent colour so it reads as an action rather than a fifth
/// tab. [ColorScheme.onPrimary] on the default red measures 4.69:1, so the glyph
/// clears AA on the accent it is most likely to be seen against.
///
/// The orb breathes: a slow ambient halo, not a §12 transition — it is the one
/// control not attached to the screen it sits on, and the pulse says the
/// assistant is reachable from anywhere. A transform and an opacity over a single
/// circle, so it repaints the halo alone and lays nothing out.
class FloatingAiDock extends StatefulWidget {
  const FloatingAiDock({
    required this.onAskAI,
    super.key,
  });

  final VoidCallback onAskAI;

  @override
  State<FloatingAiDock> createState() => _FloatingAiDockState();
}

class _FloatingAiDockState extends State<FloatingAiDock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Read here rather than in [initState] so that turning the system setting on
    // while the app is open stops the pulse (CLAUDE.md §12).
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
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

    return Semantics(
      button: true,
      label: 'Open AI assistant',
      child: SizedBox.square(
        dimension: 64,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // The halo must not take the tap the orb is there to receive.
            IgnorePointer(
              child: _PulseHalo(animation: _controller, color: colors.primary),
            ),
            Material(
              color: colors.primary,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onAskAI,
                child: SizedBox.square(
                  dimension: 64,
                  child: Icon(kAiGlyph, size: 30, color: colors.onPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ring that swells out from under the orb and fades.
class _PulseHalo extends StatelessWidget {
  const _PulseHalo({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      // Built once and reused on every frame.
      child: const SizedBox.square(dimension: 64),
      builder: (context, child) {
        final t = Curves.easeOut.transform(animation.value);

        return Transform.scale(
          scale: 1 + t * 0.45,
          // The fade is folded into the colour rather than wrapped in an
          // `Opacity`, which would cost a saveLayer on every frame of the loop.
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: color.a * (1 - t) * 0.35),
              shape: BoxShape.circle,
            ),
            child: child,
          ),
        );
      },
    );
  }
}
