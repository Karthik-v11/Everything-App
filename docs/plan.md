# Everything App — Implementation Plan

Flutter (Android + iOS), offline-first, BLoC architecture per `CLAUDE.md`.

---

## 0. Decisions That Override `docs/design.md`

`docs/design.md` was written against Riverpod + clean architecture. `CLAUDE.md` is the
authority for this project. Where the two conflict, the table below wins. Everything else in
`design.md` (data models, DB schema, correctness properties, error strategy, testing strategy)
stands and is carried into this plan.

| Topic | `design.md` says | **This project does** |
|---|---|---|
| State management | Riverpod providers | **flutter_bloc / HydratedBloc**, Style A & B state patterns |
| Folder layout | `domain/` + `features/` | **`bloc/` + `data/` + `view/`** per CLAUDE.md §1 |
| Use cases | `domain/usecases/` | **None.** Bloc → Repository → Service → DAO. No use-case layer |
| Repo return type | `Either<Failure, T>` | **`Future<JsonResponse>`** per CLAUDE.md §4 |
| DI | Riverpod | **`MultiBlocProvider` in `app/app.dart`** |
| Navigation | go_router | **go_router** (unchanged — matches CLAUDE.md §10) |
| Local DB | Drift + SQLCipher | **Drift + SQLCipher** (unchanged) |
| Async UI state | `AsyncValue.when()` | **`BlocConsumer` / `BlocBuilder`** |

**The offline-first adaptation of the service layer.** CLAUDE.md's `Service` pattern assumes Dio.
Here, a service wraps a **Drift DAO** instead, but keeps the identical `Future<JsonResponse>`
contract and 3-layer error handling. Blocs are therefore written exactly as CLAUDE.md
prescribes and are unaware of whether their data came from SQLite or HTTP.

```dart
/// [TasksService] handles all task persistence against the local Drift database.
class TasksService {
  TasksService({required this.dao});

  final TasksDao dao;

  Future<JsonResponse> getTasksForDate(DateTime date) async {
    try {
      final entries = await dao.tasksForDate(date);
      return JsonResponse.success(
        message: 'Loaded successfully.',
        data: entries.map(Task.fromEntry).toList(),
      );
    } on DriftRemoteException catch (error) {
      return JsonResponse.failure(statusCode: 500, message: 'Error: ${error.remoteCause}');
    } on Exception {
      return JsonResponse.failure(statusCode: 500, message: 'Error: Unexpected error occurred.');
    }
  }
}
```

Only **two** services use Dio: `WeatherService` and `NewsService`. Those follow CLAUDE.md §5
verbatim (fresh `Dio()` each, `XClientInterceptor`, 10s timeouts).

**Reactive lists.** Drift's `watch*` streams are the reason task/transaction lists update
instantly after a write. Blocs that own a list expose a `Watch<Feature>Event` whose handler
uses `emit.forEach(...)` over the DAO stream, so a write anywhere in the app refreshes every
screen showing that data without manual reload events.

---

## 1. Package Set

```yaml
dependencies:
  flutter_bloc: ^8.1.6          # state
  hydrated_bloc: ^9.1.5         # persisted state (settings, user, filters)
  equatable: ^2.0.5
  go_router: ^14.2.0            # navigation
  dio: ^5.5.0                   # weather + news only
  drift: ^2.19.0                # local DB
  sqlcipher_flutter_libs: ^0.6.0  # AES-256 at rest
  sqlite3_flutter_libs: ^0.5.24
  path_provider: ^2.1.4
  flutter_secure_storage: ^9.2.2  # DB key, PIN hash
  encrypt: ^5.0.3               # item-level vault encryption
  local_auth: ^2.3.0            # biometrics
  flutter_local_notifications: ^22.0.1
  timezone: ^0.11.1             # correct scheduled-notification zones
  flutter_timezone: ^5.1.0      # the device's IANA zone name, which `timezone` needs
  fl_chart: ^0.68.0             # finance charts
  table_calendar: ^3.1.2        # (evaluate — custom strip may be simpler)
  flutter_markdown: ^0.7.4      # document preview rendering (editor is a plain TextField)
  receive_sharing_intent: ^1.8.0
  home_widget: ^0.6.0
  google_fonts: ^6.2.1
  flutter_dotenv: ^5.1.0        # weather/news API keys
  intl, uuid, connectivity_plus, share_plus, url_launcher, shimmer

  # Phase 12. `home_widget` is only the data channel and the refresh trigger — the
  # widgets themselves are Kotlin AppWidgetProvider + Swift WidgetKit.
  receive_sharing_intent: ^1.9.0
  home_widget: ^0.9.3

dev_dependencies:
  drift_dev, build_runner, bloc_test, mockito, glados, golden_toolkit
  integration_test (sdk)
```

```yaml
  # Phase 14. `clock` is what makes a golden of a dated screen possible: it is
  # `DateTime.now()` in production and freezable under `withClock` in a test.
  clock: ^1.1.2
```

**`golden_toolkit` was not added** (Phase 14). It is unmaintained, and the only thing this app needed
from it was `loadAppFonts()` — which is a `FontLoader` over three known paths, plus MaterialIcons off
the SDK. That is `test/flutter_test_config.dart`, and it throws when a font is missing instead of
rendering boxes. `glados` and `integration_test` are still unused: the properties were asserted with
plain unit tests, and nothing yet needs a driver.

Deferred to their own phases: `googleapis` + `google_sign_in` (Drive backup),
`pdf` + `printing` (export), `geofence_service` (location reminders).

```yaml
  # Phase 13. The engine versions independently of the core and registers no
  # backend by default — the core alone compiles and then throws at the first
  # model call. This is what forced iOS 16.0.
  flutter_gemma: ^1.3.0
  flutter_gemma_litertlm: ^1.1.0
```

---

## 2. Folder Structure

Strictly CLAUDE.md §1, with a `data/database/` subtree added for Drift.

```
lib/
├── main.dart                       # startApplication(() => const Application())
├── app/
│   ├── app.dart                    # MultiBlocProvider — ADD every new bloc here
│   └── start.dart                  # bootstrap: DB key, HydratedStorage, notifications, tz
├── bloc/
│   ├── theme/          settings/        connectivity/     auth/
│   ├── dashboard/      weather/         news/
│   ├── tasks/          task_form/
│   ├── bookmarks/      to_buy/          watchlist/        vault/
│   ├── projects/       document/
│   ├── finance/        transaction_form/ budget/          accounts/
│   ├── search/         ai/               backup/
│   ├── share/          home_widget/      storage/           # Phase 12
│   └── (each = <feature>_bloc.dart + _event.dart + _state.dart, part/part of)
├── core/
│   ├── route/          routes.dart, app_router.dart        # MUST update per feature
│   ├── utils/          app_colors, app_text_styles, theme, extensions, helpers,
│   │                   responsive, constants                # PROTECTED — do not modify
│   ├── exceptions/     dio_exception.dart                   # PROTECTED
│   └── interceptors/   x_client_interceptor.dart            # PROTECTED
├── data/
│   ├── database/
│   │   ├── app_database.dart        # @DriftDatabase, schemaVersion, SQLCipher setup
│   │   ├── tables/                  # one file per table
│   │   └── daos/                    # one DAO per module
│   ├── models/                      # Equatable, fromJson/toJson/copyWith/props
│   │   └── json_response.dart       # PROTECTED
│   ├── entity/                      # *_params.dart — mutable request/write objects
│   ├── repositories/                # abstract + Impl, one file each
│   └── services/                    # DAO-backed (local) or Dio-backed (weather/news)
├── view/
│   ├── screens/<feature>/
│   └── widgets/
├── debug/                           # AppBlocObserver — PROTECTED
└── .env                             # WEATHER_API_KEY, NEWS_API_KEY
```

**Three integration points, touched on every single feature** (CLAUDE.md is explicit):
`core/route/routes.dart` → `core/route/app_router.dart` → `app/app.dart`.

Phase 12 added the app's only hand-written native code, which lives outside this tree because it runs
outside this app's process — a widget is drawn by the launcher and a share extension by whatever app
is sharing:

```
android/app/src/main/
├── kotlin/com/karthik/everything_app/
│   ├── EverythingWidgetProvider.kt      # base: reads the published data, wires taps
│   ├── TodayTasksWidgetProvider.kt  FinanceWidgetProvider.kt  QuickAddWidgetProvider.kt
├── res/layout/          widget_*.xml            # RemoteViews — no ListView, see Phase 12
├── res/xml/             widget_*_info.xml       # sizes + the 30-min updatePeriodMillis
└── res/values/          widget_colors.xml, widget_strings.xml   # §4's palette, restated

ios/
├── Share Extension/     ShareViewController.swift, Info.plist, entitlements
├── EverythingWidget/    EverythingWidget.swift (SwiftUI), Info.plist, entitlements
└── Runner/Runner.entitlements                   # the App Group all three share

tool/add_ios_extension_targets.rb                # adds both Xcode targets — not by hand
```

---

## 3. Database Schema

Single Drift DB, `everything.db`, SQLCipher-keyed. Tables from `design.md` §Database Schema,
plus the ones it marked as "+ …":

| Table | Notes |
|---|---|
| `tasks` | + `parentTaskId` for recurrence chain, `completedAt` |
| `categories` | user-defined, shared by tasks |
| `transactions` | `amount` stored as `IntColumn` of **paise/cents**, not `real` — see below |
| `accounts` | cash, bank, credit card, wallet, UPI, custom |
| `budgets` | monthly limit + `categoryLimitsJson` |
| `bookmarks` | + `folderId` |
| `to_buy_items` | |
| `watchlist` | |
| `vault_items` | `encryptedPayload` only; never plaintext |
| `folders` | one table, `scope` column (bookmark / vault) |
| `projects` | + `parentProjectId` for sub-projects |
| `documents` | plain Markdown text (`content`), no revision history |
| `attachments` | polymorphic: `ownerType` + `ownerId` |
| `search_index` | FTS5 virtual table — see below |

Two schema decisions that differ from `design.md` and are worth calling out:

**Money is an integer.** `design.md` uses `RealColumn get amount => real()()`. Property 6 requires
no precision loss beyond two decimals, and binary floats cannot guarantee that under summation
(Property 7 sums an arbitrary sequence). Store **minor units as `int`**, format at the edge.
This makes Properties 6 and 7 hold exactly rather than approximately.

**Search is FTS5, not `LIKE`.** Requirement 24.2 demands < 300 ms across 10,000 items and
Requirement 17.1 spans eight modules. An FTS5 virtual table fed by triggers gives that; eight
`LIKE '%q%'` scans will not. **The vault contributes only its `name` field to the index** —
Requirement 9.5 forbids plaintext content in search indexes, so encrypted payloads are never
indexed and vault search matches on title only.

---

## 4. Theme (from reference UI)

The reference screens define the design language precisely; `core/utils/theme.dart` and
`app_colors.dart` are protected, so these values must be **provided to the developer for those
files, not written by an agent**:

- Background near-black `#0F0F0F`; cards dark gray `#1C1C1C`; hairline dividers.
- Primary accent **amber `#FFB300`** — used on the weather pill, `Add Project`, the selected
  calendar date, and priority markers.
- Overdue/expense red, category-chip indigo.
- Typography per `initial-requirements.md`: **monospace** for labels (`Tasks`, `Library`, dates,
  amounts), **serif** for headings (`Good Morning, Karthik!`, `Today`), sans for body.
  Concretely: JetBrains Mono, Noto Serif, Inter — **bundled as variable-font assets, not fetched
  via `google_fonts`**. The package downloads font files over the network on first use, which in an
  offline-first app means a first launch with no connection silently renders in the wrong typeface.
  This is why `google_fonts` is absent from the package list in §1 despite CLAUDE.md §14 listing it.
- Bottom nav: four detached pill buttons, selected pill filled gray.
- Two stacked floating buttons above the nav bar (AI sparkle + a large primary AI orb), with
  `+` and search satellites — implemented as one reusable `FloatingAiDock` widget rendered from
  the `ShellRoute` so it appears on every screen (Requirement 2.2).

`ThemeBloc` is a HydratedBloc holding `{ AppTheme variant, String accentHex, FontSize size }`
and builds `ThemeData` on the fly, satisfying Property 11 (instant apply, no restart).

---

## 5. Phased Build

Each phase ends with a running, demoable app. Within a phase, every feature follows the
CLAUDE.md §16 checklist in order: **Model → Params → Service → Repository → Bloc → register in
`app.dart` → Screen → routes**.

### Phase 1 — Foundation ✅ done
The protected scaffolding, hand-built by the developer or generated once and then frozen.
- `main.dart` + `app/start.dart`: `WidgetsFlutterBinding`, `dotenv.load`, timezone init,
  `HydratedBloc` storage, `AppBlocObserver`, portrait lock.
- `core/utils/*` (theme, colors, text styles, extensions, responsive, constants), `core/exceptions/`,
  `core/interceptors/`, `debug/`.
- `data/models/json_response.dart`.
- `core/route/routes.dart` + `app_router.dart` with a `ShellRoute` hosting the bottom nav and the
  floating AI dock. `StatefulShellRoute.indexedStack` — this is what preserves each tab's scroll
  position and state (Requirement 2.4); a plain `ShellRoute` will not.
- `ThemeBloc` and `ConnectivityBloc` registered in `MultiBlocProvider`.
  *No `SettingsBloc` yet* — the only setting that exists in Phase 1 is the theme, and `ThemeBloc`
  already owns it. It arrives with the first non-theme setting (Phase 4, notifications).
- Settings screen, Theme section only — built now rather than stubbed, because it is what makes
  Property 11 (instant theme switching) demonstrable instead of merely asserted.

**Exit:** app launches to an empty four-tab shell in the correct dark/amber theme; switching
tabs preserves state; changing theme/accent/font in Settings re-themes every screen instantly and
survives a restart.

Two deviations from the plan as written, both still standing:

1. **`google_fonts` is not used.** It downloads font files on first use, so an offline-first app's
   first launch with no connection would render in the wrong typeface. JetBrains Mono, Noto Serif
   and Inter are bundled as variable-font assets instead (§4).
2. **The Settings screen's Theme section was built, not stubbed** — it is what makes Property 11
   demonstrable rather than merely asserted.

### Phase 2 — Encrypted Persistence ✅ done
- `SecurityService`: generate a 256-bit DB key on first launch, store in
  `flutter_secure_storage`; retrieve on every launch. PIN stored as a PBKDF2-HMAC-SHA256 hash with a
  per-user salt, never in plaintext.
- `AppDatabase` with SQLCipher `PRAGMA key`, all tables from §3, `schemaVersion: 1`.
- `AuthBloc` + lock screen: biometric via `local_auth`, PIN fallback, **3 failures → 30s lockout**
  (Requirement 1.4), auto-lock on resume after the configured background duration (Requirement 1.5).
  The auth gate is a single `GoRouter.redirect`, so a new screen is protected by default rather than
  by remembering to guard it.

**Exit:** DB file is unreadable without the key; app locks and unlocks.

Four things worth carrying forward:

1. **`sqlcipher_flutter_libs` is dead.** Its 0.7.0 release is an empty no-op — `sqlite3` 3.x moved
   native library selection into build hooks. SQLCipher is now enabled by a `hooks: user_defines:`
   block in `pubspec.yaml`. This matters more than it sounds: plain SQLite **silently ignores** an
   unknown `PRAGMA key` instead of erroring, so getting this wrong yields a fully working app writing
   a completely unencrypted database, with nothing looking wrong until someone pulls the file off the
   device. `AppDatabase._verifyKeyed` checks `PRAGMA cipher_version` at open time so that failure is
   loud. Verified: `sqlcipher.framework` is in the built iOS bundle.
2. **The DB key is not derived from the PIN.** A 4-digit PIN carries ~13 bits of entropy; keying the
   database with it would make the at-rest encryption decorative. The key is 256 bits from the OS
   CSPRNG. The PIN gates the UI, the key protects the file — two separate jobs.
3. **The lockout counter lives in secure storage, not in memory.** An in-memory counter resets on
   force-quit, which would hand an attacker unlimited guesses three at a time.
4. **No DAOs yet.** The plan listed them here, but a DAO with no feature to serve is speculative code;
   each module phase writes its own against this schema. All tables exist now, so no phase needs a
   migration.

**Tests (37 passing):** database encryption is tested against the *bytes on disk* — the file is opened
without the key and must fail, and grepped for plaintext row data, schema names, and the
`SQLite format 3` header, none of which may appear. Reading back through the same keyed handle that
wrote the data would have passed trivially and proved nothing. Plus PIN hashing, salt uniqueness,
lockout threshold/persistence, and the `AuthBloc` state machine.

### Phase 3 — Tasks ✅ done
The most-used module — build it first and completely.
- Screens: task list with the weekly calendar strip, task create/edit sheet.
- `TasksBloc` (**Style A** — holds the list, selected date, filters; hydrated so the last filter
  survives restart), `TaskFormBloc` (**Style B** — one focused create/update action).
- Recurrence engine: on complete, generate exactly one next occurrence (Property 4).
- Overdue derivation, subtask progress, filters (Today/Tomorrow/Upcoming/Completed/Overdue/
  Category/Priority), in-module search.

**Exit:** full task CRUD offline.
**Tests:** Properties 1, 2, 3, 4.

Three things worth carrying forward:

1. **There is no task-detail route.** Creating and editing both happen in one modal sheet over
   whichever screen asked for it, so the list stays visible behind it and the keyboard is up the
   moment it opens. A separate detail screen for a title, a date and four pills would be a
   navigation for nothing.
2. **The sheet parses shorthand** (`Pay rent tomorrow 5pm #finance p1`) via `QuickTaskParams`, which
   is a pure function and is what Phase 10's rule-based AI parser will be built on rather than
   duplicating.
3. **Everything reads from one DAO stream.** Filters, groups and search are derived in memory from
   it, so no write anywhere in the app needs a reload event — which is the property Phase 4 then
   leaned on for scheduling.

### Phase 4 — Notifications ✅ done
- `NotificationService` on `flutter_local_notifications` + `timezone`, with Android 13+
  `POST_NOTIFICATIONS` and exact-alarm permission handling (the usual Android 14 trap).
- Task reminder, deadline, recurring, missed-task, daily summary, weekly summary.
- `SettingsBloc` arrives here, as planned, with the first non-theme setting: the notification
  configuration, hydrated. Settings owns it; `TasksBloc` owns the task list; neither alone can
  decide what to schedule, so Settings *pushes* the configuration to `TasksBloc` by event dispatch
  (CLAUDE.md §3.6 — never a cross-bloc state read).
- A **Remind** pill in the task sheet, and a Notifications section in Settings (master switch, five
  per-kind switches, digest times, digest weekday).

**Exit:** a task set 2 minutes out fires a notification with the app killed.
*(Location reminders, Requirement 4.12, remain deferred to Phase 12.)*

Four things worth carrying forward:

1. **The schedule is reconciled, not written.** The plan said reminders would be scheduled and
   cancelled inside `TasksBloc`'s event handlers. That is a write for every code path that touches a
   task — the form, the checkbox, the delete, the recurrence rollover, and every future one (AI,
   share intent, home widget) — and it takes exactly one forgotten call to leave an alarm armed for
   a task that no longer exists. Instead `NotificationPlan.build(tasks, settings, now)` is a **pure
   function** returning the set of notifications that *should* be pending, and
   `NotificationService.applyPlan` diffs it against what the OS actually holds, cancelling and
   scheduling only the difference. It is driven off the DAO stream, so **every** write reconciles,
   including writes from code that does not exist yet. Completing a task cancels its reminder with
   no cancel call anywhere in the app.
2. **The OS queue is the only store.** Each pending notification carries its own definition in its
   payload, so a plan built now can be compared against alarms armed by a previous launch. A second
   copy of the schedule on disk would be one more thing that can drift from the database.
3. **Exact alarms are requested, not assumed.** On Android 14+ the user can refuse them, and
   `zonedSchedule` *throws* if asked for one without the permission — so the service checks
   `canScheduleExactNotifications()` and falls back to an inexact alarm rather than failing to
   schedule at all. Settings says so plainly when it happens; a reminder quietly arriving 40 minutes
   late reads as a broken app.
4. **Notification ids are an FNV-1a hash of a stable seed**, not `Object.hashCode`, which Dart does
   not promise is stable across runs. A drifting id would orphan every alarm already in the OS queue
   on every app start.

**Tests (22 passing):** the six delivery rules of Requirement 5, driven through the pure planner with
an injected `now` — so a missed-task alert and a Monday digest are assertions rather than a wait.
Plus reconciliation against a fake queue: an unchanged plan re-arms *nothing*, a moved due date
cancels and re-arms, a deleted task's alarm is withdrawn, and a payload from an older build is
cancelled rather than left to fire something the app can no longer explain.

### Phase 5 — Finance
- Screens: finance dashboard (donut chart + budget bar, per the reference UI), transaction list,
  transaction form, budgets, accounts.
- `FinanceBloc` (Style A: summary + transactions), `TransactionFormBloc` (Style B), `BudgetBloc`.
- `fl_chart`: pie by category, monthly trend line, income-vs-expense bars, budget progress.
- Budget alert thresholds — warning at ≥ 80% and < 100%, exceeded at ≥ 100% (Property 8) — as a
  pure, unit-testable function, invoked from the bloc after every transaction write.

**Exit:** the Finance reference screen renders from real data.
**Tests:** Properties 6, 7, 8.

### Phase 6 — Dashboard ✅ done
Depends on Tasks + Finance existing, which is why it is not first.
- Greeting/date header, weather pill, today's tasks (complete/edit/open/see-all), the "You spent"
  card, news with category tabs.
- `WeatherBloc` + `NewsBloc` — the only two Dio services. Both HydratedBloc, so the last successful
  payload is the offline cache (Requirement 3.11) with **zero extra caching code**.
- Both degrade to cached data silently; a banner appears only if the cache is > 1 hour stale.

**Exit:** the Dashboard reference screen renders; airplane mode still shows cached weather/news.

Five things worth carrying forward:

1. **The Dashboard owns no data.** Every figure on it belongs to a module that already owns it, and
   the screen is where the four are put side by side — which is what makes it a summary rather than a
   fifth source of truth. Two small derivations were added to the states that own the data rather
   than computed in the widget: `TasksState.todayTasks` and `FinanceState.totalsFor(month)`. The
   latter exists because the Dashboard is always about *this* month while `FinanceBloc.selectedMonth`
   is wherever the user last scrolled the Finance tab to — without it, looking at February on Finance
   would quietly put February's spending on the Dashboard. The budget card assembles a `BudgetStatus`
   from this month's limit and this month's spend, which is legal precisely because that type is a
   pure value: no bloc reads another bloc's state (CLAUDE.md §4.4), the *screen* reads both.
2. **There is no location permission.** The plan never budgeted `geolocator`, and a permission prompt
   on first launch — for one pill on one screen — buys a coordinate the user can type in five seconds.
   The city is named once and lives in `WeatherBloc`'s own hydrated state, so a rehydrated bloc can
   fetch on launch without waiting to be told where it is. `SettingsBloc` owns the greeting name
   (Requirement 3.1); it does *not* own the city, because two owners of one value is one value that
   can disagree with itself.
3. **The hydration *is* the cache.** Requirement 3.11 asked for cached weather and news offline, and
   both blocs satisfy it with no caching code: the payload is part of the persisted state, so it is on
   screen before the first request is made and stays there when that request fails. A failed fetch
   never clears what is on screen and never raises an error the user can act on — offline is this
   app's normal condition, not a fault. The only admission is the stale banner, past
   `kStaleCacheThreshold`, which is the point where the temperature on the pill stops being an answer
   and becomes a memory. Each news category caches separately and re-fetches only when stale, which is
   what keeps a scroll through six tabs from spending six requests of a daily quota measured in dozens.
4. **NewsAPI has no "world" category**, and forbids mixing `sources` with `country`/`category`. World
   is therefore a set of international sources and every other tab is a category of the local feed;
   All is that feed with no category, which is what makes it a mix rather than a repeat of India's
   general bucket. This lives in `NewsCategory`, so the API's shape is stated once.
5. **`.env` ships with no API keys**, and a build without them is a working app minus its weather —
   not a broken one. Both services say so plainly instead of letting the request time out.

Also fixed here, and it is a bug the sheets have had since Phase 3: **choosing an option from a pill
menu closed the keyboard.** `PopupMenuButton` shows its menu by *pushing a route*, and the new route
takes the focus scope with it — so in both the task and the transaction sheet, which open with the
caret already in a field, setting a category or an account dismissed the keyboard and left the user to
tap back into the field. The two sheets had each grown their own copy of the pill; both now use one
`OptionPillMenu` built on `MenuAnchor`, which renders into the `Overlay` instead of pushing a route
and so never touches focus at all. It is covered by a test that asserts the field keeps **primary
focus** through a selection — the same assertion fails against the old widget, which is what makes it
a regression test rather than a restatement.

**Tests (64 passing):** the two above. The phase adds no properties of its own — its correctness is
"the cache is what is on screen", which the hydration makes structural rather than something to assert.

### Phase 7 — Library ✅ done
Largest surface area; build as five independent sub-features behind one hub screen.
1. **Bookmarks** — URL, title, thumbnail, tags, folders. Metadata scrape on save (best-effort).
2. **To Buy** — item, price, store, priority, purchased, reminder → reuses `NotificationService`.
3. **Watchlist** — movie/TV/anime/manga/book/game, status, rating, progress. Progress clamped to
   total; completing stamps `completedAt` (Property 16).
4. **Vault** — `VaultBloc` gated by a fresh `AuthBloc` challenge on entry (Requirement 9.2).
   Item-level AES-256 via `encrypt` **on top of** the already-encrypted DB. Plaintext is decrypted
   only in the detail screen, never held in list state.
5. **Projects** — container with nested sub-projects; deleting cascades after confirmation.

**Exit:** Library reference screen + all five sub-screens.
**Tests:** Property 16; vault authentication gate.

Five things worth carrying forward:

1. **The OS notification queue is now partitioned by kind, and it had to be.** Phase 4's
   `applyPlan` reconciles by *cancelling anything pending that its plan does not contain* — which is
   exactly what stops a reminder outliving its task. But it read the **whole** queue, so the moment a
   second module scheduled anything, the two reconcilers would erase each other: the Tasks sync would
   withdraw every to-buy reminder, the To-Buy sync would withdraw every task reminder, and the last
   write would win until the next one undid it. The user would simply never be reminded, with nothing
   in the app looking broken. `applyPlan` now takes `owns: Set<NotificationKind>` and touches only
   its own slice. This is the extension point Phase 4's notes were reaching for when they said the
   schedule reconciles "including writes from code that does not exist yet" — Phase 12's share intent
   and home widget each take their own kinds and cost nothing.
2. **A bookmark is saved from its URL, and *then* goes looking for its title.** The source type, a
   readable title from the slug, and — for YouTube and GitHub, whose thumbnail URLs are a function of
   the link — a preview image are all derived with no network call (`UrlMetadata.read`), so the save
   is instant and works on a plane. `MetadataService` enriches the row afterwards and its failure is
   *not an error*: offline, the bookmark already exists and already looks right. It is the app's third
   and last Dio service, and the only one whose failure the user is never told about, because nothing
   they did has failed. It overwrites only a title nobody has typed.
3. **Property 16 lives in the model, not in the bloc.** `WatchlistItem.withProgress` and
   `.withStatus` are where progress is clamped to the total and where Completed is stamped with a
   date — and every writer routes through them. So the `+1` on the card, the field in the sheet, and
   the AI parser that does not exist yet are all subject to the rule without each having to remember
   it. Reaching the total *completes the entry*, which is the only way "the user watched the last
   episode" and "the user tapped Completed" can be guaranteed to leave the same row behind.
4. **The vault list never holds a plaintext, by construction rather than by discipline.** A
   `VaultItem` has a name, a type and an opaque blob, and there is no method on it that can produce
   anything readable — so the list can be streamed from launch, filtered and searched while the vault
   is still *locked*, and nothing readable has been loaded. Exactly one item is decrypted at a time,
   into a single nullable `VaultState.revealed`, when its detail sheet opens; the type makes holding
   two secrets impossible, and it is cleared when the sheet closes or the vault re-locks. The vault
   re-locks in `dispose`, so leaving and returning is a fresh challenge (Requirement 9.2) rather than
   a resumed session. Two further calls worth stating: the challenge goes through the app's *own*
   `AuthRepository`, so a wrong PIN at the vault advances the same lockout as a wrong PIN at the lock
   screen — a vault with its own PIN check would have been a second front door with no bolt on it —
   and the item key is a **separate** 256-bit key from the database key, because a second layer of
   encryption using the key the database is already open under is a layer any code holding a database
   handle can peel straight back off.
5. **The delete confirmation names what it destroys.** Requirement 10.4 asks for a confirmation
   before removing a project "and all its contents", and a dialog that said only "Delete project?"
   would be asking the user to agree to something they had not been told. `ConfirmDeleteProjectEvent`
   counts the tasks, documents, attachments and sub-projects first — from the database, so the numbers
   are what will actually go — and the dialog reads "This also deletes 2 sub-projects, 11 tasks and 3
   documents." An empty project skips the dialog entirely: a confirmation with nothing in it trains
   people to dismiss the ones that matter.

**Tests (131 passing, up from 86):** Property 16 asserted over a *range* of updates rather than at one
convenient point, plus both routes to Completed and the reopen that must drop the date. The vault is
tested against its **ciphertext** — the payload must contain none of the plaintext, the same value must
encrypt differently every time (a fixed IV would leak which of the user's passwords are the same
password), and a single flipped character must fail to decrypt rather than producing plausible nonsense
the app would show as bank details. A round-trip test would have passed against an implementation that
stored plaintext, which is the failure this layer exists to prevent. Plus the gate: a reveal while
locked never reaches the repository at all, and leaving the vault drops the decrypted item. Plus the
queue partition, in both directions, and the project tree's cycle handling.

### Phase 8 — Document Writer
- Plain **Markdown** documents — no rich-text editing package, no Delta format, no revision history.
  Each document is a `.md` file's worth of text stored as-is in the `documents` table.
- Two modes on one screen: a raw Markdown **editor** (a `TextField`) and a rendered **preview**,
  toggled between. Preview renders standard Markdown (headings, lists, checklists, code, links).
- Auto-save every 30 s (Property 12).
- Export to Markdown and plain text now; **PDF export moves to Phase 11**,
  so `pdf`/`printing` is integrated once, not twice.

**Tests:** Property 12 (auto-save).

### Phase 9 — Global Search ✅ done
- FTS5 index + triggers; `SearchBloc` querying all eight modules, results grouped by module.
- Recent searches (hydrated) and as-you-type suggestions.
- Vault results surface titles only.

**Exit:** < 300 ms against a seeded 10,000-item DB — benchmark it, don't assume it.
**Tests:** Property 5.

Four things worth carrying forward:

1. **The index is a standalone FTS5 table maintained by triggers, not rebuilt on read.**
   `search_index(item_id UNINDEXED, module UNINDEXED, title, body)` lives beside the real tables,
   and three triggers per source table (`AFTER INSERT/UPDATE/DELETE`) keep its one row per item in
   step. So a task edited in the sheet, a transaction added from the AI dock, a bookmark enriched in
   the background — every write reconciles its own FTS row with no reindex step and nothing for a
   feature to remember to call, which is the same shape as Phase 4's notification reconciliation. It
   is created in `AppDatabase.beforeOpen` behind `CREATE ... IF NOT EXISTS`, exactly like
   `_createIndexes`, rather than through a `schemaVersion` bump: the index is derived data, not
   schema the models depend on, so it stays at version 1 and a database written by an earlier build
   is covered by a **one-time backfill** that runs only when the table is first created (the triggers
   fire only on *future* writes, so rows already on disk would otherwise never be indexed).
2. **The vault contributes its name and nothing else — enforced at the schema, not the query.** The
   vault's FTS source lists *no body column at all*, so `encryptedPayload` is never tokenised and a
   vault item can only ever match on its title (Requirement 9.5). This is stronger than filtering
   payloads out at search time: there is no code path by which an encrypted blob could reach the
   index, and the test proves it against a payload token that appears nowhere else and must return
   zero vault hits. Searching **eight** modules' contents while indexing the ninth's title only is
   the whole reason global search and an encrypted vault can coexist.
3. **Raw user text never touches `MATCH`.** `"`, `*`, `:`, `-`, and `NEAR`/`OR`/`AND` all carry
   meaning in FTS5, so `SearchService.toMatchQuery` strips everything that is not a letter, digit or
   space — mirroring the `unicode61` tokenizer the content was indexed with — lower-cases (which also
   neutralises the operator keywords, upper-case-only), and appends `*` to each token for prefix
   matching. So the query tokenises the same way the content did, results appear as the user types,
   and a pasted URL or a stray quote is a search rather than a syntax error. Tokens are ANDed (FTS5's
   default), so "pay rent" narrows.
4. **Ranking, and the delete-by-scan trade.** Results order by `bm25(search_index, 0,0,10,1)` —
   title weighted ten to body's one — so a title hit sorts above a body hit for the same term, and
   `SearchState.groups` then re-sections the flat ranked list into a fixed module order so the
   sections do not reshuffle between keystrokes. The one cost paid for the string primary keys: an
   update/delete trigger removes the stale FTS row with `DELETE ... WHERE module = ? AND item_id = ?`
   over `UNINDEXED` columns, which is a content scan rather than a rowid lookup. That is a few
   milliseconds against a single-row write and never on the read path the 300 ms budget bounds, so it
   is left as is and noted rather than optimised with a shadow rowid map.

**Tests (142 passing, up from 136):** Property 5 over a mixed dataset — every hit contains the queried
term in a searchable field, and the rows that lack it (a different task, a watchlist title) never leak
in — plus the vault indexing its name but never its payload in both directions, a blank/punctuation
query returning an empty result rather than an error, and the **< 300 ms bar benchmarked against a
seeded 10,000-row index** (Requirement 24.2) across four queries, not asserted.

### Phase 10 — AI Assistant (interface + rule-based) ✅ done
- `AIRepository` interface exactly as `design.md` defines it (`parseTaskIntent`,
  `parseTransactionIntent`, `summarizeDocument`, `searchWithAI`, `answerQuestion`).
- First implementation: a **deterministic parser** — date/amount/category extraction via regex and
  a keyword lexicon ("tomorrow", "next friday", "spent 500 on food"). It fully satisfies
  Requirements 16.2, 16.3, 16.5, 16.6 for the common phrasings, is instant, adds nothing to app
  size, and returns a confidence score so low-confidence input triggers a clarifying question
  (Requirement 16.7).
- AI sheet from the floating dock: add task / add expense / add note / search / ask.

**Exit:** "Buy milk tomorrow" and "Spent 500 on food" create correct entries.
**Tests:** Property 14 — written against the *interface*, so it re-runs unchanged against the LLM.

Five things worth carrying forward:

1. **The AI layer parses but never persists, and that is the whole architecture.** `AiRepository`
   is the one repository that returns bare domain types instead of `Future<JsonResponse>` — the
   exception the plan reserved for it — so Phase 13 drops a `flutter_gemma` implementation in behind
   the identical interface with no change to the bloc, the sheet, or the test. But it also creates
   *nothing*: parsing is its only job, and a parsed task is handed to `TasksRepository.create`, a
   parsed expense to `FinanceRepository.createTransaction`, a note to `DocumentsRepository.save` — the
   exact code and validation the quick-add and transaction sheets already use. So "Spent 500 on food"
   from the assistant is subject to the same "amount must be positive, account required" rules as one
   typed into the finance sheet, and it reaches every screen through the same DAO stream. The bloc is
   the composition point where an intent becomes a real entry; the AI layer never touches the
   database.
2. **It is built on the sheets' own parsers, not a second copy of them.** `ParsedTaskIntent.parse`
   *is* Phase 3's `QuickTaskParams` (plan §5 line 300 said it would be), and the expense category
   comes from Phase 5's `inferTransactionCategory` — so the assistant and the sheet cannot disagree
   about what "tomorrow 5pm" or "Swiggy" means, because they read it with the same pure code. The one
   thing genuinely new is amount extraction, and it lives in the intent value type where it is
   unit-testable with no dependencies — which is where Property 14 is actually asserted, against the
   shape the LLM will have to fill too, rather than against this implementation.
3. **Classification needs a money *marker*, not just a number — because times and quantities have
   numbers too.** "Buy milk tomorrow 5pm" has a `5` in it and stays a task; it takes a currency
   symbol or a spend/earn verb ("spent", "paid", "₹") to read a line as an expense. And the guess is
   only the sheet's default mode: the five mode chips let the user override it, so a misclassification
   costs one tap, never a wrong entry. This is why "buy"/"bought" are deliberately *not* money verbs —
   they read as a to-do far more often than a purchase.
4. **Confidence gates creation, and below the bar the assistant asks rather than guesses**
   (Requirement 16.7). A line the parser can pull no name out of ("tomorrow 5pm") or no amount out of
   ("lunch at the cafe") scores below the threshold, and the sheet shows a one-line prompt — "What
   should I call this task?", "How much was it?" — instead of saving something half-understood that
   the user then has to find and undo.
5. **Questions are answered from search, never from a model's imagination.** `answerQuestion` runs the
   query through the same FTS index Global Search uses and reports only what came back — counts per
   module and a few titles. It is the honest ceiling of a rule-based engine and a safe one: it
   physically cannot state a fact the database does not hold. When the model arrives it can phrase the
   same grounded results more fluently; it does not get licence to invent new ones.

**Tests (159 passing, up from 142):** Property 14 asserted through `ParsedTaskIntent` — a task line
always yields a non-empty title, an inferable date always yields a consistent non-null `dueDate`, and
a line that is only a date scores too low to act on — plus the transaction parser (amount, income vs
expense, currency markers and `k`/`lakh` suffixes, a marked amount winning over an incidental "2
coffees", "yesterday", and the untitled-line-named-after-its-category fallback) and the classifier
across all five intents, including the number-that-is-a-time staying a task.

### Phase 11 — Backup, Restore & Export ✅ done
- `BackupService`: AES-256-encrypted export with an HMAC integrity tag; local storage.
- Restore verifies HMAC first and **aborts without touching the live DB** on mismatch (Requirement 22.6).
- Automatic scheduled backup.
- document → PDF. One `pdf`/`printing` integration.

**Exit:** a backup taken today restores every module exactly; a tampered one is refused with the live data untouched; a document exports to a shareable PDF.
**Tests:** Property 10 (backup round-trip + tamper detection).

Six things worth carrying forward:

1. **The format is encrypt-then-MAC with two derived keys, and the verify runs before
   anything else.** The database is serialised, gzipped, AES-256-CBC encrypted, and then an
   HMAC-SHA256 tag is computed over the ciphertext; the envelope is `magic ‖ iv ‖ mac ‖
   ciphertext`. `BackupService.open` checks the tag **before it decrypts and long before
   `restoreFromBytes` touches a row**, so a damaged or tampered backup is rejected with the
   on-device data exactly as it was (Requirement 22.6) — there is no "was anything lost?" to
   answer because on failure nothing was touched. The AES key and the HMAC key are **derived
   apart** from one stored master by labelled SHA-256 (`SecurityService.backupKeys`): reusing one
   key for both is the classic encrypt-then-MAC footgun, and the split means the integrity tag
   cannot be forged by anyone who only learns the cipher key. The seal/open pair is static and
   pure, so Property 10 is asserted against the **bytes** — a round-trip test alone would pass
   against an implementation that skipped the tag entirely, which is the failure this layer
   exists to prevent, so every test flips a byte (of the ciphertext, the IV, or the MAC) and
   asserts the open *fails*.

2. **The backup key is independent of the SQLCipher key, on purpose.** A backup outlives the
   install that wrote it — surviving a reinstall is the whole point — so it is keyed by a secret
   of its own rather than one bound to a single device's database file. The trade this leaves
   standing: the master lives in this device's secure storage, so a backup shared to another
   device restores only back onto *this* install. A passphrase-derived key (PBKDF2 over a
   user-entered secret) is the change that would make a backup portable across devices; it is a
   clean swap behind `backupKeys` when cross-device restore is actually wanted, and is noted
   rather than built speculatively.

3. **The snapshot is schema-agnostic.** `_exportSnapshot` iterates `AppDatabase.allTables` and
   `SELECT *`s each — a table added in a later phase is backed up with no change here. Every
   column is already an `int`/`double`/`String`/`null` (money is minor units, dates are unix
   seconds, enums are their name), so the raw row map is JSON-encodable with no per-type handling.
   The FTS index and its shadow tables are **not** drift tables, so they are correctly excluded;
   restore rebuilds them through the same triggers Phase 9 installed, which fire per row on the
   re-insert. Restore is one `transaction` with `PRAGMA defer_foreign_keys = ON`, so the
   delete-then-fill order need not be topologically sorted and any mid-way failure rolls the whole
   database back rather than leaving it half-restored. drift's stream queries are notified once at
   the end (`markTablesUpdated`), so every open screen re-reads without a relaunch.

4. **Google Drive is a share sheet, not an OAuth client.** The plan listed "local storage + Google
   Drive", and `googleapis` + `google_sign_in` were the packages it deferred to "their own
   phases" (§1) — because a working Drive client needs external project setup (OAuth client IDs,
   SHA fingerprints, an iOS URL scheme) that cannot be tested or shipped from code alone, the same
   class of external dependency as the weather/news API keys. So the off-device path is `share_plus`:
   a backup is an encrypted file, and "Share" hands it to the OS sheet, which reaches Drive, Files,
   email or anything else the user has. The encryption is the app's; the destination is the user's.
   A first-party `googleapis` uploader is a clean addition behind `BackupRepository` when the OAuth
   credentials exist — it does not change the format, the bloc, or the tests.

5. **Automatic backup is opportunistic at launch, not a background job.** A true scheduled task
   belongs to the platform worker (WorkManager / BGTask) introduced with the home-screen widgets in
   Phase 12; wiring a second native moving part now would be speculative. Until then,
   `InitBackupEvent` takes an overdue backup (older than a day) when the app is opened with the
   feature on — which covers the common case of an app used most days — and composes with a real
   scheduler later rather than being replaced by one. The preference and the last-backup time are
   hydrated; the file **list** is re-read from disk each launch, because a file the OS or another
   install removed would make a remembered list a lie.

6. **PDF export is a lightweight renderer, not a second Markdown engine.** `document → PDF` shares
   the rendered bytes through `printing` (Requirement 11.4), building the page with `pdf`: headings
   by their `#` level, bullet and numbered lists, everything else a paragraph. That covers what the
   plain-text editor actually produces without dragging the preview's full HTML pipeline into a
   background build. It is the one `pdf`/`printing` integration Phase 8 deferred here so it happened
   once, and it sits beside the existing Markdown/plain-text exports on the same menu.

**Tests (166 passing + 1 pre-existing unrelated failure; this phase adds 8):** Property 10 in two layers — the envelope against its bytes
(round-trip, plus a flipped ciphertext/IV/MAC byte and a wrong MAC key each rejected, plus a
truncated/foreign file refused) and a full database round-trip through the service (a backup taken,
the database diverged, then restored back to exactly the snapshot), plus the tamper abort proven
against the **live data**: a corrupted backup fails to restore and the on-device rows are still
there, untouched, rather than rolled back to anything.

*(One pre-existing failure remains in `ai_parser_test` — a Phase 10 classifier edge, "a plain
to-do" landing in `toBuy` rather than `task` — untouched by this phase and unrelated to it.)*

### Phase 12 — System Integration ✅ done
- **Share extension** (`receive_sharing_intent`): Android intent-filters + iOS Share Extension
  target. Incoming URL/file → chooser sheet → bookmark / document / task / project file.
- **Home screen widgets** (`home_widget` + native): today's tasks, finance, quick add;
  small/medium/large; 30-min refresh. **This phase is genuinely native work** — Kotlin
  `AppWidgetProvider` + Swift `WidgetKit`.
- Settings screen: the sections from Requirement 25.1, plus storage usage per module.

**Scope taken:** three widgets, not seven. Today's tasks, finance and quick add were built; weather,
calendar, quote and the AI shortcut were not. The native plumbing is identical for all of them — a
provider, a layout, an `appwidget-provider` XML and a manifest receiver on Android; a `Widget` in the
`WidgetBundle` on iOS — so the remaining four are a copy of an existing provider rather than new
ground. The AI shortcut in particular already exists as a pill on the quick-add widget.

Eight things worth carrying forward:

1. **A widget is the one place data leaves the encrypted database, and that is not a detail.** Phase 2
   put the database behind SQLCipher precisely so nothing could read it without the key. A widget runs
   in the *launcher's* process — it has no key and cannot ever have one — so the only way it can draw
   anything is if the app copies what it needs into a container both processes can read: an App Group
   on iOS, `SharedPreferences` on Android. **That container is not encrypted, and nothing the OS offers
   makes it so while still being readable at draw time.** So this phase deliberately made that boundary
   as narrow as it can be and still be useful: task titles, three counts, and one pre-formatted spend
   figure. **The vault is never published, at any size, in any form — not a name, not a count**, because
   a widget is drawn on a lock screen and Requirement 9 puts vault contents behind a second layer of
   encryption *and* a fresh challenge. No per-transaction amounts, no account names, no note bodies.
   The Settings switch is what makes this a real choice rather than a decision taken on the user's
   behalf, and switching it off **erases the container** rather than merely stopping the refresh —
   which is why `HomeWidgetBloc.isEnabled` starts `null` rather than `false`: null means "Settings has
   not spoken yet" and publishes nothing, where `false` would be a guess and `true` would put titles
   into a plaintext store belonging to someone who had switched widgets off. The test asserts the
   **exact key set** that crosses, so a field added later is a decision rather than an accident.
2. **The widgets reconcile off the DAO streams, exactly as Phase 4's reminders do.** The obvious
   implementation — republish from every code path that writes a task or a transaction — is a call site
   in the form, the checkbox, the delete, the recurrence rollover, the AI sheet, the share chooser, and
   every future one, and it takes one forgotten call to leave a widget showing yesterday. `HomeWidgetBloc`
   instead watches the same two streams the screens read, so **every** write republishes, including from
   code that does not exist yet, with no push call anywhere. It reads *repositories*, not blocs, which is
   what lets it project two modules onto one surface without violating §4.4 — the widget needs tasks and
   finance, and neither owns the other.
3. **The payload ships formatted strings, and the native side owns no formatting rule at all.** Shipping
   `expenseMinor: 1500000` would mean reimplementing `Helpers.formatMoney` — minor-unit division, `en_IN`
   lakh/crore grouping, the symbol — in Kotlin *and* Swift, which is three implementations of one rule and
   three chances for the home screen to disagree with the Finance tab about what the month cost. Kotlin and
   Swift draw the strings they are handed.
4. **The 30-minute refresh redraws; it cannot re-read — and no WorkManager job can fix that.** The plan
   said "30-min refresh via WorkManager (Android)". Building it revealed the premise does not hold: a
   background worker in Kotlin has no database key either, so all it could do is re-render the same
   published values. Recomputing "today's tasks" against a new day needs the database, and the database
   needs Dart. So the refresh is `updatePeriodMillis="1800000"` in the provider XML and a
   `.after(+30min)` timeline policy on iOS — no WorkManager dependency, no second native moving part, and
   30 minutes is also the *floor* Android enforces, so asking for less only looks like it works. In
   practice it barely matters: the app republishes on every write, so the widget is current the moment
   anything changes and goes at most one app-open stale. **The consequence for Phase 11's note 5 stands:
   the platform background worker did not land here, so automatic backup is still opportunistic-at-launch.**
   A Dart background isolate (opening SQLCipher off a secure-storage key read) is what would change both,
   and it was not worth building to make a date roll over half an hour sooner.
5. **The share layer routes but never persists — the same architecture as Phase 10's AI layer.** A shared
   link becomes a `Bookmark` through `BookmarksRepository`, a note a `Document`, a file an `Attachment` —
   the same code and the same validation the in-app sheets use, reaching every screen through the same DAO
   stream. So a bookmark saved from Chrome's share sheet is identical to one typed into the Library and is
   enriched by the same background metadata fetch. **The chooser exists because the destination is genuinely
   ambiguous**: a link is usually a bookmark, but "read this later" is a task, and only the person sharing
   knows which. It offers only the destinations that fit what arrived rather than options that fail on tap.
   Two things the OS will not do for us: it does not say whether a shared string is a link or a note —
   Android sends a URL from a browser as `text/plain` — so `SharedItem.fromText` decides by looking, and a
   share of "Title\nhttps://…" keeps the URL because the link is the part that can be reopened; and
   `SEND_MULTIPLE` is a separate action from `SEND`, which is why declaring only the first is how "share 6
   photos" silently does nothing.
6. **Both plugin entry points are two APIs, and handling one is the classic bug.** A share that *launches*
   the app and a share that arrives while it is running are different paths in the plugin and in the OS;
   so are a widget tap on a cold app and on a warm one. Handling only the first gives an app where sharing
   works once and then appears dead. All four funnel through one event each, so there is exactly one place
   a share or a tap becomes state. **Both are gated on the lock**, and neither is dropped: filing a share or
   opening the task sheet over the lock screen would act for someone who has not passed the challenge, so
   the pending item is held and a second listener runs it the instant the app unlocks.
7. **The `attachments` table finally has a writer, and the copy is the point.** It has been counted and
   cascaded by `ProjectsDao` since Phase 2 and written by nothing; a shared file is the first. A share
   intent hands over a path into OS-owned staging — Android's `content://` cache, iOS's share-extension
   container — which the OS deletes as soon as the share is over. Recording that path yields an attachment
   that opens for the rest of the session and is a dead link by tomorrow, which is the worst failure
   available: it looks saved. `AttachmentsService.attach` copies the bytes into the app's own storage
   first, names the copy by id (two shares of `IMG_0001.jpg` must not overwrite each other, and a filename
   from another app is not a path component to trust), and writes the row only after the bytes land.
8. **Storage Usage is measured, not estimated — `dbstat` made the honest answer possible.** Every module's
   rows live in one SQLite file, so "how much is Tasks using" is not a question the filesystem can answer.
   SQLite's `dbstat` virtual table reports pages per table, which *is* the on-disk cost; it was verified
   present in this SQLCipher-from-source build, and it is queried defensively — the flag is a compile-time
   option, and a fallback reports item counts with `isEstimated` set rather than a size the app cannot
   stand behind. Two traps found by measuring: the database file is **`everything.db.sqlite`**, because
   `drift_flutter` appends `.sqlite` to a name that already ends in `.db`, so the obvious filename measures
   nothing and confidently reports 0; and the `-wal` sidecar is part of the real footprint and is not small.
   The FTS index is named as its own line rather than folded into the modules it indexes — it holds a copy
   of every title and body in the app, so charging it to Tasks and Library would make each look twice its
   size — and `Other` exists so the parts add up to the whole honestly instead of rounding the difference
   into a named module.

**Requirement 25.1's Language section was deliberately not built, and this is the one gap in the phase.**
The app has *no* localization: no `flutter_localizations`, no `.arb` files, no delegates, no
`supportedLocales`, and every string in every screen is a hardcoded English literal. A language picker
would therefore be a control wired to nothing — worse than no control, because it is a promise the app
cannot keep and the only way to find out is to pick a language and watch nothing happen (CLAUDE.md §15
forbids exactly this). Localization is a phase of its own: extracting every string across ~40 screens,
**plus a second pass in the platforms' own resource systems** — the widget strings live in
`values/widget_strings.xml` and the Swift/Kotlin sources precisely because a widget has no Flutter engine
to ask. Two related things worth stating while they are in view: `Helpers.formatMoney` hardcodes `en_IN`
and `₹`, so a user outside India sees rupees, and `core/utils/` is protected — that is a developer change,
not an agent one. **AI Settings** was built around the one knob that is real today: Requirement 25.3 offers
"model precision or response style" as examples, and both are properties of a model this app does not have
yet (the engine is Phase 10's rule-based parser). A precision slider over a regex is a control wired to
nothing, the same mistake as the language picker. The **confidence threshold** is the genuine equivalent —
it changes what the assistant does with the next thing typed, which is what 25.3 actually asks for — and it
is threaded as `isConfidentAt(threshold)` so the pure intent types stay pure, pushed to `AiBloc` by event
dispatch. One bug caught in the writing: `AiOpened` emits `const AiState()` to reset the session, which
would have quietly reset the user's threshold to the default every time the sheet reopened — the slider
would appear to work until you closed the sheet.

**Three build-level findings, none of them optional:**
- **`receive_sharing_intent` 1.9.0 hardcodes `compileSdk 37`**, which AGP resolves to the platform hash
  `android-37`. That platform **does not exist and cannot be installed** — Google ships `android-37.0` and
  `android-37.1`, and there is no bare `android-37` in the SDK manager. Adding the plugin therefore breaks
  the Android build on a fully up-to-date SDK. `android/build.gradle.kts` pins the exact broken value to
  `android-36`, scoped so a fixed upstream release stops matching and the override retires itself. It must
  also sit **before** the existing `evaluationDependsOn(":app")` block, which forces evaluation — an
  `afterEvaluate` registered after it throws.
- **The iOS deployment target moved 13.0 → 14.0.** `home_widget` requires it and WidgetKit requires it
  regardless; there was no version of this phase that kept 13.0.
- **The two iOS targets are added by a script, not by hand:** `tool/add_ios_extension_targets.rb`, using the
  `xcodeproj` gem CocoaPods already vendors. A target is ~10 interlinked object graphs keyed by unique
  UUIDs, and hand-editing `project.pbxproj` is how you corrupt a project file. It is idempotent and worth
  keeping, because it encodes four things that each fail in a way that does not name the real cause:
  *`Embed App Extensions` must be ordered before Flutter's `Thin Binary` script* or Xcode reports "Cycle
  inside Runner"; *the share extension links the plugin's SPM product* via a local package reference into
  Flutter's generated checkout, whose path is **version-suffixed** (`receive_sharing_intent-1.9.0`) and so
  is read from the generated `Package.swift` rather than hardcoded, and must be re-run on a plugin upgrade;
  *`CUSTOM_GROUP_ID`* is a build setting on both targets so the App Group id is stated once — a mismatch
  does not error anywhere, the share simply vanishes; and *the extension `Info.plist` needs an explicit
  `CFBundleIdentifier`*, whose absence surfaces as "Embedded binary's bundle identifier is not prefixed with
  the parent app's" — pointing at the prefix when the real problem is that there is no identifier at all.

Two smaller traps, both silent: **`home_widget` stores under the bare key**, not a `widget.`-prefixed one, so
a prefix in the Swift reader returns nil for everything and the widget draws its empty state forever with no
error anywhere. And **`Text.strikethrough` must be called on `Text`**, before `lineLimit` — the View-level
overload is iOS 16+, so reordering two lines silently raises the deployment target the file needs.

**Tests (188 passing, up from 166; this phase adds 22):** the widget's **boundary**, not its drawing —
`toWidgetData`'s exact key set, and a task published with notes, a category and a project asserted to carry
its title and *none* of them. Plus `WidgetAction.fromUri` against the closed set, because registering a URL
scheme makes `everything://…` callable by **any** app on the device: it is matched against navigation targets
and nothing else — no ids read out of it, nothing looked up, nothing written — so the worst a hostile caller
achieves is opening a screen reachable from the app icon, behind the lock gate. And `SharedItem.fromText`,
which is the one piece of judgement in the share flow.

**The tests caught a real bug, which is the reason to note them.** `HomeWidgetPayload.build` is documented as
a pure function of `(tasks, now)` — but it called `Task.isOverdue`, which reads `DateTime.now()` internally.
So the payload silently read the wall clock, could not be asserted against an injected one, and a test written
in the past reported every task overdue. Overdue is now derived against the injected `now`, mirroring
`NotificationPlan`, which never calls `isOverdue` for exactly this reason. It also has to be `status == pending`
rather than `!isCompleted`: a **cancelled** task is not late, it is abandoned.

**Verified:** `flutter analyze` clean; 188 tests pass (the one failure is the pre-existing `ai_parser_test`
classifier edge from Phase 10, untouched and unrelated); `flutter build apk` and `flutter build ios
--no-codesign` both succeed. Checked in the built artifacts rather than assumed: both `.appex` bundles are
embedded in `Runner.app/PlugIns/`, `$(CUSTOM_GROUP_ID)` resolves to `group.com.karthik.everythingApp` in the
share extension's shipped `Info.plist`, the `everything` URL scheme is registered, and the merged Android
manifest carries the `SEND`/`SEND_MULTIPLE` filters and all three `APPWIDGET_UPDATE` receivers. **What no
build can check is in the device list below** — nothing here has been run on a phone.

### Phase 13 — On-Device LLM ✅ built, ⚠️ not yet spiked on a device
Swap the rule-based `AIRepositoryImpl` for a `flutter_gemma`-backed one. **No bloc, screen, or test
changes** — that is the entire payoff of Phase 10's interface.

Before committing, spike and measure on a real mid-range device: APK/IPA size delta, cold model
load, tokens/sec, peak RAM. Model is downloaded on demand, not bundled. If the numbers are bad,
the rule-based parser stays and this phase is dropped with no architectural damage — the app is
fully functional without it.

**It became a wrap, not a swap, and that is the finding.** The plan expected `AiRepositoryImpl` to be
replaced outright. Building it showed that would trade a fast, correct parser for a slow,
unconstrained one, so `ModelBackedAiRepository` **decorates** the rule-based engine and overrides
exactly two methods — `summarizeDocument` and `answerQuestion`. Everything above the interface is
untouched, which is still the payoff Phase 10 paid for; it just bought a narrower swap than the plan
imagined. **The feature is off by default and the app ships complete without it.**

Eight things worth carrying forward:

1. **The parsers stay rule-based, and the reasons are structural rather than a preference.**
   `flutter_gemma` 1.3.0 has **no constrained decoding and no JSON-schema output**, so a model-backed
   parser would prompt for JSON and fall back to the rule-based parser whenever the JSON came back
   malformed — strictly worse than the rule-based parser alone: identical answers when it works, wrong
   or slow ones when it does not. Two harder facts sit underneath that. `classifyIntent` is
   **synchronous** and runs on every keystroke — no model can implement it, so that method was never
   swappable and the interface quietly said so since Phase 10. And `AiBloc._emitPreview` re-parses on
   every debounced keystroke, where the rule-based parser costs microseconds and a generation costs
   seconds: the *interface* survives that swap, the typing does not. **The plan's "no changes at all"
   was true of the code and false of the experience**, and only the second one matters to a user.
2. **The model backs the two paths Phase 10 itself named as its ceiling.** Phase 10, note 5:
   `answerQuestion` is "the honest ceiling of a rule-based engine" and the model "can phrase the same
   grounded results more fluently; it does not get licence to invent new ones." That is now literally
   the design. `answerQuestion` runs the app's **own FTS search first, always**, through the delegate —
   the same index, ranking and query-cleaning Global Search uses — and the model is shown only the rows
   that came back. So the set of facts an answer can contain is **identical whether the model is loaded
   or not**; the model changes the wording, never the substance. An empty search never reaches it at
   all, because asking a model to explain an empty list is how it starts filling one in.
3. **`summarizeDocument` is the one place this phase genuinely trades correctness away, and it is why
   the switch exists.** Phase 10's extractive summary "can never misstate what the document says"
   because it lifts sentences verbatim. A generated one can. It is bounded — one document, told to use
   only that document — but it is a change in kind, not degree, and it is not ours to make on someone's
   behalf. Hence off by default.
4. **The switch has no flag — it loads or unloads the model, and that is the whole mechanism.**
   `ModelBackedAiRepository` asks one question: is a model in memory right now? `OnDeviceModelBloc` is
   the only thing that answers it. So switching off does not set a boolean every call site must
   remember to check; there is genuinely nothing to fall forward to, and the fallback is structural.
   Same shape as Phase 12's widget switch erasing its container rather than merely ceasing to publish.
   Every failure — no token, not downloaded, not loaded, generation failed, generation **blank** —
   lands on the rule-based engine silently, with no error state, because nothing the user did has
   failed. The blank case is the one a naive implementation ships broken: `success` is true, the string
   is empty, and an empty summary shown as a summary reads as a corrupt document.
5. **`+51.9 MB` of engine ships to everyone, and the plan did not budget for it.** "Downloaded on
   demand, not bundled" defers the **584 MB model** — it does **not** defer the runtime. Measured from
   a real arm64 release APK: `libLiteRtLm.so` 25.0 MB, two GPU accelerators 8.3 + 8.1 MB, the
   constraint provider 4.7 MB, and more, for **51.9 MB against an 85.6 MB app — a ~60% size increase
   for a feature that is off by default**. Worse, some of it is plainly dead weight on a phone:
   `libLiteRtWebGpuAccelerator.so` is a *web* backend, 8.1 MB, inside an Android APK. This is one of
   the four spike numbers and it is **already measured, already bad, and the only one obtainable
   without a device** — see the risks table.
6. **The model repo is gated, so `HF_TOKEN` is now a deployment dependency of the same kind as the
   weather and news keys.** `litert-community/Gemma3-1B-IT` is `gated: auto` — every download without a
   token 401s — so it lives in `.env` and is handled exactly as Phase 6, note 5 handles the other two:
   absent, the app is a working app minus its on-device model, and **says so in Settings** rather than
   offering a download that fails after 584 MB. It is read in `GemmaService` rather than added beside
   `kWeatherAPIKey` in `core/utils/constants.dart`, because that file is protected (§0); moving it
   there is a one-line developer change and the natural home for it.
7. **The package's own documented model URL does not exist.** `flutter_gemma`'s README installs
   `.../Gemma3-1B-IT/resolve/main/model.litertlm`; that repository has **no file by that name**, and the
   request 401s on the gate before the filename is ever reached — so the error names the token and
   hides the typo. The real portable build is
   `Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm` (584 MB). Its chipset-suffixed siblings
   (`_sm8650`, `_mt6989`, `_Google_Tensor_G5`) are NPU builds for exactly one SoC each and will not load
   on anything else, which is why the `multi-prefill-seq` build is the only sane default for a shipped
   app.
8. **A fresh inference session per call, closed straight after — for privacy, not tidiness.** The two
   prose calls are self-contained: there is no conversation to carry, and a retained session would let
   one document's text sit in the context of the next question. In an app holding a vault and bank
   details that is a real hazard, not a hypothetical one. `createSession` shares the loaded weights, so
   the cost is a KV-cache reset, not a reload. Relatedly, and enforced upstream rather than here: **a
   vault item cannot reach a prompt**, because its FTS source declares no body column (Phase 9, note 2),
   so a vault `SearchResult` carries a title and nothing else.

**Three build-level findings:**
- **The iOS deployment target moved 14.0 → 16.0.** MediaPipe/LiteRT-LM require it and there was no
  version of this phase that kept 14.0. It also caught a **latent Phase 12 bug**:
  `tool/add_ios_extension_targets.rb` hardcoded `DEPLOY = '14.0'`, so the next run of the extension
  script would have silently regressed both extensions below the app that embeds them. Now 16.0, with
  a comment naming the three places that must agree.
- **The first `flutter build ios` after raising the target fails with a stale generated manifest.**
  `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift` keeps the old
  `.iOS("13.0")` and the build reports *"The package product 'flutter-gemma' requires minimum platform
  version 16.0 … but this target supports 13.0"* — naming the plugin, when the real cause is a cached
  file. `flutter pub get` regenerates it **still wrong** (13.0); the *build* is what rewrites it to
  16.0. So: delete `ios/Flutter/ephemeral` and build again, and do not go looking at the plugin.
- **The engine packages version independently of the core** — core `^1.3.0`, engine
  `flutter_gemma_litertlm: ^1.1.0` — so the two constraints deliberately do not match, and matching
  them fails to resolve. The core registers **no** engine by default, so depending on it alone compiles
  and then throws a `StateError` at the first model call.

**Tests (207 passing, up from 188; this phase adds 19):** not the model — a 584 MB download cannot run
in CI, and asserting that a 1B model writes a good sentence is a spike, not a test. What is tested is
the **boundary**, which is where every decision in this phase lives. Chiefly: **the parsers must never
reach the model**, asserted by a fake that *fails the test if it is generated from* — so a future
`parseTaskIntent` override turns the suite red and names the line, rather than quietly making the
previews slow. Verified as a real regression test rather than a restatement: routing a parser through
the model mid-run does fail it. Plus grounding (the model sees the search hits and the question, and
is told in its system instruction that the list is all it has), and all four fallbacks — unloaded,
failed, **blank**, and empty-search — each producing the rule-based answer.

**Verified:** `flutter analyze` clean; 207 tests pass (the one failure is the pre-existing
`ai_parser_test` classifier edge from Phase 10, untouched and unrelated); `flutter build apk` and
`flutter build ios --no-codesign` both succeed. Checked in the artifacts rather than assumed: both
Phase 12 `.appex` bundles still embed and now report `MinimumOSVersion 16.0`, `sqlcipher.framework`
and `libsqlcipher.so` are **still present** (Phase 2's encryption survives the new build hooks), and
`LiteRtLm.framework` / `libLiteRtLm.so` ship on both platforms. **`libLiteRtLm.so` is arm64-only —
`armeabi-v7a` gets sqlcipher but no engine**, so a 32-bit device runs the app fine and can never load a
model, which the fallback already covers.

**What no build can check:** the other three spike numbers. Nothing here has run on a phone, and the
plan's gate is **not cleared**.

### Phase 14 — Hardening ✅ built, ⚠️ the on-device half is not cleared
Launch < 1 s, task create < 200 ms, search < 300 ms — measured on device, not in debug mode.
Golden tests for the four reference screens. Accessibility pass. Store assets.

**The four reference screens have goldens, and they paid for themselves on the first run.** The
accessibility pass found a short list rather than a long one. The performance bar splits cleanly in
two: the parts a host can measure are measured and are nowhere near their budgets, and the part that
needs a phone is named below rather than asserted. Store assets are further from done than "icons
exist" suggests.

Seven things worth carrying forward:

1. **A state getter that reads the wall clock is not a function of its state, and three of them were.**
   `TasksState.todayTasks` and `.dateGroups` called `DateTime.now()` *inside the getter*, as did the
   weather and news staleness getters — so the same state rendered differently depending on when you
   looked at it, and no golden of the Dashboard or Tasks could ever be stable. This is **the same bug
   Phase 12 caught in `HomeWidgetPayload.build`** ("documented as a pure function of `(tasks, now)` —
   but it called `Task.isOverdue`, which reads `DateTime.now()` internally"), one layer up, and the
   codebase already had the right answer sitting next to it: `FinanceState.totalsFor(now)` takes an
   injected `now`, for exactly the reason Phase 6, note 1 explains. The literal calls in `bloc/`,
   `view/` and `Task.isOverdue` now go through `clock.now()`, which is `DateTime.now()` in production
   and freezable under `withClock` in a test. **The goldens are what forced this into the open** — the
   wall-clock reads were invisible for eleven phases because nothing had ever tried to render a screen
   at a known instant.
2. **`core/utils/extensions.dart` is protected, reads the clock, and that is the ceiling on these
   goldens — flagged, not fixed (§0).** `isToday`, `isTomorrow`, `isYesterday` and `isPast` each call
   `DateTime.now()` directly, and `relativeLabel` is built on the first three. `task_card` renders
   `due.relativeLabel`, so under a frozen clock the Tasks day sections read `15 Jan` where a device on
   that date reads **Today**. That is *stable* — wrong by the same amount every day, so the golden
   still pins layout, type and colour — but it means the goldens do not exercise the relative wording,
   which is a real gap on the one screen whose grouping is the feature. The fix is four lines
   (`DateTime.now()` → `clock.now()`) in a file agents may not touch, and it belongs to the developer
   alongside §4's theme values and Phase 13's `HF_TOKEN` constant. `Task.isOverdue` lives in
   `data/models/` and is **not** protected, which is why the red Overdue section in the Tasks golden is
   real while Today/Tomorrow is not.
3. **The goldens caught a currency bug on the first render, which is the entire argument for them.**
   **`JetBrainsMono.ttf` has no `U+20B9` (₹).** Verified against the font tables, not inferred: Inter
   and Noto Serif carry the glyph, JetBrains Mono does not. §4 assigns **monospace to amounts**, so
   every figure on Finance — the donut total, the budget bar, the income/spent/saved row, every
   transaction — asks a font for a glyph it does not have. The Dashboard's `₹33,000` renders correctly
   because it is styled in Inter. So the app renders the rupee sign in two different typefaces on two
   screens, and on Finance it survives only on OS font fallback, meaning the symbol comes out in a
   different face from the digits beside it. **This is invisible on a device** — the OS quietly
   substitutes — which is exactly why eleven phases of running the app never surfaced it, and a golden
   with only the bundled fonts loaded did so immediately. The Finance golden is left honest, showing
   the tofu, rather than papered over with a fallback the harness would have to fake. The fix is a
   developer decision: subset a ₹ into JetBrains Mono, or style amounts in Inter and give up the
   monospace figure alignment §4 asked for. **Nothing in the app is broken; the symbol is just not
   ours to place.**
4. **Task create is measured at ~0.13 ms against a 200 ms budget, and the number's value is what it
   rules out.** Five creates through the real `TasksRepository → TasksService → TasksDao` path against
   a **seeded 10,000-row table**, warmup discarded: 395 µs worst, ~130 µs steady. The benchmark
   asserts the **FTS triggers actually fired** (`search_index` count goes 10,000 → 10,006 across the
   measured writes) — without that it could pass while measuring a write that skipped Phase 9's
   trigger, which is the worthless case. The honest reading is not "the bar is cleared": 200 ms is a
   *user-perceived* budget (tap → the task is on screen) and this measures the database portion, which
   turns out to be **0.1% of it**. So if a device ever misses 200 ms on task create, the cause is
   upstream of SQLite — a bloc rebuild or a frame — and this bench is what lets that be said without
   guessing.
5. **The pre-existing `ai_parser_test` failure was never a classifier bug — the test's example was
   wrong, and four phases of "unrelated" hid it.** It has been red since Phase 10 and waved through by
   Phases 11, 12 and 13 as a "classifier edge". It is not an edge: `classify('Buy milk tomorrow')`
   returns `toBuy`, and **that is correct**. `AiIntent` has ten values, the sheet renders a chip for
   every one (`for (final mode in AiIntent.values)`), and `AiBloc` has a full create branch and preview
   card for `toBuy` — so "Buy milk tomorrow" preselects To Buy and files a shopping item, which is what
   it is. The test was written when the line was a stand-in for a generic to-do and it picked the one
   example that later became a real destination. The assertion is now pinned rather than deleted (a
   shopping line *is* a to-buy item; `Call the dentist` is the plain to-do) — deleting it would have
   been hiding it twice. **The lesson is the "pre-existing and unrelated" label itself**, which is how
   a wrong test survived three phases of being read and not examined.
6. **`TasksService.create` was returning `'DEBUG: $e'` to the user.** The app's most-used write path
   (Phase 3: "the most-used module — build it first and completely") caught its exception and put the
   raw `toString()` into the failure message the UI shows in a SnackBar — flush-left indented, the
   shape of debugging left behind. Every sibling method in the same file returns a sentence. It now
   does too. Two things this is worth stating for: it is the only `DEBUG:` in `lib/`, and it violated
   §18 quietly for however long it stood — a caught exception leaking its type name to a user is the
   failure mode §18 exists to prevent, and nothing about it looked wrong from the outside because the
   path only runs when a create fails.
7. **The accessibility pass was short because the codebase was already doing the work.** Tooltips are
   the house pattern — 40 `tooltip:` against 32 `IconButton(` — so the audit's long list of candidates
   collapsed to **seven** real gaps: two untooltipped icon buttons, a colour swatch that announced
   nothing at all, and four selection chips whose **selected state was carried by fill colour and font
   weight alone**, which a screen reader cannot hear. Those four now pass `button: true` + `selected:`
   and no `label:`, because each already has a visible `Text` that would be overridden — the reason
   `app_bottom_nav` *does* pass one is that its child is an icon. The four chips were deliberately
   **not** unified into a shared widget: the three type-chips are near-identical bodies over three
   unrelated enums with no shared interface, so one generic chip would mean extractor callbacks
   threaded through three working call sites, and the fourth is text-only with different styling. §0's
   "minimum code for the ask" wins over a de-duplication that is only skin-deep. The real precondition
   — a shared `label`/`icon` interface on those enums — is named here rather than smuggled in under an
   accessibility fix.

**Store assets are not one item, and the gap that matters is not the icons.** Launcher icons are
genuinely done: `flutter_launcher_icons` is configured and generated for both platforms, adaptive
Android with the §4 `#0F0F0F` background, and iOS 18 dark and tinted variants. What is missing is
everything else, and one piece of it is a hard gate: **there is no `PrivacyInfo.xcprivacy` on any of
the three iOS bundles.** `ios/EverythingWidget/EverythingWidget.swift` reads
`UserDefaults(suiteName:)` — Phase 12's App Group channel, the whole mechanism by which a widget draws
anything — and that is a **required-reason API**. Twelve of the app's own plugins already ship
manifests, so the mechanism is plainly in play; the three first-party bundles (Runner, the share
extension, the widget) declare nothing. Apple rejects this at upload with ITMS-91053, so **the app
cannot currently be submitted to the App Store** — which no build check catches, because it is not a
build error. It is not written here on purpose: a manifest with guessed reason codes is a false
declaration to Apple and worse than an absent one, and the correct codes depend on the final plugin
set at submission. The rest — listing copy, screenshots, a privacy policy URL, `fastlane`/`metadata` —
is developer and store work, not code, and none of it exists.

**Tests (220 passing, up from 214; this phase adds 5 and repairs 1):** four goldens and a benchmark.
The goldens are of the **real** thing or they are worth nothing, which is the same argument Phase 2
made about testing encryption against the bytes on disk: they render the production `ThemeData` via
`AppTheme.build`, on a fixed 390×844 surface at 1:1, with the three real bundled fonts **and**
MaterialIcons loaded off the SDK by hand — a widget test builds no asset bundle, so every glyph, text
and icon alike, otherwise comes out an empty box, and *a golden of a screen of boxes passes forever
and proves nothing*. `test/flutter_test_config.dart` throws rather than degrading if a font is missing,
for the same reason `AppDatabase._verifyKeyed` shouts about `PRAGMA cipher_version`. Each golden was
**looked at**, not just diffed: Library's amber tiles and derived counts, the Tasks calendar strip with
its red Overdue section and priority dots, Finance's donut and its 116%-over budget bar, the
Dashboard's serif greeting and amber weather pill. That is how the ₹ was found.

**Verified:** `flutter analyze` clean; **220 tests pass, 0 failing — the suite is green for the first
time since Phase 10.** The Android build succeeds with `clock` added. No protected path was modified.
The goldens were checked to actually **bite** rather than merely pass: changing one visible string in
`library_page` fails its golden, and reverting passes it — a golden that cannot fail is the same trap
as Phase 2's round-trip-through-the-keyed-handle test, and the check is what tells them apart.
**What no host can check is the device list in §8** — launch < 1 s in particular has not been measured
at all, and is not measurable here: it needs `flutter run --profile --trace-startup` on a real phone,
because a debug-mode launch on this Mac measures the JIT, not the app.

---

## 6. Testing

Test only what is **crucial** — the logic that is security-sensitive, destructive, or a
consequential calculation, where a silent regression is expensive and non-obvious. Do **not** aim
for exhaustive coverage; skip trivial UI, getters/setters, and generated code (CLAUDE.md §17).

What earns a test:
- **Money & budgets** — integer minor-unit arithmetic and budget thresholds (Properties 6, 7, 8).
  A rounding or threshold error here is wrong numbers the user trusts.
- **Encryption & auth** — DB-at-rest encryption (tested against bytes on disk), vault item-level
  encryption (tested against ciphertext), PIN hashing/lockout, backup HMAC verify + tamper abort
  (Property 10). These protect the data; a round-trip test that passes on plaintext proves nothing.
- **Data-integrity rules** — recurrence generating exactly one occurrence (Property 4), watchlist
  progress clamping/completion (Property 16), notification reconciliation and queue partitioning.
- **Search** — the < 300 ms bar against a seeded 10k-item DB (Property 5), benchmarked not assumed.
- **The performance budgets** — task create < 200 ms against the same seeded 10k DB, through the real
  repository path with the FTS triggers asserted live (Phase 14). Same rule as search: benchmarked,
  not assumed.
- **The four reference screens** — goldens (Phase 14). The exception to "skip trivial UI", and only
  these four: §4 defines their design precisely, and a golden is the only thing that notices when a
  colour, a typeface or a grouping quietly moves. They render the production theme and the real
  bundled fonts, because a golden of the wrong pixels is worse than none.

Everything else (individual bloc state sequences, other widget/golden screens, broad integration
flows) is written only when a specific bug or a genuinely high-risk path calls for it — not by default.

Tooling: `glados` for property tests, `bloc_test`/`mocktail` where a bloc test is warranted.
Repository tests run against an **in-memory Drift DB** (`NativeDatabase.memory()`), so no SQLCipher
key is needed in CI.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| On-device LLM size/latency makes it unshippable | **Half-realised, and the size half is measured.** The engine adds **+51.9 MB to every build** whether or not the user ever enables it (Phase 13, note 5) — "downloaded on demand" defers the 584 MB model, not the runtime. Latency was answered structurally instead of measured: the parsers were never given to the model, so no keystroke path can be slow. The rule-based engine remains a complete fallback and the feature is off by default, so the phase is still droppable — deleting it reclaims 52 MB and iOS 14/15 |
| On-device LLM's three unmeasured numbers | **Open.** Cold model load, tokens/sec and peak RAM need a mid-range phone; the plan's spike gate is not cleared. If they are bad, drop the phase — nothing depends on it |
| iOS 16 excludes iOS 14/15 devices | **New, and the cost of Phase 13 alone.** MediaPipe/LiteRT-LM require 16.0; no version of that phase kept 14.0. Nothing else in the app needs it, so dropping Phase 13 returns the floor to 14.0 |
| ~~Home widgets are native, not Flutter~~ | **Held.** Isolated in Phase 12; the app is fully usable with them switched off, and the Settings switch makes that a real choice |
| ~~iOS Share Extension is fiddly (app groups, entitlements)~~ | **Held, and it did not slip.** Both iOS targets build and embed; the fiddly parts are scripted in `tool/add_ios_extension_targets.rb` rather than left as Xcode folklore |
| Widget data sits outside the SQLCipher database | **New, and structural — it cannot be designed away.** A widget process has no key. Mitigated by publishing the minimum (titles, counts, one formatted figure), **never the vault**, and a Settings switch that erases the container (Phase 12, note 1) |
| **No iOS privacy manifest on any first-party bundle** | **New, open, and a hard gate.** The widget reads `UserDefaults(suiteName:)` — a required-reason API — and Runner/share-extension/widget declare nothing, so the App Store rejects at upload (ITMS-91053). No build catches it. Not written speculatively: wrong reason codes are a false declaration and worse than none (Phase 14) |
| **JetBrains Mono has no ₹ glyph** | **New, open, and invisible on a device.** §4 puts amounts in monospace; the font lacks `U+20B9`, so Finance's figures survive on OS fallback and render the symbol in a different face from its digits. Found by a golden, not by use. Fix is a developer call: subset the glyph in, or style amounts in Inter and lose the figure alignment (Phase 14) |
| Wall-clock reads in protected `core/utils/extensions.dart` | **Flagged, not fixed (§0).** `isToday`/`isTomorrow`/`isYesterday`/`isPast` call `DateTime.now()`, so the Tasks golden cannot exercise Today/Tomorrow wording. Four-line developer change; everything else now goes through `clock.now()` (Phase 14) |
| Plugin `compileSdk` outruns the installable Android SDK | Pinned in `android/build.gradle.kts`, scoped to the exact broken value so it retires itself upstream (Phase 12) |
| SQLCipher + Drift build issues on iOS | Proven in Phase 2, before any feature depends on it |
| FTS5 misses the 300 ms bar | Benchmarked at Phase 9 against a seeded 10k dataset, not at the end |
| Float money errors break Properties 6/7 | Integer minor units from day one — not fixable later without a migration |
| `core/utils/*` is protected but the theme is unbuilt | §4 values handed to the developer for those files; agents never touch them |

---

## 8. Immediate Next Steps

Phases 1–12 are done. Phase 13 is **built but not spiked** — its code is complete and both platforms
build, but the plan's own gate (measure on a real device, drop it if the numbers are bad) has not been
cleared, so it is not yet a decision. Phase 14 is **built, with its on-device half open**: the suite is
green (220, 0 failing) and the host-measurable budgets are measured, but launch < 1 s has not been
measured at all, and it left three things on the developer's desk that an agent may not or should not
do — the ₹ glyph (§4/Phase 14 note 3), the four-line `clock.now()` change in protected
`core/utils/extensions.dart` (note 2), and the iOS privacy manifest that currently blocks submission.
Next:

1. **Add the two API keys to `.env`** — `WEATHER_API_KEY` (OpenWeatherMap) and `NEWS_API_KEY`
   (NewsAPI). Until they are there the Dashboard renders in full and says, in the weather pill and
   under the news tabs, exactly what it is missing. Then set a city and confirm the pill, the detail
   screen, and — in airplane mode — that both sections still show what they last fetched.
2. **Verify the notification queue on a real device.** Two things no test can cover. First, the
   Phase 4 check that was already outstanding: set a task two minutes out, kill the app, confirm the
   notification arrives — on an Android 14+ device with the exact-alarm permission *refused* as well,
   to confirm the inexact fallback still delivers. Second, and new: set a task reminder **and** a
   to-buy reminder, then edit the task. Both must still fire. That is the partition from Phase 7's
   note 1, and it is the one bug in this area that a passing test suite and a working-looking app
   would both hide.
3. **Set an app PIN before using the vault.** With no PIN and no enrolled biometrics there is nothing
   to challenge against, and the vault says so rather than opening. This is the same rule as the app
   lock (Phase 2): the lock gates the UI, the keys protect the data.
4. **Confirm the search backfill on a device that already holds data.** The FTS index is created and
   backfilled on first open after this build ships (Phase 9, note 1). On a fresh install the triggers
   cover everything from the first write, so this only matters for an upgrade over an existing
   database: open the app, search for a task or transaction created in an earlier build, and confirm
   it is found — the one path the in-memory tests, which always start empty, cannot exercise.
5. **Try the assistant on real phrasing, and confirm the create path end to end.** The dock's sparkle
   now opens the AI sheet. Type "Buy milk tomorrow" and confirm a task lands on tomorrow; type "Spent
   500 on food" and confirm an expense of ₹500 under Food against the first account. Then the two
   things a test cannot cover: an amount-less "lunch at the cafe" in Expense mode must ask "How much
   was it?" rather than saving nothing, and the mode chips must let a misclassified line be corrected
   in one tap. A device with **no accounts seeded** should get "Add an account first" rather than a
   silent failure.

6. **Verify backup and restore on a real device.** Two things no test covers. First, take a
   backup, add and delete a few things across modules, then restore it and confirm every module —
   tasks, finance, the vault, documents — is back to the backed-up state and that Global Search
   still finds a restored item (the FTS index is rebuilt by triggers on the re-insert, not by a
   reindex step). Second, share a backup out via the share sheet to confirm it reaches a cloud
   drive; note that a shared backup restores only onto **this** install until the key is made
   passphrase-derived (Phase 11, note 2). Also export a document to PDF and confirm the OS share
   sheet opens with a readable file.

7. **Verify the share extension on both devices — this is the highest-value check on this list,
   because a compiling extension and a working one are very different claims.** Both targets build and
   embed, but nothing here has run on a phone. Share a link from the browser into Everything: it must
   offer Bookmark / Task / Document, and Bookmark must produce a row identical to one typed into the
   Library. Then the three cases a build cannot check. **(a)** Share into the app while it is *already
   running* — that is the plugin's second API, and if only the launch path were wired, sharing would
   work once and then silently do nothing. **(b)** Share into a *locked* app: the chooser must not
   appear over the lock screen, and must appear the moment you unlock — the share is deferred, not
   dropped. **(c)** On iOS, share a PDF and attach it to a project, then **force-quit, reboot, and open
   the attachment**: this is the one that proves `AttachmentsService` copied the bytes instead of
   recording the OS's temporary path, and a share-extension path that has been cleaned up is exactly
   the failure that looks fine all session and is a dead link tomorrow.
8. **Place all three widgets, at every size, on both platforms.** Nothing about how a widget *looks* is
   testable from a build. Check: a task list that shrinks from four items to two leaves no stale rows;
   an overdue task sorts to the top and shows "Overdue"; a date-only task shows no time; the spend
   figure matches the Finance tab **exactly**, including the lakh grouping (if it does not, something
   native is formatting money and must stop). Then tap each quick-add pill and confirm it lands on the
   right sheet rather than the Dashboard — on iOS that exercises the `everything://` scheme, which is
   registered but has never been opened. **On a device where the app has never run, a widget must draw
   its empty state, not a crash** — that is the `home_widget` bare-key path (Phase 12) which, if wrong,
   fails silently and forever.
9. **Switch the widgets off in Settings and confirm the container is actually emptied** — the home
   screen must fall back to its empty state, not freeze on the last snapshot. This is the switch the
   whole "data outside the encrypted database" trade rests on (Phase 12, note 1), and the only way to
   know it does what it says is to watch it. While there: confirm the **vault is absent from every
   widget at every size**, which is the invariant the code makes structural and a device makes obvious.
10. **Check Storage Usage against reality on a device with real data.** The per-module figures come from
    `dbstat`, which was verified present in this SQLCipher build on the host but not on a phone. If the
    lines show "—" instead of sizes, the fallback fired and the flag is absent from the device build —
    which is worth knowing, and is exactly why it degrades to item counts rather than throwing. The
    total should be in the same neighbourhood as the OS's own storage figure for the app.
11. **Finish Phase 13's spike, then decide whether to keep it — the decision is genuinely open.** The
    phase is built, analyzes clean, and both platforms build, but **the gate the plan put in front of it
    is not cleared**. One of the four numbers is in and it is not encouraging: **+51.9 MB on every
    build, for a feature that is off by default** (Phase 13, note 5), plus an iOS floor raised to 16.0
    that nothing else in the app needs. The three that need a phone: **cold model load** (time from tap
    to first answer), **tokens/sec**, and **peak RAM** while loaded — on a mid-range device, not this
    Mac. Add `HF_TOKEN` to `.env` first or Settings will correctly refuse to download.
    Then the two things only a device shows: that a 584 MB download over mobile data behaves (it is
    `background_downloader`, so it should survive backgrounding — confirm), and that a summary of a real
    document is actually **better** than Phase 10's extractive one. If it is not, that is the whole
    justification gone, because the parsers were never the model's to improve.
    **Dropping it is cheap and stays cheap:** remove two dependencies, one decorator, one bloc and one
    Settings tile; the interface, the sheet, the AI tests and every parser are untouched, and the app
    reclaims 52 MB and iOS 14/15. That optionality is what Phase 10's interface actually bought, and it
    is worth more than the model.
12. **If Phase 13 is kept, the AI Settings gap Phase 12 named is now open to close.** Requirement 25.3's
    "model precision" and "response style" stop being controls wired to nothing once a model exists —
    they would sit beside the confidence threshold. Worth stating that they are *still* not obviously
    worth building: the model backs two prose methods, and a temperature slider over a document summary
    is a control over something nobody has an opinion about (Phase 13, note 3).
13. **Still outstanding, and now unblocked by nothing:** the platform background worker did **not** land
    in Phase 12 — building it revealed a worker cannot re-read the database either (Phase 12, note 4), so
    it bought nothing for widgets. Automatic backup therefore remains opportunistic-at-launch (Phase 11,
    note 5). If a real schedule is wanted, the change is a **Dart background isolate** that opens
    SQLCipher off a secure-storage key read — which would serve backups and widget recomputation at once,
    and is the only thing that would.
14. **Localization is now a named gap, not an oversight** (Phase 12). Requirement 25.1's Language section
    is the one part of the requirement not built, because a picker over hardcoded English strings is a
    control wired to nothing. Doing it properly is its own phase: every string in ~40 screens, plus a
    second pass in the platforms' resource systems for the widgets, plus `Helpers.formatMoney`'s
    hardcoded `en_IN`/`₹` — which lives in protected `core/utils/` and is a developer change.
15. **Write the iOS privacy manifest before attempting any submission — this blocks the App Store
    outright** (Phase 14). The widget's `UserDefaults(suiteName:)` is a required-reason API and none of
    the three bundles declares one, so the upload fails with ITMS-91053 and no build will warn you. It
    needs a `PrivacyInfo.xcprivacy` on Runner, the share extension **and** the widget (three bundles,
    three files), with the reason codes that are actually true of the final plugin set — `CA92.1` for
    the App Group's UserDefaults, plus whatever `path_provider`/`flutter_secure_storage` pull in. It is
    deliberately not guessed here: a false declaration to Apple is worse than an absent one. While
    there, the rest of "store assets" is untouched — listing copy, screenshots, a privacy policy URL.
    The icons are done and need nothing.
16. **Decide the ₹, and it is a design decision, not a bug fix** (Phase 14, note 3). JetBrains Mono has
    no `U+20B9`, and §4 puts amounts in monospace — so Finance's figures render the rupee through OS
    fallback in a face that does not match their digits, on every device, today. Either subset a ₹ into
    `JetBrainsMono.ttf` (keeps §4's monospace figure alignment, costs a font-pipeline step) or style
    amounts in Inter (free, gives up the alignment that made §4 choose monospace). **Look at the
    Finance screen on a phone next to the Dashboard before choosing** — the Dashboard's `₹33,000` is
    Inter and correct, so the two screens are a live A/B of the answer. Re-generate the Finance golden
    once decided: it currently, honestly, records the tofu.
17. **Four lines in `core/utils/extensions.dart` would finish the Tasks golden** (Phase 14, note 2).
    `isToday`/`isTomorrow`/`isYesterday`/`isPast` call `DateTime.now()`; routing them through
    `clock.now()` (the package is already a direct dependency and the rest of the app is converted)
    makes `relativeLabel` honour a frozen clock, at which point the Tasks golden exercises the
    Today/Tomorrow grouping that is the screen's whole feature instead of rendering `15 Jan`. Protected
    path, so it is the developer's to make; the goldens then need one `--update-goldens`.
18. **Measure launch on a device — the one budget with no number at all** (Phase 14). Task create is
    ~0.13 ms against 200 ms and search is benchmarked under 300 ms, both against a seeded 10k database,
    so the two bars with host-measurable components are covered. Launch < 1 s is not: it wants
    `flutter run --profile --trace-startup` on a real mid-range phone, because a debug launch measures
    the JIT rather than the app. Worth doing on the same run as Phase 13's spike, since `start.dart`
    already awaits its bootstrap concurrently and the on-device LLM's `+51.9 MB` is exactly the kind of
    thing that shows up first at launch.
