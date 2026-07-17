import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:everything_app/app/start.dart';
import 'package:everything_app/bloc/ai/ai_bloc.dart';
import 'package:everything_app/bloc/auth/auth_bloc.dart';
import 'package:everything_app/bloc/backup/backup_bloc.dart';
import 'package:everything_app/bloc/bookmarks/bookmarks_bloc.dart';
import 'package:everything_app/bloc/briefing/briefing_bloc.dart';
import 'package:everything_app/bloc/budget/budget_bloc.dart';
import 'package:everything_app/bloc/connectivity/connectivity_bloc.dart';
import 'package:everything_app/bloc/document/document_bloc.dart';
import 'package:everything_app/bloc/documents/documents_bloc.dart';
import 'package:dio/dio.dart';
import 'package:everything_app/bloc/finance/finance_bloc.dart';
import 'package:everything_app/bloc/home_widget/home_widget_bloc.dart';
import 'package:everything_app/bloc/news/news_bloc.dart';
import 'package:everything_app/bloc/projects/projects_bloc.dart';
import 'package:everything_app/bloc/search/search_bloc.dart';
import 'package:everything_app/bloc/settings/settings_bloc.dart';
import 'package:everything_app/bloc/share/share_bloc.dart';
import 'package:everything_app/bloc/speech/speech_bloc.dart';
import 'package:everything_app/bloc/storage/storage_bloc.dart';
import 'package:everything_app/bloc/task_form/task_form_bloc.dart';
import 'package:everything_app/bloc/tasks/tasks_bloc.dart';
import 'package:everything_app/bloc/theme/theme_bloc.dart';
import 'package:everything_app/bloc/to_buy/to_buy_bloc.dart';
import 'package:everything_app/bloc/transaction_form/transaction_form_bloc.dart';
import 'package:everything_app/bloc/vault/vault_bloc.dart';
import 'package:everything_app/bloc/watchlist/watchlist_bloc.dart';
import 'package:everything_app/bloc/weather/weather_bloc.dart';
import 'package:everything_app/core/route/app_router.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/database/daos/attachments_dao.dart';
import 'package:everything_app/data/database/daos/bookmarks_dao.dart';
import 'package:everything_app/data/database/daos/documents_dao.dart';
import 'package:everything_app/data/database/daos/finance_dao.dart';
import 'package:everything_app/data/database/daos/projects_dao.dart';
import 'package:everything_app/data/database/daos/search_dao.dart';
import 'package:everything_app/data/database/daos/tasks_dao.dart';
import 'package:everything_app/data/database/daos/to_buy_dao.dart';
import 'package:everything_app/data/database/daos/vault_dao.dart';
import 'package:everything_app/data/database/daos/watchlist_dao.dart';
import 'package:everything_app/data/repositories/ai_repository.dart';
import 'package:everything_app/data/repositories/app_info_repository.dart';
import 'package:everything_app/data/repositories/attachments_repository.dart';
import 'package:everything_app/data/repositories/backup_repository.dart';
import 'package:everything_app/data/repositories/bookmarks_repository.dart';
import 'package:everything_app/data/repositories/documents_repository.dart';
import 'package:everything_app/data/repositories/finance_repository.dart';
import 'package:everything_app/data/repositories/gemini_repository.dart';
import 'package:everything_app/data/repositories/home_widget_repository.dart';
import 'package:everything_app/data/repositories/model_backed_ai_repository.dart';
import 'package:everything_app/data/repositories/news_repository.dart';
import 'package:everything_app/data/repositories/notifications_repository.dart';
import 'package:everything_app/data/repositories/projects_repository.dart';
import 'package:everything_app/data/repositories/search_repository.dart';
import 'package:everything_app/data/repositories/share_repository.dart';
import 'package:everything_app/data/repositories/speech_repository.dart';
import 'package:everything_app/data/repositories/storage_repository.dart';
import 'package:everything_app/data/repositories/tasks_repository.dart';
import 'package:everything_app/data/repositories/to_buy_repository.dart';
import 'package:everything_app/data/repositories/vault_repository.dart';
import 'package:everything_app/data/repositories/watchlist_repository.dart';
import 'package:everything_app/data/repositories/weather_repository.dart';
import 'package:everything_app/data/services/ai_service.dart';
import 'package:everything_app/data/services/app_info_service.dart';
import 'package:everything_app/data/services/attachments_service.dart';
import 'package:everything_app/data/services/backup_service.dart';
import 'package:everything_app/data/services/bookmarks_service.dart';
import 'package:everything_app/data/services/documents_service.dart';
import 'package:everything_app/data/services/finance_service.dart';
import 'package:everything_app/data/services/gemini_service.dart';
import 'package:everything_app/data/services/home_widget_service.dart';
import 'package:everything_app/data/services/metadata_service.dart';
import 'package:everything_app/data/services/news_service.dart';
import 'package:everything_app/data/services/notification_service.dart';
import 'package:everything_app/data/services/projects_service.dart';
import 'package:everything_app/data/services/search_service.dart';
import 'package:everything_app/data/services/security_service.dart';
import 'package:everything_app/data/services/share_service.dart';
import 'package:everything_app/data/services/speech_service.dart';
import 'package:everything_app/data/services/storage_service.dart';
import 'package:everything_app/data/services/tasks_service.dart';
import 'package:everything_app/data/services/to_buy_service.dart';
import 'package:everything_app/data/services/vault_service.dart';
import 'package:everything_app/data/services/watchlist_service.dart';
import 'package:everything_app/data/services/weather_service.dart';
import 'package:everything_app/view/screens/home_widget/home_widget_listener.dart';
import 'package:everything_app/view/screens/share/share_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Root widget. Registration order in the [MultiBlocProvider] below matters: a
/// bloc must come before any bloc that depends on it (CLAUDE.md §9.2).
///
/// [bootstrap] carries the already-opened encrypted database and the shared
/// auth repository from `start.dart`.
class Application extends StatelessWidget {
  const Application({required this.bootstrap, super.key});

  final Bootstrap bootstrap;

  @override
  Widget build(BuildContext context) {
    // The database is a dependency, not state, so it is provided rather than
    // wrapped in a bloc. Every feature DAO takes it from here.
    //
    // NotificationsRepository must stay shared: it holds the plugin's
    // initialised state, so a second instance gets an uninitialised timezone db
    // and every reminder it schedules fails.
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: bootstrap.database),
        RepositoryProvider<TasksRepository>(
          create: (context) => TasksRepositoryImpl(
            tasksService: TasksService(
              dao: TasksDao(context.read<AppDatabase>()),
            ),
          ),
        ),
        RepositoryProvider<FinanceRepository>(
          create: (context) => FinanceRepositoryImpl(
            financeService: FinanceService(
              dao: FinanceDao(context.read<AppDatabase>()),
            ),
          ),
        ),
        RepositoryProvider<NotificationsRepository>(
          create: (context) => NotificationsRepositoryImpl(
            notificationService: NotificationService(
              plugin: FlutterLocalNotificationsPlugin(),
            ),
          ),
        ),
        // The five Library sub-features (Requirements 6–10). Each owns its own
        // DAO over the shared database, as Tasks and Finance do.
        RepositoryProvider<BookmarksRepository>(
          create: (context) => BookmarksRepositoryImpl(
            bookmarksService: BookmarksService(
              dao: BookmarksDao(context.read<AppDatabase>()),
              // Fresh Dio, never shared (CLAUDE.md §9.1): it fetches arbitrary
              // hosts, not one API. Its failure is non-fatal — a bookmark is
              // already saved from its URL before this is called.
              metadataService: MetadataService(dio: Dio()),
            ),
          ),
        ),
        RepositoryProvider<ToBuyRepository>(
          create: (context) => ToBuyRepositoryImpl(
            toBuyService: ToBuyService(
              dao: ToBuyDao(context.read<AppDatabase>()),
            ),
          ),
        ),
        RepositoryProvider<WatchlistRepository>(
          create: (context) => WatchlistRepositoryImpl(
            watchlistService: WatchlistService(
              dao: WatchlistDao(context.read<AppDatabase>()),
            ),
          ),
        ),
        RepositoryProvider<VaultRepository>(
          create: (context) => VaultRepositoryImpl(
            vaultService: VaultService(
              dao: VaultDao(context.read<AppDatabase>()),
              // A second SecurityService is safe: its only in-memory state is
              // the cached vault key, and this is the sole instance that asks
              // for it. PIN hash, attempt counter and lockout expiry all live in
              // secure storage, not in the object.
              //
              // Vault *authentication* deliberately does not go through here:
              // VaultBloc challenges via `bootstrap.authRepository` so a wrong
              // PIN at the vault advances the lock-screen lockout (Req 1.4).
              securityService: SecurityService(
                storage: const FlutterSecureStorage(
                  // Must match `start.dart`'s keychain accessibility tier, or
                  // the vault key lands under a different policy to the rest of
                  // the app's secrets.
                  iOptions: IOSOptions(
                    accessibility: KeychainAccessibility.first_unlock,
                  ),
                ),
                localAuth: LocalAuthentication(),
              ),
            ),
          ),
        ),
        RepositoryProvider<ProjectsRepository>(
          create: (context) => ProjectsRepositoryImpl(
            projectsService: ProjectsService(
              dao: ProjectsDao(context.read<AppDatabase>()),
            ),
          ),
        ),
        RepositoryProvider<DocumentsRepository>(
          create: (context) => DocumentsRepositoryImpl(
            documentsService: DocumentsService(
              dao: DocumentsDao(context.read<AppDatabase>()),
            ),
          ),
        ),
        // Backup, Restore & Export (Requirement 22). Reads every table through
        // the shared database directly rather than a DAO — a backup is the whole
        // database, not one module's slice. Backups are keyed by the user's
        // backup PIN and carry their own KDF salt, so they outlive the device,
        // unlike the SQLCipher key which is bound to it.
        RepositoryProvider<BackupRepository>(
          create: (context) {
            final security = SecurityService(
              storage: const FlutterSecureStorage(
                iOptions: IOSOptions(
                  accessibility: KeychainAccessibility.first_unlock,
                ),
              ),
              localAuth: LocalAuthentication(),
            );
            return BackupRepositoryImpl(
              backupService: BackupService(
                database: context.read<AppDatabase>(),
                security: security,
              ),
              securityService: security,
            );
          },
        ),
        // Global Search reads the FTS index maintained by triggers on every
        // module's table (Requirement 17). It owns no data of its own — one
        // read-only DAO over the shared database.
        RepositoryProvider<SearchRepository>(
          create: (context) => SearchRepositoryImpl(
            searchService: SearchService(
              dao: SearchDao(context.read<AppDatabase>()),
            ),
          ),
        ),
        // The assistant's generation engine. Cloud rather than on-device
        // because a 1B model at q4 wants ~1.5 GB resident and the target device
        // has ~1 GB free. A fresh Dio per service, never shared (CLAUDE.md §10).
        RepositoryProvider<GeminiRepository>(
          create: (context) =>
              GeminiRepositoryImpl(geminiService: GeminiService(dio: Dio())),
        ),
        // The AI assistant (Requirement 16). Owns no DAO: it reads categories,
        // the search index and documents through the feature repositories above,
        // hence provided after them.
        //
        // [ModelBackedAiRepository] decorates rather than replaces the
        // rule-based impl, overriding only the two prose methods where a model
        // helps — parsing stays on the fast, deterministic path.
        RepositoryProvider<AiRepository>(
          create: (context) => ModelBackedAiRepository(
            delegate: AiRepositoryImpl(
              aiService: AiService(
                tasksRepository: context.read<TasksRepository>(),
                searchRepository: context.read<SearchRepository>(),
                documentsRepository: context.read<DocumentsRepository>(),
              ),
            ),
            engine: context.read<GeminiRepository>(),
            documentsRepository: context.read<DocumentsRepository>(),
          ),
        ),
        // Content shared in from another app (Requirement 12). The share
        // repository owns no data — it is the plugin boundary.
        RepositoryProvider<ShareRepository>(
          create: (context) => ShareRepositoryImpl(
            shareService: ShareService(
              plugin: ReceiveSharingIntent.instance,
            ),
          ),
        ),
        RepositoryProvider<AttachmentsRepository>(
          create: (context) => AttachmentsRepositoryImpl(
            attachmentsService: AttachmentsService(
              dao: AttachmentsDao(context.read<AppDatabase>()),
            ),
          ),
        ),
        // The home screen widgets (Requirement 13). Owns no DAO: it publishes a
        // projection of other modules' data into a container the widget
        // processes can read.
        RepositoryProvider<HomeWidgetRepository>(
          create: (context) => HomeWidgetRepositoryImpl(
            homeWidgetService: HomeWidgetService(),
          ),
        ),
        // The Settings screen's Storage Usage and About sections
        // (Requirements 25.4, 25.1). Storage reads the shared database directly
        // rather than a DAO: it measures the whole file, not one module's slice.
        RepositoryProvider<StorageRepository>(
          create: (context) => StorageRepositoryImpl(
            storageService: StorageService(
              database: context.read<AppDatabase>(),
            ),
          ),
        ),
        RepositoryProvider<AppInfoRepository>(
          create: (context) =>
              AppInfoRepositoryImpl(appInfoService: AppInfoService()),
        ),
        // The app's only two networked services. A fresh Dio each, never shared
        // (CLAUDE.md §9.1): different hosts, timeouts and keys, and a shared
        // interceptor list would leak a weather header onto a news request.
        RepositoryProvider<WeatherRepository>(
          create: (context) =>
              WeatherRepositoryImpl(weatherService: WeatherService(dio: Dio())),
        ),
        RepositoryProvider<NewsRepository>(
          create: (context) =>
              NewsRepositoryImpl(newsService: NewsService(dio: Dio())),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ThemeBloc>(
            create: (context) => ThemeBloc(),
          ),
          BlocProvider<ConnectivityBloc>(
            create: (context) => ConnectivityBloc(connectivity: Connectivity()),
          ),
          BlocProvider<AuthBloc>(
            // The only bloc built and dispatched before the first frame: the
            // router's redirect reads it on the first build.
            lazy: false,
            create: (context) =>
                AuthBloc(repository: bootstrap.authRepository)
                  ..add(const CheckAuthEvent()),
          ),
          BlocProvider<TasksBloc>(
            create: (context) => TasksBloc(
              repository: context.read<TasksRepository>(),
              notificationsRepository: context.read<NotificationsRepository>(),
            ),
          ),
          BlocProvider<TaskFormBloc>(
            create: (context) =>
                TaskFormBloc(repository: context.read<TasksRepository>()),
          ),
          BlocProvider<BudgetBloc>(
            // Must be registered before FinanceBloc, which pushes the month's
            // spend here the moment its stream delivers.
            create: (context) => BudgetBloc(
              repository: context.read<FinanceRepository>(),
              notificationsRepository: context.read<NotificationsRepository>(),
            ),
          ),
          BlocProvider<FinanceBloc>(
            create: (context) => FinanceBloc(
              repository: context.read<FinanceRepository>(),
              budgetBloc: BlocProvider.of<BudgetBloc>(context),
            ),
          ),
          BlocProvider<TransactionFormBloc>(
            create: (context) => TransactionFormBloc(
              repository: context.read<FinanceRepository>(),
            ),
          ),
          BlocProvider<WeatherBloc>(
            create: (context) =>
                WeatherBloc(repository: context.read<WeatherRepository>()),
          ),
          BlocProvider<NewsBloc>(
            create: (context) =>
                NewsBloc(repository: context.read<NewsRepository>()),
          ),
          BlocProvider<BriefingBloc>(
            // Ordered after Tasks/Weather/News for readability only — the
            // Dashboard assembles their facts and pushes them here; this bloc
            // takes only the engine as a dependency.
            create: (context) =>
                BriefingBloc(engine: context.read<GeminiRepository>()),
          ),
          BlocProvider<BookmarksBloc>(
            create: (context) =>
                BookmarksBloc(repository: context.read<BookmarksRepository>()),
          ),
          BlocProvider<ToBuyBloc>(
            create: (context) => ToBuyBloc(
              repository: context.read<ToBuyRepository>(),
              notificationsRepository: context.read<NotificationsRepository>(),
            ),
          ),
          BlocProvider<WatchlistBloc>(
            create: (context) =>
                WatchlistBloc(repository: context.read<WatchlistRepository>()),
          ),
          BlocProvider<VaultBloc>(
            create: (context) => VaultBloc(
              repository: context.read<VaultRepository>(),
              // The app's own auth repository, so a wrong PIN at the vault door
              // advances the same lockout counter as one at the lock screen
              // (Requirement 1.4).
              authRepository: bootstrap.authRepository,
            ),
          ),
          BlocProvider<ProjectsBloc>(
            create: (context) =>
                ProjectsBloc(repository: context.read<ProjectsRepository>()),
          ),
          BlocProvider<DocumentsBloc>(
            create: (context) => DocumentsBloc(
              repository: context.read<DocumentsRepository>(),
            ),
          ),
          // Editor for the one open document. Kept apart from the list bloc
          // above because it holds a running auto-save timer and the live
          // unsaved buffer — a save failure here never touches the list.
          BlocProvider<DocumentBloc>(
            create: (context) => DocumentBloc(
              repository: context.read<DocumentsRepository>(),
            ),
          ),
          BlocProvider<SearchBloc>(
            // No startup event: it queries on demand and its only persisted
            // state — the recent searches — is rehydrated, not streamed.
            create: (context) =>
                SearchBloc(repository: context.read<SearchRepository>()),
          ),
          BlocProvider<AiBloc>(
            // Parses through AiRepository, creates through the feature
            // repositories — never persists on its own. No startup event: idle
            // until the assistant sheet is opened.
            create: (context) => AiBloc(
              repository: context.read<AiRepository>(),
              tasksRepository: context.read<TasksRepository>(),
              financeRepository: context.read<FinanceRepository>(),
              documentsRepository: context.read<DocumentsRepository>(),
              bookmarksRepository: context.read<BookmarksRepository>(),
              toBuyRepository: context.read<ToBuyRepository>(),
              watchlistRepository: context.read<WatchlistRepository>(),
              projectsRepository: context.read<ProjectsRepository>(),
            ),
          ),
          BlocProvider<SpeechBloc>(
            // Lazy with no startup event: `initialize` prompts for the
            // microphone, so it must not run until the mic is tapped.
            create: (context) => SpeechBloc(
              repository: SpeechRepositoryImpl(speechService: SpeechService()),
            ),
          ),
          BlocProvider<BackupBloc>(
            // No cross-bloc dependency: a backup is the whole database, read
            // straight through it, so nothing here waits on another bloc.
            create: (context) =>
                BackupBloc(repository: context.read<BackupRepository>()),
          ),
          BlocProvider<HomeWidgetBloc>(
            // Reads the same DAO streams the screens do, so every write
            // republishes the home screen with no push call at any call site.
            // Must precede SettingsBloc, which pushes the on/off switch at it.
            create: (context) => HomeWidgetBloc(
              repository: context.read<HomeWidgetRepository>(),
              tasksRepository: context.read<TasksRepository>(),
              financeRepository: context.read<FinanceRepository>(),
            ),
          ),
          BlocProvider<ShareBloc>(
            // Routes but never persists: a shared link is saved by
            // BookmarksRepository under the same validation as one typed into
            // the Library. Provided after the four repositories it composes.
            create: (context) => ShareBloc(
              repository: context.read<ShareRepository>(),
              bookmarksRepository: context.read<BookmarksRepository>(),
              tasksRepository: context.read<TasksRepository>(),
              documentsRepository: context.read<DocumentsRepository>(),
              attachmentsRepository: context.read<AttachmentsRepository>(),
            ),
          ),
          BlocProvider<StorageBloc>(
            // No startup event and no stream: measuring on every write costs a
            // dbstat scan and two directory walks, so it measures only when the
            // Storage section is opened.
            create: (context) =>
                StorageBloc(repository: context.read<StorageRepository>()),
          ),
          BlocProvider<SettingsBloc>(
            // Last: sole source of the notification configuration, and
            // TasksBloc, BudgetBloc and ToBuyBloc deliver nothing until they
            // have heard from here (CLAUDE.md §9.2).
            create: (context) => SettingsBloc(
              repository: context.read<NotificationsRepository>(),
              tasksBloc: BlocProvider.of<TasksBloc>(context),
              budgetBloc: BlocProvider.of<BudgetBloc>(context),
              toBuyBloc: BlocProvider.of<ToBuyBloc>(context),
              homeWidgetBloc: BlocProvider.of<HomeWidgetBloc>(context),
              aiBloc: BlocProvider.of<AiBloc>(context),
              appInfoRepository: context.read<AppInfoRepository>(),
            ),
          ),
        ],
        child: const _AppView(),
      ),
    );
  }
}

class _AppView extends StatefulWidget {
  const _AppView();

  @override
  State<_AppView> createState() => _AppViewState();
}

class _AppViewState extends State<_AppView> {
  late final GoRouter _router;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();

    final authBloc = context.read<AuthBloc>();
    _router = AppRouter.build(authBloc: authBloc);

    // Auto-lock (Requirement 1.5). The bloc records when the app was hidden and
    // re-locks on resume only if it stayed in the background past the auto-lock
    // duration.
    _lifecycle = AppLifecycleListener(
      onHide: authBloc.markBackgrounded,
      onPause: authBloc.markBackgrounded,
      onRestart: () => authBloc.add(const LockEvent()),
      onResume: () => authBloc.add(const LockEvent()),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _startModules());
  }

  /// Starts every bloc that is not the auth gate, split across three frames to
  /// avoid flooding drift's background isolate with concurrent queries.
  ///
  /// Order is load-bearing: BudgetBloc must listen before FinanceBloc pushes
  /// spend, and the Library streams and HomeWidget must be listening before
  /// SettingsBloc pushes notification config and the widget on/off switch.
  void _startModules() {
    if (!mounted) return;

    // ── Frame 1: dashboard-critical ────────────────────────────────────────
    context.read<ConnectivityBloc>().add(const WatchConnectivityEvent());
    context.read<TasksBloc>().add(const WatchTasksEvent());
    context.read<BudgetBloc>().add(const WatchBudgetsEvent());
    context.read<FinanceBloc>().add(const WatchFinanceEvent());

    // ── Frame 2: library, widgets, config ──────────────────────────────────
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Before SettingsBloc: ToBuyBloc must be listening before the
      // notification configuration is pushed at it.
      context.read<BookmarksBloc>().add(const WatchBookmarksEvent());
      context.read<ToBuyBloc>().add(const WatchToBuyEvent());
      context.read<WatchlistBloc>().add(const WatchWatchlistEvent());
      context.read<VaultBloc>().add(const WatchVaultEvent());
      context.read<ProjectsBloc>().add(const WatchProjectsEvent());
      context.read<DocumentsBloc>().add(const WatchDocumentsEvent());

      context.read<HomeWidgetBloc>().add(const WatchHomeWidgetEvent());

      // Settings pushes notification config to TasksBloc, BudgetBloc,
      // ToBuyBloc and HomeWidgetBloc — all listening by now.
      context.read<SettingsBloc>().add(const InitSettingsEvent());

      context.read<ShareBloc>().add(const WatchSharesEvent());

      // ── Frame 3: backup, network ────────────────────────────────────────
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        // Deferred: lists the backup files and may write one if an automatic
        // backup is overdue.
        context.read<BackupBloc>().add(const InitBackupEvent());

        // Last: network calls that update already-rendered cached data.
        context.read<WeatherBloc>().add(const FetchWeatherEvent());
        context.read<NewsBloc>().add(const FetchNewsEvent());
      });
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Read inside build so that a change to the device's light/dark setting
    // rebuilds the app under the "System" theme.
    final platformBrightness = MediaQuery.platformBrightnessOf(context);

    return BlocBuilder<ThemeBloc, ThemeState>(
      builder: (context, state) {
        return MaterialApp.router(
          title: 'Everything',
          debugShowCheckedModeBanner: false,
          theme: state.themeData(platformBrightness),
          routerConfig: _router,
          // The lock check is a keychain read; until it lands the app cannot
          // know whether the Dashboard is a legal destination. Withholding the
          // tree behind the surface colour keeps a locked app from flashing its
          // contents.
          //
          // ShareListener wraps the router rather than sitting on a screen: a
          // share arrives over whatever was last open, including the full-screen
          // routes pushed above the shell, which a listener inside the shell
          // could not reach.
          //
          // Both listeners sit *inside* the gate, not around it. A BlocListener
          // resolves its bloc with `context.read` in initState, so mounting them
          // above the gate force-constructed ShareBloc and HomeWidgetBloc — and
          // through them ~10 repositories, their services, DAOs and a Dio, plus
          // the share plugin's channel registration — on the one frame that
          // renders nothing but a ColoredBox. Every one of those providers is
          // `lazy: true` and reads as deferred; the laziness was being cancelled
          // from above. Nothing is lost by mounting a frame later: both
          // listeners already no-op while locked, and both blocs buffer the
          // pending action until they are.
          builder: (context, child) => BlocBuilder<AuthBloc, AuthState>(
            buildWhen: (previous, current) =>
                previous.isChecked != current.isChecked,
            builder: (context, auth) => auth.isChecked && child != null
                ? ShareListener(child: HomeWidgetListener(child: child))
                : ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: const SizedBox.expand(),
                  ),
          ),
        );
      },
    );
  }
}
