import 'dart:async';

import 'package:everything_app/bloc/auth/auth_bloc.dart';
import 'package:everything_app/core/route/routes.dart';
import 'package:everything_app/debug/navigation_observer.dart';
import 'package:everything_app/view/screens/auth/lock_page.dart';
import 'package:everything_app/view/screens/dashboard/dashboard_page.dart';
import 'package:everything_app/view/screens/dashboard/weather_page.dart';
import 'package:everything_app/view/screens/finance/accounts_page.dart';
import 'package:everything_app/view/screens/finance/budgets_page.dart';
import 'package:everything_app/view/screens/finance/finance_page.dart';
import 'package:everything_app/view/screens/finance/transactions_page.dart';
import 'package:everything_app/view/screens/library/bookmarks_page.dart';
import 'package:everything_app/view/screens/library/document_page.dart';
import 'package:everything_app/view/screens/library/library_page.dart';
import 'package:everything_app/view/screens/library/project_page.dart';
import 'package:everything_app/view/screens/library/to_buy_page.dart';
import 'package:everything_app/view/screens/library/vault_page.dart';
import 'package:everything_app/view/screens/library/watchlist_page.dart';
import 'package:everything_app/view/screens/search/search_page.dart';
import 'package:everything_app/view/screens/settings/settings_page.dart';
import 'package:everything_app/view/screens/shell/app_shell.dart';
import 'package:everything_app/view/screens/tasks/tasks_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// [AppRouter] is the app's GoRouter configuration.
///
/// The four modules live inside a [StatefulShellRoute.indexedStack]: each branch
/// keeps its own [Navigator] alive across tab switches, which preserves scroll
/// position and navigation stack (Requirement 2.4). A plain `ShellRoute` rebuilds
/// the branch on every switch and loses both.
///
/// The auth gate is a single [GoRouter.redirect] rather than a per-screen check,
/// so a new screen is unreachable while the app is locked without having to
/// remember to guard it (CLAUDE.md §10.2).
class AppRouter {
  const AppRouter._();

  /// [rootNavigatorKey] is the navigator every full-screen route is pushed onto.
  ///
  /// Public because a share can arrive from another app at any moment, and the
  /// listener that opens its chooser sits *above* the router — it has no context
  /// below this navigator to push a sheet onto (see `ShareListener`).
  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'root');

  static final GlobalKey<NavigatorState> _dashboardKey =
      GlobalKey<NavigatorState>(debugLabel: 'dashboard');
  static final GlobalKey<NavigatorState> _tasksKey =
      GlobalKey<NavigatorState>(debugLabel: 'tasks');
  static final GlobalKey<NavigatorState> _libraryKey =
      GlobalKey<NavigatorState>(debugLabel: 'library');
  static final GlobalKey<NavigatorState> _financeKey =
      GlobalKey<NavigatorState>(debugLabel: 'finance');

  /// [build] wires the router to [authBloc].
  ///
  /// [refreshListenable] re-runs the redirect when the lock state changes; without
  /// it, locking the app would update the bloc but leave the current screen in
  /// place.
  static GoRouter build({required AuthBloc authBloc}) {
    return GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/dashboard',
      observers: [NavigationObserver()],
      refreshListenable: _BlocRefreshListenable(authBloc.stream),
      redirect: (context, state) {
        final auth = authBloc.state;
        final location = state.matchedLocation;

        // Nothing is routed until the check lands. `Application` holds the tree
        // back behind the surface colour meanwhile, which is what keeps a locked
        // app from flashing its contents — a splash *route* would do the same job
        // but would then have to slide itself off the screen on every launch.
        if (!auth.isChecked) return null;

        if (!auth.isUnlocked) {
          return location == '/lock' ? null : '/lock';
        }

        // Unlocked: the lock screen is no longer a valid destination.
        if (location == '/lock') return '/dashboard';

        return null;
      },
      routes: [
        GoRoute(
          parentNavigatorKey: rootNavigatorKey,
          name: lockRoute,
          path: '/lock',
          builder: (context, state) => const LockPage(),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              navigatorKey: _dashboardKey,
              routes: [
                GoRoute(
                  name: dashboardRoute,
                  path: '/dashboard',
                  builder: (context, state) => const DashboardPage(),
                  // A child of the branch rather than of the root, so the bottom
                  // navigation stays put and Back returns to the Dashboard
                  // (Requirement 3.3).
                  routes: [
                    GoRoute(
                      name: weatherRoute,
                      path: 'weather',
                      builder: (context, state) => const WeatherPage(),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _tasksKey,
              routes: [
                GoRoute(
                  name: tasksRoute,
                  path: '/tasks',
                  builder: (context, state) => const TasksPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _libraryKey,
              routes: [
                GoRoute(
                  name: libraryRoute,
                  path: '/library',
                  builder: (context, state) => const LibraryPage(),
                  // Children of the branch, so the bottom navigation stays put and
                  // Back returns to the Library hub rather than to whichever tab was
                  // open before it.
                  //
                  // Adding and editing has no route in any of the five: each is a
                  // modal sheet over the list that asked for it, for the same reason
                  // a task has none.
                  routes: [
                    GoRoute(
                      name: bookmarksRoute,
                      path: 'bookmarks',
                      builder: (context, state) => const BookmarksPage(),
                    ),
                    GoRoute(
                      name: toBuyRoute,
                      path: 'to-buy',
                      builder: (context, state) => const ToBuyPage(),
                    ),
                    GoRoute(
                      name: watchlistRoute,
                      path: 'watchlist',
                      builder: (context, state) => const WatchlistPage(),
                    ),
                    GoRoute(
                      name: vaultRoute,
                      path: 'vault',
                      builder: (context, state) => const VaultPage(),
                    ),
                    // A sub-project is the same screen as a project, so one route
                    // serves every depth. The id is a path parameter rather than a
                    // passed object: a project reached from a notification, a search
                    // result or a restored stack has no object to be passed.
                    GoRoute(
                      name: projectRoute,
                      path: 'project/:id',
                      builder: (context, state) => ProjectPage(
                        projectId: state.pathParameters['id'] ?? '',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: _financeKey,
              routes: [
                GoRoute(
                  name: financeRoute,
                  path: '/finance',
                  builder: (context, state) => const FinancePage(),
                  // Children of the branch rather than of the root, so the bottom
                  // navigation stays put and Back returns to the Finance
                  // dashboard rather than to whichever tab was open before it.
                  //
                  // Creating and editing a transaction has no route, for the same
                  // reason a task has none: it is a modal sheet over whatever
                  // screen asked for it (see `showTransactionSheet`).
                  routes: [
                    GoRoute(
                      name: transactionsRoute,
                      path: 'transactions',
                      builder: (context, state) => const TransactionsPage(),
                    ),
                    GoRoute(
                      name: budgetsRoute,
                      path: 'budgets',
                      builder: (context, state) => const BudgetsPage(),
                    ),
                    GoRoute(
                      name: accountsRoute,
                      path: 'accounts',
                      builder: (context, state) => const AccountsPage(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),

        // Full-screen routes: pushed above the shell, covering the bottom
        // navigation and the AI dock.
        //
        // Creating and editing a task has no route: it is a modal sheet over
        // whichever screen asked for it (see `showTaskSheet`), so the list stays
        // visible behind it and the keyboard is up the moment it opens.
        GoRoute(
          parentNavigatorKey: rootNavigatorKey,
          name: settingsRoute,
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),

        // Global Search spans all four tabs, so it is a full-screen route above
        // the shell rather than a child of any one branch — its own screen
        // covering the bottom navigation and the AI dock while a search is on.
        GoRoute(
          parentNavigatorKey: rootNavigatorKey,
          name: searchRoute,
          path: '/search',
          builder: (context, state) => const SearchPage(),
        ),

        // The document editor is a full-screen route above the shell rather than
        // a child of the Library branch: it is a focused writing surface, and the
        // bottom navigation and the floating AI dock have no business sitting over
        // it. The id is a path parameter so a document opened from a search result
        // or a restored stack needs no object handed to it; a new document mints
        // its id before navigating and carries its project in the query.
        GoRoute(
          parentNavigatorKey: rootNavigatorKey,
          name: documentRoute,
          path: '/document/:id',
          builder: (context, state) => DocumentPage(
            documentId: state.pathParameters['id'] ?? '',
            projectId: state.uri.queryParameters['projectId'],
          ),
        ),
      ],
    );
  }
}

/// [_BlocRefreshListenable] adapts a bloc's state stream to the [Listenable] that
/// GoRouter's `refreshListenable` expects.
class _BlocRefreshListenable extends ChangeNotifier {
  _BlocRefreshListenable(Stream<Object?> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
