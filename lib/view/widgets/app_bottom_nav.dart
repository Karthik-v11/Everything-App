import 'dart:ui' show ImageFilter;

import 'package:everything_app/core/utils/extensions.dart';
import 'package:flutter/material.dart';

/// [NavDestination] is one bottom-navigation entry.
class NavDestination {
  const NavDestination({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// [AppBottomNav] is the four-tab bottom navigation.
///
/// The reference UI does not use a Material [NavigationBar]: the tabs are four
/// **detached pills** floating over the background, with the selected pill filled
/// in a lighter grey. This widget reproduces that.
///
/// The bar does not sit *beside* the content, it sits *over* it — the shell sets
/// `extendBody`, so the list underneath scrolls beneath the pills and dissolves
/// into the bar rather than being cut off at its edge. What does the dissolving is
/// [_ProgressiveBlur] plus the scrim over it.
///
/// [currentIndex] is the selected branch; [onSelect] is called with the tapped
/// branch index.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    required this.currentIndex,
    required this.onSelect,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const List<NavDestination> destinations = [
    NavDestination(icon: Icons.home_rounded, label: 'Dashboard'),
    NavDestination(icon: Icons.task_alt_rounded, label: 'Tasks'),
    NavDestination(icon: Icons.inbox_rounded, label: 'Library'),
    NavDestination(icon: Icons.attach_money_rounded, label: 'Finance'),
  ];

  @override
  Widget build(BuildContext context) {
    // The pills are the only child that sizes the stack; the blur fills whatever
    // height they end up needing.
    return Stack(
      children: [
        const Positioned.fill(child: _ProgressiveBlur()),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 28, 12, 8),
            child: Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _NavPill(
                        destination: destinations[i],
                        isSelected: i == currentIndex,
                        onTap: () => onSelect(i),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// [_ProgressiveBlur] is the frosted ramp the content scrolls into.
///
/// A single [BackdropFilter] cannot do this. Its blur is one radius over its whole
/// rect, so however gently the colour on top is faded in, the top edge of the
/// filter is still the line where unblurred content becomes blurred content — the
/// harsh cut this replaces. iOS ramps the *radius*, not just the opacity.
///
/// Flutter has no gradient blur, so the ramp is approximated in bands: each takes
/// an equal slice of the bar's height and blurs only its own slice, at roughly
/// double the radius of the band above it. Doubling is what hides the seams — the
/// step between two adjacent bands is always small relative to the blur either
/// side of it, while the first and last bands are still ~50x apart. The scrim on
/// top then carries the colour from transparent to the surface, so the pills sit
/// on something solid.
///
/// The cost is one saved layer *plus a gaussian pass* per band, every frame the
/// bar is on screen — and because the shell sets `extendBody`, "every frame" means
/// every scroll frame of every module, not just when the bar animates. That makes
/// the band count the single most expensive knob in the app's steady-state render,
/// so it is kept as low as the ramp will tolerate: three bands at a 3.5x ratio
/// still keep every seam small relative to the blur either side of it, while the
/// gradient scrim below carries most of the colour read. The peak sigma is held at
/// 12 rather than 20 — past ~12 the extra radius is invisible under the scrim but
/// the convolution cost keeps climbing, and it is the widest band that dominates a
/// mid-range Android GPU's frame.
class _ProgressiveBlur extends StatelessWidget {
  const _ProgressiveBlur();

  /// Blur radius per band, top to bottom.
  static const List<double> _sigmas = [1, 3.5, 12];

  @override
  Widget build(BuildContext context) {
    final surface = context.colors.surface;

    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            for (final sigma in _sigmas)
              Expanded(
                // Clipped per band, or each filter would sample — and blur — the
                // whole screen behind it instead of its own slice.
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
          ],
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // Weighted late: the top half stays nearly clear so the ramp reads as
              // blur rather than as a block of colour sliding in.
              colors: [
                surface.withValues(alpha: 0),
                surface.withValues(alpha: 0.08),
                surface.withValues(alpha: 0.45),
                surface.withValues(alpha: 0.92),
              ],
              stops: const [0, 0.35, 0.68, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // The selection is the accent fill, not a lighter grey: in the light theme
    // `surfaceContainer` and `surfaceContainerHigh` both resolve to white, which
    // left the selected tab indistinguishable from the other three.
    final background = isSelected ? colors.primary : colors.surfaceContainer;
    final foreground = isSelected ? colors.onPrimary : colors.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: isSelected,
      label: destination.label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: 52,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? colors.primary : colors.outline,
              ),
            ),
            child: Center(
              child: AnimatedScale(
                scale: isSelected ? 1.1 : 1,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: Icon(destination.icon, size: 24, color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
