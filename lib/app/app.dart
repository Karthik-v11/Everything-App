import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:everything_app/app/start.dart';
import 'package:everything_app/bloc/ai/ai_bloc.dart';
import 'package:everything_app/bloc/auth/auth_bloc.dart';
import 'package:everything_app/bloc/backup/backup_bloc.dart';
import 'package:everything_app/bloc/bookmarks/bookmarks_bloc.dart';
import 'package:everything_app/bloc/budget/budget_bloc.dart';
import 'package:everything_app/bloc/connectivity/connectivity_bloc.dart';
import 'package:everything_app/bloc/document/document_bloc.dart';
import 'package:everything_app/bloc/documents/documents_bloc.dart';
import 'package:dio/dio.dart';
import 'package:everything_app/bloc/finance/finance_bloc.dart';
import 'package:everything_app/bloc/home_widget/home_widget_bloc.dart';
import 'package:everything_app/bloc/news/news_bloc.dart';
import 'package:everything_app/bloc/on_device_model/on_device_model_bloc.dart';
import 'package:everything_app/bloc/projects/projects_bloc.dart';
import 'package:everything_app/bloc/search/search_bloc.dart';
import 'package:everything_app/bloc/settings/settings_bloc.dart';
import 'package:everything_app/bloc/share/share_bloc.dart';
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
import 'package:everything_app/data/repositories/gemma_repository.dart';
import 'package:everything_app/data/repositories/home_widget_repository.dart';
import 'package:everything_app/data/repositories/model_backed_ai_repository.dart';
import 'package:everything_app/data/repositories/news_repository.dart';
import 'package:everything_app/data/repositories/notifications_repository.dart';
import 'package:everything_app/data/repositories/projects_repository.dart';
import 'package:everything_app/data/repositories/search_repository.dart';
import 'package:everything_app/data/repositories/share_repository.dart';
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
import 'package:everything_app/data/services/gemma_service.dart';
import 'package:everything_app/data/services/home_widget_service.dart';
import 'package:everything_app/data/services/metadata_service.dart';
import 'package:everything_app/data/services/news_service.dart';
import 'package:everything_app/data/services/notification_service.dart';
import 'package:everything_app/data/services/projects_service.dart';
import 'package:everything_app/data/services/search_service.dart';
import 'package:everything_app/data/services/security_service.dart';
import 'package:everything_app/data/services/share_service.dart';
import 'package:everything_app/data/services/storage_service.dart';
import 'package:everything_app/data/services/tasks_service.dart';
import 'package:everything_app/data/services/to_buy_service.dart';
import 'package:everything_app/data/services/vault_service.dart';
import 'package:everything_app/data/services/watchlist_service.dart';
import 'package:everything_app/data/services/weather_service.dart';
import 'package:everything_app/view/screens/home_widget/home_widget_listener.dart';
import 'package:everything_app/view/screens/share/share_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// [Application] is the root widget.
///
/// Every bloc is registered in the [MultiBlocProvider] below, the single
/// integration point for new features (CLAUDE.md §9.2). Registration order
/// matters: a bloc must come before any bloc that depends on it.
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
    // The two feature repositories are provided rather than constructed inside
    // each bloc that needs them. Four blocs used to build their own — three of
    // them a second and third FinanceDao over the same database — which is three
    // duplicate DAO graphs built while the first frame is waiting. One instance
    // each, created lazily on first read.
    //
    // The notification repository is provided for a harder reason: it holds the
    // plugin's initialised state and the device's exact-alarm capability. Two
    // blocs each building their own would give one of them an uninitialised
    // timezone database, and every reminder it scheduled would fail.
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
        // The five Library sub-features (Requirements 6–10). Each owns its own DAO
        // over the shared database, as Tasks and Finance do.
        RepositoryProvider<BookmarksRepository>(
          create: (context) => BookmarksRepositoryImpl(
            bookmarksService: BookmarksService(
              dao: BookmarksDao(context.read<AppDatabase>()),
              // A fresh Dio, never shared (CLAUDE.md §9.1). It answers to every host
              // on the internet rather than to one API, and it is the only service
              // in the app whose failure is uninteresting — a bookmark is saved from
              // its URL before this is ever called.
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
              // Its own SecurityService, not the one `start.dart` built. `Bootstrap`
              // does not expose that instance and `start.dart` is protected
              // (CLAUDE.md §0), so this is the available option — and it is a safe
              // one, because the only in-memory state a SecurityService holds is the
              // cached vault key, and this is the only instance in the app that ever
              // asks for it. Everything else the two would race over — the PIN hash,
              // the failed-attempt counter, the lockout expiry — lives in secure
              // storage rather than in either object.
              //
              // The vault's *authentication* deliberately does not come through
              // here: `VaultBloc` challenges through `bootstrap.authRepository`, so a
              // wrong PIN at the vault advances the same lockout as a wrong PIN at
              // the lock screen (Requirement 1.4).
              securityService: SecurityService(
                storage: const FlutterSecureStorage(
                  // Matches `start.dart`: the same keychain accessibility tier, or
                  // the vault key would be written under a policy the rest of the
                  // app's secrets are not stored under.
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
        // Backup, Restore & Export (Requirement 22). It reads and writes every
        // table through the shared database directly rather than a DAO — a backup
        // is the whole database, not one module's slice. Its own SecurityService,
        // for the same reason the vault's is its own: `start.dart` does not expose
        // the bootstrap instance, and the only in-memory state a SecurityService
        // holds is a cached key this is the sole caller of. The backup keys live
        // in secure storage, derived from a master that is independent of the
        // SQLCipher key so a backup outlives the install that wrote it.
        RepositoryProvider<BackupRepository>(
          create: (context) => BackupRepositoryImpl(
            backupService: BackupService(
              database: context.read<AppDatabase>(),
              security: SecurityService(
                storage: const FlutterSecureStorage(
                  iOptions: IOSOptions(
                    accessibility: KeychainAccessibility.first_unlock,
                  ),
                ),
                localAuth: LocalAuthentication(),
              ),
            ),
          ),
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
        // The on-device model's lifecycle (Phase 13). Provided before the
        // assistant because the assistant wraps it.
        //
        // The assistant no longer reads this — it reads [GeminiRepository]
        // below — but [OnDeviceModelBloc] and the settings screen still drive
        // the download UI from it.
        RepositoryProvider<GemmaRepository>(
          create: (context) => GemmaRepositoryImpl(gemmaService: GemmaService()),
        ),
        // The assistant's generation engine. Cloud rather than on-device
        // because a 1B model at q4 wants ~1.5 GB resident and the target device
        // has ~1 GB free: the weights downloaded but never loaded. A fresh Dio
        // per service, never shared (CLAUDE.md §10).
        RepositoryProvider<GeminiRepository>(
          create: (context) =>
              GeminiRepositoryImpl(geminiService: GeminiService(dio: Dio())),
        ),
        // The AI assistant (Requirement 16). It owns no data and no DAO: it reads
        // categories, the search index and documents through the feature
        // repositories above — which is why it is provided after them — and its
        // rule-based engine parses with the same pure code the sheets use.
        //
        // Phase 13 is this line, and it is a **wrap rather than a swap**. The
        // plan expected the rule-based implementation to be replaced outright;
        // building it showed that would trade a fast, deterministic parser for a
        // slow, unconstrained one, so [ModelBackedAiRepository] decorates it and
        // overrides only the two prose methods where a model actually helps.
        // Nothing above this line knows the difference — which was the point of
        // the interface, and is still what it bought.
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
        // repository owns no data — it is the plugin boundary — while attachments
        // are the first writer the polymorphic `attachments` table has ever had:
        // it has been counted and cascaded by ProjectsDao since Phase 2 and
        // written by nothing.
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
        // The home screen widgets (Requirement 13). It owns no DAO: it publishes
        // a projection of data other modules own into a container the widget
        // processes can read.
        RepositoryProvider<HomeWidgetRepository>(
          create: (context) => HomeWidgetRepositoryImpl(
            homeWidgetService: HomeWidgetService(),
          ),
        ),
        // The Settings screen's Storage Usage and About sections
        // (Requirements 25.4, 25.1). Storage reads every table through the
        // shared database directly rather than a DAO, as the backup does: it
        // measures the whole file, not one module's slice.
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
        // (CLAUDE.md §9.1): they answer to different hosts, different timeouts and
        // different keys, and one interceptor list between them is one place for a
        // weather header to end up on a news request.
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
            // The only bloc still built and dispatched before the first frame:
            // the router's redirect reads it on the first build, and the tree is
            // held back behind the surface colour until its check lands, so
            // everything else on screen is waiting on this one event.
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
            // Before FinanceBloc, which pushes the month's spending here the
            // moment its stream delivers. A budget that starts listening only
            // when the Finance tab is opened would miss it.
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
              // advances the same lockout counter as a wrong PIN at the lock screen
              // (Requirement 1.4). A vault with its own PIN check would have been a
              // second front door with no bolt on it.
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
          // The editor for the one open document. It holds a running auto-save
          // timer and the live, unsaved buffer, so it is kept apart from the list
          // bloc above — a save failure here never touches what the list renders.
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
            // repositories — it never persists on its own (see AiRepository). No
            // startup event: it does nothing until the assistant sheet is opened.
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
          BlocProvider<BackupBloc>(
            // No cross-bloc dependency: a backup is the whole database, read
            // straight through it, so nothing here waits on another bloc.
            create: (context) =>
                BackupBloc(repository: context.read<BackupRepository>()),
          ),
          BlocProvider<HomeWidgetBloc>(
            // Reads the same DAO streams the screens do, so every write in the
            // app republishes the home screen with no push call at any call site.
            // Before SettingsBloc, which pushes the on/off switch at it.
            create: (context) => HomeWidgetBloc(
              repository: context.read<HomeWidgetRepository>(),
              tasksRepository: context.read<TasksRepository>(),
              financeRepository: context.read<FinanceRepository>(),
            ),
          ),
          BlocProvider<OnDeviceModelBloc>(
            // Reads whether the weights are on disk at launch, and loads them
            // only if the user has switched the feature on. Before SettingsBloc,
            // which pushes that switch at it — and which is also what loads the
            // model on a restart, since this bloc starts with it off.
            //
            // `lazy: false`: without it the bloc is not constructed until a
            // widget reads it, and the only widget that does is the Settings
            // section — so the assistant would stay rule-based until someone
            // scrolled to the bottom of Settings, and then quietly become
            // model-backed.
            lazy: false,
            create: (context) => OnDeviceModelBloc(
              repository: context.read<GemmaRepository>(),
            )..add(const InitOnDeviceModelEvent()),
          ),
          BlocProvider<ShareBloc>(
            // Routes but never persists, exactly as AiBloc does: a shared link is
            // saved by BookmarksRepository under the same validation as one typed
            // into the Library, so it is provided after the four it composes.
            create: (context) => ShareBloc(
              repository: context.read<ShareRepository>(),
              bookmarksRepository: context.read<BookmarksRepository>(),
              tasksRepository: context.read<TasksRepository>(),
              documentsRepository: context.read<DocumentsRepository>(),
              attachmentsRepository: context.read<AttachmentsRepository>(),
            ),
          ),
          BlocProvider<StorageBloc>(
            // No startup event and no stream: it measures when the Storage
            // section is opened. Doing it on every write would cost a dbstat scan
            // and two directory walks to keep a number fresh that is only on
            // screen at the bottom of Settings.
            create: (context) =>
                StorageBloc(repository: context.read<StorageRepository>()),
          ),
          BlocProvider<SettingsBloc>(
            // Last: it is the only source of the notification configuration, and
            // none of TasksBloc, BudgetBloc or ToBuyBloc delivers anything until it
            // has heard from here (CLAUDE.md §9.2).
            create: (context) => SettingsBloc(
              repository: context.read<NotificationsRepository>(),
              tasksBloc: BlocProvider.of<TasksBloc>(context),
              budgetBloc: BlocProvider.of<BudgetBloc>(context),
              toBuyBloc: BlocProvider.of<ToBuyBloc>(context),
              homeWidgetBloc: BlocProvider.of<HomeWidgetBloc>(context),
              aiBloc: BlocProvider.of<AiBloc>(context),
              onDeviceModelBloc: BlocProvider.of<OnDeviceModelBloc>(context),
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

  /// [_startModules] builds and starts every bloc that is not the auth gate.
  ///
  /// These used to be `lazy: false` with their startup event dispatched from
  /// `create`, which put all of it — three Drift watch streams, two seed writes,
  /// the connectivity probe, the notification plugin and the ~440KB IANA timezone
  /// database it parses on this isolate — between `runApp` and the first frame.
  /// None of it is *readable* before the first frame: the tree is held back
  /// behind the surface colour until the auth check lands, so nothing on screen
  /// can render a task or a transaction until after this callback has run
  /// anyway.
  ///
  /// One post-frame callback later, the first frame is out and the same work
  /// starts, in the same order — which is the part that matters. Registration
  /// order alone is not enough: BudgetBloc has to be listening before FinanceBloc
  /// pushes the month's spend at it, and TasksBloc must not arm a schedule before
  /// SettingsBloc has said what the user actually wants. Reading them in this
  /// order is what preserves that, and each read is what constructs the bloc.
  void _startModules() {
    if (!mounted) return;

    context.read<ConnectivityBloc>().add(const WatchConnectivityEvent());
    context.read<TasksBloc>().add(const WatchTasksEvent());
    context.read<BudgetBloc>().add(const WatchBudgetsEvent());
    context.read<FinanceBloc>().add(const WatchFinanceEvent());

    // The Library's five, before SettingsBloc for the same reason TasksBloc is:
    // ToBuyBloc must be listening before the notification configuration is pushed
    // at it, or its first reminder sync would find no settings and do nothing.
    //
    // VaultBloc streams its rows from the start even though the vault is locked,
    // which is safe precisely because every payload on that stream is ciphertext —
    // and it is what makes the vault ready the instant the challenge is passed
    // rather than after a spinner the user waits through having just proved who
    // they are.
    context.read<BookmarksBloc>().add(const WatchBookmarksEvent());
    context.read<ToBuyBloc>().add(const WatchToBuyEvent());
    context.read<WatchlistBloc>().add(const WatchWatchlistEvent());
    context.read<VaultBloc>().add(const WatchVaultEvent());
    context.read<ProjectsBloc>().add(const WatchProjectsEvent());
    context.read<DocumentsBloc>().add(const WatchDocumentsEvent());

    // Before SettingsBloc, for the same reason TasksBloc and ToBuyBloc are: it
    // must be listening before the on/off switch is pushed at it, or it would
    // never be told and would publish nothing for the whole session.
    context.read<HomeWidgetBloc>().add(const WatchHomeWidgetEvent());

    context.read<SettingsBloc>().add(const InitSettingsEvent());

    // After the modules it files into are listening, so a share that *launched*
    // the app has somewhere to land. It is read here rather than lazily because
    // a cold launch from another app's share sheet is exactly the case where
    // nothing else would ever construct this bloc, and the pending share would
    // sit in the plugin unread.
    context.read<ShareBloc>().add(const WatchSharesEvent());

    // After the first frame: it lists the backup files and may write one if an
    // automatic backup is overdue, neither of which the first frame waits on.
    context.read<BackupBloc>().add(const InitBackupEvent());

    // Last, and behind the first frame for a second reason: these two are the
    // only startup work that touches the network. The Dashboard has already drawn
    // the weather and headlines it hydrated, so these fetches are an update to
    // something the user is already reading rather than something they are
    // waiting on — and on a device with no connection they are a no-op the screen
    // never notices.
    context.read<WeatherBloc>().add(const FetchWeatherEvent());
    context.read<NewsBloc>().add(const FetchNewsEvent());
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
          // The lock check is a keychain read, and until it lands the app cannot
          // know whether the Dashboard is a legal destination. Withholding the
          // tree behind the surface colour for those few milliseconds is what
          // keeps a locked app from flashing its contents. It replaces a splash
          // *route*, which bought the same guarantee at the price of a page
          // transition sliding across every launch.
          // ShareListener wraps the router rather than sitting on a screen: a
          // share arrives over whatever was last open, including the full-screen
          // routes pushed above the shell, which a listener inside the shell
          // could not reach.
          builder: (context, child) => ShareListener(
            child: HomeWidgetListener(
              child: BlocBuilder<AuthBloc, AuthState>(
                buildWhen: (previous, current) =>
                    previous.isChecked != current.isChecked,
                builder: (context, auth) => auth.isChecked && child != null
                    ? child
                    : ColoredBox(
                        color: Theme.of(context).colorScheme.surface,
                        child: const SizedBox.expand(),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
