# CLAUDE.md — Flutter Architecture Guide

BLoC + Firebase + Dio + GoRouter. Priority: scalability > readability > maintainability > performance > consistency. Domain-agnostic.

## 0. Ground Rules

**Never modify without explicit instruction:** `core/interceptors/`, `core/utils/`, `core/exceptions/`, `core/environments/`, `debug/`, `firebase_options.dart`, `app/start.dart`. Looks wrong? Flag, don't fix.

**Every new feature touches:** `core/route/routes.dart` (constant) + `core/route/app_router.dart` (GoRoute) + `app/app.dart` (BlocProvider).

**Auth interceptor** (protected, don't touch): confirm its actual 401 behavior (refresh-and-retry vs fail-through) before assuming it — never reimplement refresh elsewhere.

**Agent behavior:** state assumptions; ask only if genuinely ambiguous. Minimum code for the ask — no speculative features/config/error-handling. Touch only what's needed — no drive-by refactors/reformatting; match existing style; remove only imports/vars your change orphaned, leave pre-existing dead code (mention, don't delete). Multi-step tasks get a one-line plan with a verify step per item. Be terse — no restating rules, no narrating obvious edits, no unrequested code samples, read only what's needed, prefer targeted edits over rewrites. Never empty `catch` — emit failure state and report via crash SDK (§18). Never `print()`.

## 1. New Feature Checklist
Model → Params (if request body) → Service → Repository → BLoC (3 files) → register in `app.dart` → Screen → Route (both files).

## 2. Structure
```
lib/
├── app/{app.dart(BlocProviders), start.dart(DO NOT MODIFY)}
├── bloc/<feature>/{_bloc,_event,_state}.dart   # part/part of
├── core/
│   ├── environments/ exceptions/ interceptors/ utils/   # DO NOT MODIFY
│   └── route/{routes.dart, app_router.dart}              # MUST modify per feature
├── data/
│   ├── entity/<name>_params.dart      # mutable, no Equatable, outbound-only
│   ├── models/<name>.dart             # immutable, Equatable
│   ├── models/json_response.dart      # DO NOT MODIFY
│   ├── repositories/<name>_repository.dart   # abstract + Impl
│   └── services/<name>_service.dart          # Dio calls
├── view/{screens/<feature>/, widgets/}
├── debug/                             # DO NOT MODIFY
└── main.dart
```

## 3. Naming
`snake_case` files · `<Feature>Bloc/Event/State` · `<Feature>Repository`+`Impl` · `<Feature>Service` · Model = PascalCase singular (`User`) · `<Feature>Params` · `<Feature>Page/Screen` · consts `k`+camelCase (`kURL`) · routes: camelCase+`Route` const, kebab-case value · handlers `_on<Feature>Event`.

## 4. BLoC

**4.1** 3 files per feature, strict `part`/`part of`. Never standalone.

**4.2 State — pick one:**
- **Style A** (single class, `isLoading/error/message`+`copyWith()`): persists/accumulates data across events, uses `HydratedBloc`, or multiple events update different slices.
- **Style B** (sealed/abstract base: `Initial/Loading/Success/Failure`): one focused async action, no accumulated data, state is always exactly one thing.
- B outgrows itself → migrate to A, don't bolt on fields. Prefer Dart 3 `sealed class`+exhaustive `switch` for B.
- A: `copyWith()` replaces given fields only; every async handler's first emit is `state.copyWith(isLoading:true,error:'',message:'')` pre-`await`. Hydrated → add `fromJson`/`toJson`, persist minimal fields prefixed `Hydrated`. Never persist secrets via `HydratedBloc.storage` (→ §4.5).
- B: base has `const` ctor + empty `props`. `Loading` = no data. `Failure` always `required String message`. Override `props` only where data exists.
- Both: loading emit always first; `try/catch` (catch = unexpected only, Dio errors already normalized to `JsonResponse.failure`); repo/dependent-blocs injected via ctor, `final`, declared after ctor; handlers `FutureOr<void> _on<Feature>Event`, private.

**4.3 Events:** `Equatable`, `final` `required` named fields, `props` = all fields (empty if none). No-arg events can be `const`.

**4.4 Inter-bloc:** only `otherBloc.add(Event())` — never read another bloc's state directly. Inject as `final` ctor param.

**4.5 Storage:** `hydrated_bloc` = non-sensitive persisted state only · `flutter_secure_storage` = tokens/credentials/IDs (never `HydratedBloc.storage`, even in a hydrated bloc) · `hive`/`isar` = larger local caches. Init pre-`runApp()`. Access only via services/repos, never UI. Cache failure ≠ crash.

**4.6 Env config:** check `pubspec.yaml` for `flutter_dotenv`. Present → `.env` + `dotenv.get('KEY', fallback:'')` (never bracket access), gitignored, `.env.example` provided, listed under `pubspec.yaml` assets. Absent → `core/environments/environment.dart` (DO NOT MODIFY). Neither yet → default to `flutter_dotenv`. dev/staging/prod = separate env files or build flavors, never runtime string-branching.

## 5. Repository
Abstract (`///`-documented) + `Impl` same file. `Impl`: `const` ctor, arrow-syntax delegation only, zero business logic. Signatures match exactly (incl. named/optional params). Returns `Future<JsonResponse<T>>`.

## 6. Service (Dio)
Dio via ctor injection — never instantiate inline, never share instances across services. Ctor body sets `baseUrl`, 10s send/receive/connect timeouts, `responseType: json`, `Content-Type`/`Accept: application/json`. Always `XClientInterceptor()`; `AuthInterceptor()` only if authenticated. Returns `Future<JsonResponse<T>>` only — never raw `Response`/bare model. 3-layer handling: success (`statusCode==200`) → `on DioException` (`DioExceptionOf.exceptionFromDioError`) → `on Exception` fallback. Parse models only in success branch; null-safe fallback on all `response.data['message']`.

## 7. Models (`data/models/`)
`Equatable`, `final` fields, `const` ctor + `fromJson` + `toJson()` + `copyWith()` + `props` (all fields). `?.toString()`/`DateTime.tryParse`/`num.tryParse` — never direct casts. Lists: `(json['x'] as List?)?.map(Item.fromJson).toList() ?? []`.
`JsonResponse<T>` (DO NOT MODIFY) — declare return types explicitly (`Future<JsonResponse<User>>`) to avoid `as` casts.

## 8. Params/Entity (`data/entity/`)
Mutable, non-final fields, **not** `Equatable`, outbound-only. `toJson()`+`copyWith()`, no `fromJson()`.

## 9. UI
`BlocConsumer` default for API screens (listener=side-effects, builder=UI) · `BlocBuilder` = UI-only · `BlocListener` = side-effects-only. Always handle `Loading` in builder, `Failure` in listener (`SnackBar`+`colorScheme.error`, never `AlertDialog` for transient errors). Dispatch via `context.read<Bloc>().add()` inside callbacks only — never `context.read/BlocProvider.of` at top level of `build()`. Theme via `Theme.of(context).colorScheme/textTheme` only, never hardcoded `Colors.*`/inline `TextStyle`. Responsive via `MediaQuery`/`responsive.dart`. `Semantics` label on icon-only/custom controls.

## 10. Bootstrap
Fresh `Dio()` per service inside its `BlocProvider.create` — never shared/global. Dependent blocs: `BlocProvider.of<Other>(context)` inside `create`; register dependencies before dependents. `lazy:false` only for must-init-immediately blocs. Init dispatch via `..add(const InitEvent())`.

## 11. Routing (GoRouter)
New screen = `routes.dart` const (camelCase name, kebab-case value) + matching `app_router.dart` `GoRoute`. Top-level paths start `/`, nested paths don't. Named navigation only — never `Navigator.push`/raw paths/`MaterialPageRoute`:
```dart
context.pushNamed(verifyOTPRoute, queryParameters: {'phone': phone});
context.pushReplacementNamed(homeRoute);
context.goNamed(homeRoute);
context.pop(result);
```
`redirect` guards live in `app_router.dart`. `ShellRoute` for bottom-nav/drawer. Imports alphabetized.

## 12. Animation
Budget, not decoration — never delay next user action. Durations: state-change 150–200ms `easeOut` · layout change 200–260ms `easeOutCubic` · programmatic scroll 300–350ms `easeOutCubic` · page transition = theme default. Nothing >350ms. No staggered list-entrance animation.
Rules: prefer implicit widgets (`AnimatedContainer/Opacity/Scale/Size/Switcher`, `TweenAnimationBuilder`); `AnimationController` only for gesture-driven/interruptible, always `dispose()`. Animate leaves not the trunk. Never index/delay-based animation in `itemBuilder`. Local-write feedback (toggle/complete) is immediate; animation overlays already-applied state. Reserve layout space for in/out elements. `IgnorePointer` on invisible widgets. Respect `MediaQuery.disableAnimationsOf(context)`.

## 13. Equatable
Models: always, `props`=all fields · States: always, `props` only where data carried · Events: always, `props`=all params · Params/Entity: never. `List<Object?>` if any field nullable, else `List<Object>`.

## 14. Packages
`flutter_bloc` · `hydrated_bloc`(non-sensitive persisted state) · `equatable` · `dio`(service-layer only) · `go_router`(named routes only) · `google_fonts`(AppTheme) · `path_provider`(start.dart only) · `connectivity_plus`(ConnectivityBloc only) · `device_info_plus`(service layer only) · `rxdart`(advanced streams only) · `shimmer` · `lottie`/`flutter_svg` · `animations`(page/hero transitions) · `flutter_secure_storage`(tokens/credentials). Need something else? Check `pubspec.yaml` first, reuse over adding a competing dep.

## 15. Forbidden
`setState` for BLoC-managed logic (local-only UI state OK) · top-level `context.read/BlocProvider.of` in `build()` · hardcoded `Colors.*` · business logic in repo `Impl` · HTTP direct from bloc (must be service→repo→bloc) · shared `Dio` instance · uncaught exceptions escaping repo/bloc · `Navigator.push()` · editing protected paths (§0) · Firebase imports outside `start.dart`/`firebase_options.dart`/services that need them · non-Style-A/B bloc state · empty `catch` · secrets in `HydratedBloc.storage` · `dynamic` where type is known (json params excepted) · `var` where RHS type isn't obvious.

## 16. Comments
What + why (business rule/constraint/API quirk), not AI reasoning or generation process. ≤1 line where possible. No obvious-code comments. Keep in sync, delete stale. No conversational tone.

## 17. Testing
**Default: none.** Write tests only for: bug fixes (repro test → fix) · explicitly high-risk/high-criticality logic (payments, auth, destructive writes, consequential calculations) · explicit developer ask. When warranted: `bloc_test`+`mocktail`, focused unit/widget, deterministic, isolated, no broad integration tests unless asked. Skip trivial UI/generated code/getters-setters even when criteria met.

## 18. Crash & Error Reporting
Never `print()`/swallow exceptions. If a crash SDK exists (check `pubspec.yaml`/`start.dart` — Crashlytics, Sentry), route caught exceptions through it, not just into a failure state. None present → flag, don't add one unprompted (needs external project setup).

## 19. Lint/Static Analysis
Check `analysis_options.yaml` for active ruleset before writing style-sensitive code (trailing commas, `prefer_const_constructors`, import style). Don't introduce a pattern that fails `flutter analyze` under existing rules. None configured → ask.

## 20. Build Flavors / Multi-Env
`.env` = runtime values (API URLs). Flavors (`android/app/build.gradle`, iOS schemes) = build-time identity (package name, Firebase config, icon/label) — different problem, can't be faked via `.env`. Check before assuming `.env` covers environment separation; flag if the task needs flavors that aren't set up.

## 21. Debugging/Execution
Diagnose from code/logs/stack traces/repro steps — never screenshots or live UI interaction, unless a visual bug is undiagnosable otherwise (ask first). Ask developer for logs/exceptions/widget tree, not "check how it looks." Run app only to verify build/runtime behavior. Verify with `flutter analyze`; `flutter test` only if tests exist (§17).