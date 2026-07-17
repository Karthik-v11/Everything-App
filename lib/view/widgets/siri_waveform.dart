import 'dart:math' as math;

import 'package:everything_app/core/utils/extensions.dart';
import 'package:flutter/material.dart';

/// The "I am listening" bar: four sine waves of differing frequency and speed,
/// summed and scaled by the live mic [level].
///
/// Driven, not decorative — the ribbon goes flat in a silent room, so it never
/// claims to be listening when the mic is shut.
///
/// Earns an [AnimationController] over an implicit widget (CLAUDE.md §12): the
/// motion is a continuous, interruptible phase sweep, not a transition between
/// two states.
class SiriWaveform extends StatefulWidget {
  const SiriWaveform({
    required this.level,
    required this.isListening,
    super.key,
    this.height = 48,
  });

  /// [level] is the mic amplitude, 0..1, already normalised.
  final double level;

  /// [isListening] stops the clock when false, so a closed mic costs nothing.
  final bool isListening;

  final double height;

  @override
  State<SiriWaveform> createState() => _SiriWaveformState();
}

class _SiriWaveformState extends State<SiriWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// [SiriWaveform.level] low-pass filtered. The raw per-frame RMS reading
  /// flickers, and drawn directly the ribbon judders rather than swells.
  double _smoothed = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // Not a §12 duration — nothing completes. It is the period of an ambient
      // phase sweep that repeats for as long as the mic is open.
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.isListening) _controller.repeat();
  }

  @override
  void didUpdateWidget(SiriWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening == oldWidget.isListening) return;

    if (widget.isListening) {
      _controller.repeat();
    } else {
      _controller.stop();
      _smoothed = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduced-motion: the bar still answers to the mic, reporting the level as
    // a static ribbon rather than a travelling wave, so feedback survives.
    final isMotionAllowed = !MediaQuery.disableAnimationsOf(context);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          _smoothed += (widget.level - _smoothed) * 0.18;

          return CustomPaint(
            painter: _SiriWavePainter(
              phase: isMotionAllowed ? _controller.value * 2 * math.pi : 0,
              level: _smoothed,
              color: context.colors.primary,
            ),
          );
        },
      ),
    );
  }
}

class _SiriWavePainter extends CustomPainter {
  const _SiriWavePainter({
    required this.phase,
    required this.level,
    required this.color,
  });

  final double phase;
  final double level;
  final Color color;

  /// (frequency, speed, opacity, amplitude) per ribbon. The speeds are
  /// deliberately not integer multiples: whole-number ratios make the sum repeat
  /// every cycle and the eye reads that as a loop.
  static const List<(double, double, double, double)> _waves = [
    (1.0, 1.0, 0.85, 1.0),
    (2.0, -1.4, 0.5, 0.6),
    (3.0, 0.7, 0.32, 0.4),
    (1.5, -2.1, 0.22, 0.5),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;

    // Idle floor: "listening, hearing silence" must not look like "off".
    final amplitude = (0.06 + level * 0.94) * (size.height / 2) * 0.9;

    for (final (frequency, speed, opacity, scale) in _waves) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: opacity);

      final path = Path();
      for (var x = 0.0; x <= size.width; x += 2) {
        final progress = x / size.width;

        // Sine envelope pinned to zero at both ends, or ribbons terminate
        // mid-swing against the box edge and read as a clipped graph.
        final envelope = math.sin(progress * math.pi);

        final y = midY +
            math.sin(progress * frequency * 2 * math.pi + phase * speed) *
                amplitude *
                scale *
                envelope;

        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SiriWavePainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.level != level ||
      oldDelegate.color != color;
}
