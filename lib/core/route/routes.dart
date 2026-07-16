// Route name constants.
//
// Every screen in the app has an entry here and a matching `GoRoute` in
// `app_router.dart`. Navigation is **always** by name — never by path string
// (CLAUDE.md §10.3).

// ── Shell branches (bottom navigation) ───────────────────────────────────────
const String dashboardRoute = 'dashboard';
const String tasksRoute = 'tasks';
const String libraryRoute = 'library';
const String financeRoute = 'finance';

// ── Dashboard (children of the dashboard branch) ─────────────────────────────
const String weatherRoute = 'weather';

// ── Library (children of the library branch) ─────────────────────────────────
const String bookmarksRoute = 'bookmarks';
const String toBuyRoute = 'to-buy';
const String watchlistRoute = 'watchlist';
const String vaultRoute = 'vault';

/// The project detail screen. Takes the project's id as a path parameter, so a
/// sub-project is reached by the same route as its parent.
const String projectRoute = 'project';

/// The document editor. Takes the document's id as a path parameter — a new
/// document mints its id at the call site so the route is addressable from the
/// start — and a `projectId` query parameter that files a new document under its
/// project.
const String documentRoute = 'document';

// ── Finance (children of the finance branch) ─────────────────────────────────
const String transactionsRoute = 'transactions';
const String budgetsRoute = 'budgets';
const String accountsRoute = 'accounts';

// ── Global ───────────────────────────────────────────────────────────────────
const String settingsRoute = 'settings';
const String searchRoute = 'search';

// ── Auth ─────────────────────────────────────────────────────────────────────
const String lockRoute = 'lock';
