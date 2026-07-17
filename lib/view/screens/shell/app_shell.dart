import 'package:everything_app/view/screens/ai/ai_sheet.dart';
import 'package:everything_app/view/widgets/app_bottom_nav.dart';
import 'package:everything_app/view/widgets/floating_ai_dock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// [AppShell] is the persistent chrome around the four modules: the bottom
/// navigation and the floating AI dock.
///
/// The dock lives here rather than in each module, so it is visible on every
/// screen (Requirement 2.2).
///
/// [navigationShell] is supplied by [StatefulShellRoute.indexedStack] and owns
/// the four branch navigators.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// Minimum horizontal fling velocity (px/s) that counts as a tab swipe.
  /// Below this the gesture is treated as an accidental drag and ignored.
  static const double _swipeVelocity = 240;

  /// [_onSelect] switches branches.
  ///
  /// `initialLocation: true` only when the already-selected tab is tapped again,
  /// which pops that branch to its root. Passing it on every switch would reset
  /// each tab's stack, which is the state [StatefulShellRoute] exists to keep.
  void _onSelect(int index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );

  /// A fling past [_swipeVelocity] moves one tab in the fling's direction.
  ///
  /// Swiping right (positive velocity) moves to the previous tab, matching the
  /// bar's left-to-right order. Out-of-range targets are dropped rather than
  /// wrapped, so the edge tabs feel like edges.
  void _onSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < _swipeVelocity) return;

    final target = navigationShell.currentIndex + (velocity < 0 ? 1 : -1);
    if (target < 0 || target >= AppBottomNav.destinations.length) return;

    navigationShell.goBranch(target);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The body runs the full height of the screen, under the navigation, so
      // content scrolls beneath the bar's blur instead of stopping at its edge.
      // Every scrolling module pads its own bottom to clear the dock.
      extendBody: true,
      // The detector loses the arena to any horizontal scrollable inside a
      // module, so a carousel still scrolls without switching tabs.
      body: GestureDetector(
        onHorizontalDragEnd: _onSwipe,
        child: navigationShell,
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: navigationShell.currentIndex,
        onSelect: _onSelect,
      ),
      floatingActionButton: FloatingAiDock(
        onAskAI: () => showAiSheet(context),
      ),
    );
  }
}
