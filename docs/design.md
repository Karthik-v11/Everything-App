# Design: Dashboard Overhaul + Daily Briefing

Reference: `docs/UI Updated/Dashboard (5).png`

This document covers one change set: the Dashboard redesign, the AI-generated daily
briefing, the floating pill navigation bar, and the typography switch to Outfit +
JetBrains Mono. Architecture is BLoC + Drift, per `CLAUDE.md`. It supersedes the
previous `design.md`, which described a Riverpod/clean-architecture layout the code
never adopted.

---

## 1. What the mock asks for

Read top to bottom, the mock is seven bands:

| Band | Today | Target |
|---|---|---|
| Greeting | serif headline + avatar button | same headline, avatar kept (§6.1) |
| Date / weather | label+value column, filled amber pill | two outlined pills: `15th July, Wednesday` · `Bengaluru, 27° C` + icon |
| **Briefing** | — | gradient-bordered card, asterisk avatar, generated prose |
| Agenda | left-aligned `Today's Tasks` + `See All` | centred `Today's Agenda`, subline `3 Overdue · 7 tasks today` |
| Task rows | `TaskCard` | restyled: due-status line, category chip, priority-tinted check ring |
| Finance / Upcoming | 4-card horizontal scroller | two fixed panels: budget remaining + next event |
| Top Stories | `News` + category tabs + stacked cards | `Top Stories` + score cards + thumbnail-right rows |
| Nav | 4 detached pills + 64px dock | single floating pill + red circular AI orb |

Three of these are new construction rather than restyling: the briefing, the
Upcoming panel, and the score cards.

---

## 2. Scope decisions

### 2.1 Protected files are in scope, by instruction

`lib/core/utils/theme.dart` and `lib/core/utils/app_text_styles.dart` both carry
`DO NOT MODIFY.`, and `CLAUDE.md` §0 protects `core/utils/`. The font change cannot
be done anywhere else — every widget reads `Theme.of(context).textTheme.*`, which is
the correct design and the reason the edit belongs there. **The developer has
explicitly sanctioned this edit**, which is what §0 requires. It stays limited to the
family constants, the `textTheme` slot map and the default accent; no other part of
`core/utils/` is touched, and the `DO NOT MODIFY.` markers stay in place for the next
change set.

### 2.2 Score cards are deferred

The mock shows a cricket card (`IND 202/8 (50)` vs `ENG 180/8 (50)`, `2nd ODI`) and a
football card (`ESP 2 - 1 ARG`, `Finals`). **No scores data exists anywhere in the
app.** `NewsCategory.sports` fetches ordinary headlines; `Article` carries only
`title, url, source, imageUrl, publishedAt`. Live scores need a new provider
(cricket and football are usually separate APIs), a new model, service, repository
and bloc, plus a polling story that fights the offline-first design.

That is a feature in its own right, not part of a UI overhaul. **Phase 1 ships Top
Stories without the score row**, and §7 sketches the seam so it can land later
without re-cutting the section.

### 2.3 The briefing is fed by events, never cross-bloc reads

§4.4 forbids a bloc reading another bloc's state. The briefing needs tasks, weather
and news — three other blocs. So `BriefingBloc` owns no sources: the Dashboard pushes
facts in via `BriefingFactsChanged`, the same way `SettingsBloc` pushes
`ConfigureAiEvent` today.

---

## 3. Typography

| Role | Now | Target |
|---|---|---|
| Headings (`display*`, `headline*`) | `NotoSerif` | **`Outfit`** |
| Body / titles (`title*`, `body*`) | `Inter` | **`Outfit`** |
| Labels / numerals (`label*`) | `JetBrainsMono` | `JetBrainsMono` (unchanged) |

Two families, not three. Outfit is a geometric sans and cannot carry the serif's
heading role by weight alone, so the heading slots gain weight and tighten tracking:
`w600`/`w700` at `letterSpacing: -0.4` for `headline*`/`display*`. Amounts, dates
and the `3 Overdue · 7 tasks today` subline stay mono — that contrast is what the
mock is doing.

**Bundling.** Fonts stay bundled variable TTFs; `google_fonts` remains rejected
(offline-first first launch must render in the right face). Add
`assets/fonts/Outfit.ttf`, declare family `Outfit`, drop the `NotoSerif` and `Inter`
declarations and delete both TTFs once no reference remains.

**Changes** in `app_text_styles.dart`:
- `serifFamily`/`sansFamily` → a single `sansFamily = 'Outfit'`; `serif()` and
  `sans()` collapse into `sans()`. Call sites outside the `textTheme` map are grep'd
  and moved.
- The `FontSize` scale contract (0.9 / 1.0 / 1.15, applied per slot) is unchanged.

The doc comment on the class, which currently states the serif/mono/sans split as
policy, is rewritten to state the new two-family rule.

---

## 4. Colour

The mock is near-black with a **dark red radial glow behind the greeting**, and a red
accent (check rings, `Overdue`, the AI orb, the active nav icon). The app already has
`AppColors.accentRed`; `AppThemeVariant.amoled` already gives `0xFF000000`.

- **No new hardcoded colours.** The glow is `colors.primary` at low alpha, so it
  follows the user's chosen accent rather than pinning the app to red.
- Ships as a `_GreetingGlow` — a `RadialGradient` `Container` behind the header,
  `primary.withValues(alpha: 0.18)` → transparent. It is decorative: no `Semantics`,
  and it sits under an `IgnorePointer`.
- Red-as-default is a **settings default change**, not a theme rewrite: `ThemeState`'s
  default `accentValue` moves amber → red. Existing users keep their hydrated choice.
- `onPrimary` stays `0xFF141414` (theme.dart:57). Verify contrast of the red accent
  against it — if AA fails for the orb icon, the orb uses `onSurface` on `primary`
  rather than introducing a second `onPrimary`.

---

## 5. The Daily Briefing

> "AI response generating my plan for now based on time, date, season, breaking news
> and tasks."

### 5.1 Where it runs

The assistant's engine is **Gemini** — `app.dart` wires
`ModelBackedAiRepository(engine: GeminiRepository)`. The on-device Gemma stack was
removed: it was never the assistant's path (1B@q4 needs ~1.5 GB resident vs ~1 GB free
on target), so it cost a 584 MB download and the iOS 16 floor while backing nothing.
The briefing uses the same `TextEngine` seam, so it inherits whichever engine is wired
and needs no knowledge of which.

`TextEngine.generate` is a single awaited `getResponse()` — **there is no streaming**.
The briefing therefore appears at once, and the card must have a resting state that
looks intentional while it does not (§5.5).

### 5.2 New prompt: `AiPrompt.briefing`

`AiPrompt` today holds exactly two prompts, both single-source and grounded by
construction, and its doc comment argues that grounding *is* the safety story. The
briefing is the first **multi-source** prompt, so it must extend that argument rather
than quietly break it.

```dart
static const String briefingSystemInstruction =
    'You write one short daily briefing for the owner of a personal organiser app. '
    'Use ONLY the facts given to you. Never invent a task, a number, a date, a '
    'headline or a weather reading. Do not give advice, opinions or encouragement. '
    'Two or three sentences of plain prose, no Markdown, no preamble.';

static String briefing({required BriefingFacts facts});
```

The prompt body is assembled from `BriefingFacts` under fixed headings
(`Now:`, `Weather:`, `Tasks:`, `Headlines:`), each omitted when its source has
nothing. `AiPrompt` stays pure and static — no clock, no plugin, no database — which
is what keeps the one piece of judgement here unit-testable.

Caps, in the spirit of `maxGroundingResults = 8`:
- `maxBriefingTasks = 6` — titles and due-status only.
- `maxBriefingHeadlines = 3` — titles and source only. `Article` has no body, so a
  headline can only ever be named, not explained.
- **No vault, no finance, no account figures.** The mock's briefing speaks about the
  day, and money is one prompt-injection-shaped mistake away from a bad afternoon.

### 5.3 New entity: `BriefingFacts`

`lib/data/entity/briefing_facts.dart` — mutable, not `Equatable`, outbound-only,
`toJson()` + `copyWith()`, no `fromJson()` (§8).

```dart
class BriefingFacts {
  DateTime now;                 // time + date
  Season season;                // derived, not stored — see below
  String? city;
  Weather? weather;
  int taskCount;
  int overdueCount;
  List<String> taskTitles;      // capped at maxBriefingTasks
  List<String> headlines;       // capped at maxBriefingHeadlines
}
```

**Season** is a new `Helpers.seasonOf(DateTime)` returning a `Season` enum. The app is
India-first (`NewsCategory.all` is `{country: in}`, weather defaults to Bengaluru), so
the four-season Western calendar is wrong: the enum is
`summer, monsoon, postMonsoon, winter` mapped by month. This is a rule with a real
business reason and gets a one-line comment saying so.

### 5.4 `BriefingBloc`

Style A (single class + `copyWith`), `HydratedBloc` — the card must be populated on
cold launch before any request completes, exactly as `WeatherBloc`/`NewsBloc` are.

```
lib/bloc/briefing/
  briefing_bloc.dart
  briefing_event.dart
  briefing_state.dart
```

**State** — `isLoading, error, message, text, generatedAt, isFallback`.
Hydrates `HydratedText` + `HydratedGeneratedAt` only. Getters: `hasText`,
`isStale` (reuses `kStaleCacheThreshold`), `age`.

**Events**
- `BriefingFactsChanged({required BriefingFacts facts})` — the Dashboard's push.
- `RefreshBriefingEvent` — the pull gesture.

**Regeneration policy.** Facts change on every task keystroke elsewhere in the app; a
generate-per-change would be an API call per toggle. The bloc regenerates only when:
1. there is no text, or
2. `generatedAt` is not on the same calendar day as `facts.now`, or
3. the greeting bucket changed (morning → afternoon → evening), or
4. `RefreshBriefingEvent` arrived.

Otherwise `BriefingFactsChanged` stores the facts and emits nothing. Rule 3 is why
the card can say "Good morning" and still be right after lunch.

`_onBriefingFactsChanged` guards on `isLoading` so a slow generate cannot be stacked
by a scroll-driven rebuild.

**Failure is never an error card.** On `JsonResponse.failure` — offline, no API key,
quota — the bloc emits the deterministic fallback (§5.5) with `isFallback: true` and
no `error`. A generated sentence is a nicety; the count of things due today is the
actual information, and the app is offline-first by design.

### 5.5 Fallback and resting state

`BriefingFallback.compose(BriefingFacts)` — pure, in `lib/core/utils/`… no: pure and
domain-shaped, so it lives beside the prompt as
`lib/data/entity/briefing_fallback.dart`. It produces the mock's own line from
counts alone:

> `Good morning. You have 7 things planned today.`

This is the string the mock shows, which is the tell that the templated version is
sufficient. It is used when generation fails, when the engine is unconfigured, and as
the **first-frame content** — the card never renders empty, never renders a spinner.
When a generated line arrives it replaces the fallback through an `AnimatedSwitcher`
(200ms, `easeOut`), per §12.

### 5.6 The card

`lib/view/widgets/briefing_card.dart`. Gradient border (the mock runs magenta → violet
down the right edge) via a `Container` with a `GradientBoxBorder`-style outer and
`colors.surface` inner. The asterisk mark is the app's AI glyph — reuse whatever
`FloatingAiDock` renders so the orb and the card are visibly the same entity.

Tapping the card opens the AI sheet (`showAiSheet`), which is the only affordance
that makes a proactive surface answerable to a follow-up question.

Wiring: the Dashboard holds a `BlocListener`s-free `_Briefing` widget that reads
`TasksBloc`/`WeatherBloc`/`NewsBloc` via `BlocBuilder` (a *widget* reading another
module's bloc is this screen's whole job) and dispatches `BriefingFactsChanged` from
a `buildWhen`-narrowed builder callback — **not** from `build()`'s top level (§9).

---

## 6. Dashboard layout

`dashboard_page.dart` keeps its `ListView` + `RefreshIndicator` skeleton. `_refresh`
gains `RefreshBriefingEvent`.

New child order:

```dart
_Greeting(),          // glow behind, avatar button kept
Gap(14),
_DatePill() + _WeatherPill(),   // Row, both outlined
Gap(16),
_StaleBanner(),       // unchanged
_Briefing(),          // new
Gap(28),
_Agenda(),            // was _TodayTasks
Gap(16),
_MoneyAndUpcoming(),  // was _FinanceSummary
Gap(28),
_TopStories(),        // was _News
```

### 6.1 Greeting

The mock omits the avatar `IconButton` to Settings; **it stays anyway**, by decision.
It is the Dashboard tab's only route to `settingsRoute`, and Settings is where the
greeting's own name is set — which is what makes an unnamed greeting
self-explanatory rather than a defect. The mock is incomplete here, not opinionated.

It keeps its current `IconButton.filledTonal` treatment and `Settings` tooltip. The
glow (§4) sits behind it, so the button is composed over the gradient rather than
punching a hole in it.

### 6.2 Date and weather pills

Both become outlined pills (`colors.outlineVariant` border, transparent fill,
`labelLarge` mono) — the current filled amber `_Pill` is retired. Weather gains the
city name: `Bengaluru, 27° C`. `WeatherState.hasCity == false` keeps today's
`Set location` behaviour in the same outlined shape.

Date text is `15th July, Wednesday` — an ordinal day. `DateTimeX.dashboardDate` is
extended (or a sibling getter added) rather than formatting inline.

### 6.3 Today's Agenda

Centred `headlineMedium` title with a mono subline: `3 Overdue · 7 tasks today`,
overdue in `colors.error`, the rest in `onSurfaceVariant`. The `·` separator is
dropped when overdue is zero — `0 Overdue` in red is a lie about a clean day.

**`TasksState` needs `overdueCount`.** There is no such getter today, and overdue has
two live definitions: `dateGroups` uses per-day overdue (a 09:00 task stays under
Today), `TaskFilter.overdue` uses per-minute `Task.isOverdue`. The subline sits above
a list whose rows say `Overdue by 2 days`, so it must use the **per-day** definition
or the number will disagree with the rows under it. Add:

```dart
/// Tasks whose due date fell before today. Per-day, matching [dateGroups] —
/// the agenda count must not contradict the rows beneath it.
int get overdueCount;
```

`7 tasks today` is `todayTasks.length`, which already includes overdue (documented at
`tasks_state.dart:168`). So `3 Overdue · 7 tasks today` means *seven total, three of
them late* — not ten. This matches the mock's three visible rows summing into seven.

Preview count goes 4 → 3 (`_kTaskPreviewCount`), and `See All` becomes a full-width
outlined **`Show All ›`** button below the rows.

### 6.4 Task rows

`TaskCard` gains the mock's anatomy: title (`titleMedium`), a status line
(`Overdue by 2 days` in error / `Due Today` + `🕐 10:30AM` in accent / `Due in 2 days`
in `onSurfaceVariant`), a category chip with its colour dot, and the check ring on the
**right**, tinted by urgency rather than a flat outline.

`TaskCard` is shared with the Tasks module (§3 of the widget map), and the mock's row
is a strict improvement there too — so it is restyled in place, not forked. Requirement
3.5's point stands: a card that behaves differently on a different screen is a card
learnt twice.

### 6.5 Money and Upcoming

The 4-card scroller (`You spent` / `Income` / `Savings` / `Budget left`) collapses to
two fixed side-by-side panels:

**Remaining** — `₹3000 this month` (`headlineSmall`, mono numerals), a progress bar,
and `70% used · ₹15000 used`. All three come from the existing `BudgetStatus`
(`remainingMinor`, `spentMinor`, limit) — no new finance state. `status.isSet == false`
renders `Not set` and routes to `budgetsRoute`; the bar is absent, not empty.

**Upcoming** — `Meeting with team`, `in 10 mins`, red-outlined. This is **the next
task with a due time today**, not a calendar event (the app has no calendar). Needs a
`TasksState.nextUpcoming` getter: the earliest pending task whose `dueDate` is in the
future today. Null → the panel renders `Nothing scheduled` in `onSurfaceVariant`,
same footprint (§12: reserve layout space).

The relative countdown (`in 10 mins`) is a per-minute string. It rebuilds when
`TasksBloc` emits, which is not every minute — accepted: an "in 10 mins" that is
briefly "in 8 mins" is not worth a `Timer.periodic` on the Dashboard. Revisit only if
it reads wrong in practice.

Both panels tap through to their module (`financeRoute` / `tasksRoute`), preserving
Requirement 3.8.

### 6.6 Top Stories

Renamed from `News`. The horizontal `NewsCategory` tab strip is **removed** from the
Dashboard — the mock has a single `›` chevron in the header instead. Category
selection moves behind that chevron, to the News destination. `NewsBloc` is unchanged;
the Dashboard simply stops dispatching `SelectNewsCategoryEvent` and renders
`state.visibleArticles`.

Card anatomy inverts: today's card is image-on-top; the mock is **text left, 96×72
thumbnail right, `2h ago` beneath**. `_kNewsCount` 6 → 2 for the Dashboard preview.
The `errorBuilder`/`loadingBuilder` fallbacks survive verbatim — offline, every card
takes that path.

---

## 7. Score cards — the deferred seam

When scores land, they occupy a fixed-height `SizedBox` directly under the
`Top Stories` header and above the article rows, sourced from a new `ScoresBloc`
whose state is `List<Match>`. Absent or empty → the box is not built and the
articles move up. Nothing in §6.6 changes.

This is recorded so the section is not re-cut later. It is not built in this phase.

---

## 8. Floating pill navigation

The mock replaces four detached pills with **one floating pill** (~4 icons inside a
single rounded container, iOS 26-style) and moves the AI orb out as a separate red
circle above the pill's right edge.

`app_bottom_nav.dart` changes shape but not contract: `AppBottomNav(currentIndex,
onSelect)` and the `NavDestination` list stay, so `app_shell.dart` and the
`StatefulShellRoute` are untouched.

- One `Container`, radius ~28, `colors.surfaceContainerHigh` at high alpha, hairline
  `outlineVariant` border, horizontal margin ~20, height ~60.
- Selected tab = icon in `colors.primary`; unselected = `onSurfaceVariant`. The
  mock has no selected-pill fill and no labels — the `AnimatedScale(1.1)` on select
  survives as the only selection motion, plus an `AnimatedContainer` colour cross-fade
  (200ms, `easeOut`).
- Each icon keeps its `Semantics(label:)` — an icon-only control must be labelled (§9),
  and dropping the visible label makes that mandatory rather than nice.

**The progressive blur (`_ProgressiveBlur`, three stacked `BackdropFilter`s at
`_sigmas = [1, 3.5, 12]`) is deleted.** Its own doc comment flags it as the most
expensive steady-state render knob in the app; it exists to fade content into the
detached pills, and a single opaque pill does not need it. Content clears the pill via
the existing `bottom: 140` list padding. This is the one performance win in the change
set and it is free.

`FloatingAiDock` keeps its size (64px) and its `showAiSheet` job; its resting colour
moves from `surfaceContainerHigh` to `colors.primary` (red), icon to `onPrimary`,
subject to the §4 contrast check. `Scaffold.extendBody: true` and the FAB slot are
unchanged.

---

## 9. Files

**New**
```
lib/bloc/briefing/{briefing_bloc,briefing_event,briefing_state}.dart
lib/data/entity/briefing_facts.dart
lib/data/entity/briefing_fallback.dart
lib/view/widgets/briefing_card.dart
assets/fonts/Outfit.ttf
```

**Modified**
```
lib/core/utils/app_text_styles.dart   # PROTECTED — §2.1
lib/core/utils/theme.dart             # PROTECTED — default accent only
lib/core/utils/helpers.dart           # seasonOf()
lib/core/utils/extensions.dart        # ordinal dashboard date
lib/data/entity/ai_prompt.dart        # briefing prompt + system instruction
lib/bloc/theme/theme_state.dart       # default accent amber → red
lib/bloc/tasks/tasks_state.dart       # overdueCount, nextUpcoming
lib/app/app.dart                      # register BriefingBloc
lib/view/screens/dashboard/dashboard_page.dart
lib/view/widgets/task_card.dart
lib/view/widgets/app_bottom_nav.dart  # pill; delete _ProgressiveBlur
lib/view/widgets/floating_ai_dock.dart
pubspec.yaml                          # fonts
```

**Deleted**: `assets/fonts/NotoSerif.ttf`, `assets/fonts/Inter.ttf`.

No route changes — every destination in the mock already exists. `BriefingBloc`
registers after `TasksBloc`/`WeatherBloc`/`NewsBloc` (it takes no bloc dependencies,
but the Dashboard reads all four) and is not `lazy: false` — nothing needs it before
the Dashboard builds.

---

## 10. Build order

Each step ends in a state the app runs in.

1. **Fonts** — add Outfit, rewrite the family map, drop the serif. Verify: launch,
   every screen renders in Outfit + mono, `flutter analyze` clean.
2. **Colour** — glow, red default accent. Verify: accent switching in Settings still
   drives the glow; contrast check on the orb.
3. **Nav pill** — reshape, delete the blur. Verify: all four tabs switch, re-tap pops
   to root, nothing hides under the pill.
4. **Dashboard layout** — pills, agenda header, Show All, task rows, money/upcoming,
   Top Stories. Verify: counts agree with the rows; empty states hold their footprint.
5. **`TasksState` getters** — `overdueCount`, `nextUpcoming`. Verify: unit test per
   §11.
6. **Briefing** — entity, fallback, prompt, bloc, card. Verify: fallback renders
   offline with no error; generated text replaces it; cold launch shows yesterday's
   hydrated line, then today's.

Steps 1–4 are independent of 5–6 and can land first.

---

## 11. Testing

Per §17, the default is none. Two things here clear the bar, both pure and both
capable of being confidently wrong:

- **`AiPrompt.briefing`** — that the prompt contains no vault or finance content, that
  the task and headline caps hold, and that empty sources omit their heading rather
  than emitting `Tasks:` followed by nothing. This is the safety argument of §5.2, and
  it is only an argument if it is asserted.
- **`TasksState.overdueCount` / `nextUpcoming`** — boundary cases: a task due 09:00
  today is *not* overdue (per-day), a task due yesterday is; `nextUpcoming` ignores
  completed tasks and tasks with no time.
- **`Helpers.seasonOf`** — month boundaries. Cheap, and a wrong season is a visibly
  silly briefing.

`BriefingBloc`'s regeneration policy (§5.4) is worth a `bloc_test` if it proves
fiddly in practice; it is not written speculatively.

Restyled widgets get no tests. The goldens under `test/view/goldens/` will need
regenerating after step 1 — every one of them contains the old typeface.

---

## 12. Open questions

1. **Score cards** (§2.2) — deferred. Which providers, and is a live-polling section
   wanted in an offline-first app at all?
2. **Red as default accent** (§4) — the mock is red throughout, but accent is a user
   setting with six options. Confirm the default moves rather than the palette
   narrowing.

Settled: the font edit to protected files is sanctioned (§2.1), and the Settings
avatar stays on the Dashboard (§6.1).
