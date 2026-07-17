import 'package:everything_app/core/utils/extensions.dart';
import 'package:flutter/material.dart';

/// [NavDestination] is one bottom-navigation entry.
class NavDestination {
  const NavDestination({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// The four-tab bottom navigation: a single floating pill holding all four
/// icons, with the AI orb detached beside it ([FloatingAiDock], in the shell's
/// FAB slot).
///
/// There are no visible labels, which is what makes each icon's [Semantics] label
/// mandatory rather than merely good manners (CLAUDE.md §9).
///
/// The bar sits over the content (the shell sets `extendBody`) and the pill is
/// opaque, so modules must clear it with their own bottom padding.
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

  static const double _height = 60;
  static const double _radius = 28;

  /// Gap between the bar's edge and the selected slot's indicator well.
  static const double indicatorInset = 8;

  /// Concentric with the bar's own corners: the bar's radius less the inset.
  static const double indicatorRadius = _radius - indicatorInset;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _NavIcon(
                    destination: destinations[i],
                    isSelected: i == currentIndex,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One icon inside the pill, wrapped in its own indicator well that fills in
/// when selected.
///
/// Selection motion is limited to a colour cross-fade and a small scale so a tab
/// switch is never something the user waits on (CLAUDE.md §12).
class _NavIcon extends StatelessWidget {
  const _NavIcon({
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

    return Semantics(
      button: true,
      selected: isSelected,
      label: destination.label,
      child: GestureDetector(
        onTap: onTap,
             
        child: Container(
          decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppBottomNav.indicatorRadius),
          ),
          padding: const EdgeInsets.all(AppBottomNav.indicatorInset),
          // `surface` is the page background: darker than the bar's own fill in
          // the dark/amoled variants, so the selected slot reads as a recessed
          // well like the iOS bar. The radius is the bar's less the inset, which
          // keeps the well's corners concentric with the bar's.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: isSelected ? colors.surface : Colors.transparent,
              borderRadius:
                  BorderRadius.circular(AppBottomNav.indicatorRadius),
            ),
            child: Center(
              child: AnimatedScale(
                scale: isSelected ? 1.08 : 1,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: TweenAnimationBuilder<Color?>(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  tween: ColorTween(
                    end: isSelected ? colors.primary : colors.onSurfaceVariant,
                  ),
                  builder: (context, color, _) =>
                      Icon(destination.icon, size: 24, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
