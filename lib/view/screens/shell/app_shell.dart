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

  /// [_onSelect] switches branches.
  ///
  /// `initialLocation: true` only when the already-selected tab is tapped again,
  /// which pops that branch to its root. Passing it on every switch would reset
  /// each tab's stack, which is the state [StatefulShellRoute] exists to keep.
  void _onSelect(int index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The body runs the full height of the screen, under the navigation, so
      // content scrolls beneath the bar's blur instead of stopping at its edge.
      // Every scrolling module pads its own bottom to clear the dock.
      extendBody: true,
      body: navigationShell,
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
