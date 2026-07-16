import 'dart:async';

import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/repositories/auth_repository.dart';
import 'package:everything_app/data/services/security_service.dart';
import 'package:everything_app/debug/app_bloc_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';

/// [Bootstrap] is everything that must exist before the first frame and is then
/// injected into the widget tree.
///
/// [database] is the SQLCipher-keyed database. [authRepository] is shared with
/// [AuthBloc] so that the key used to open the database and the gate in front of
/// the UI come from the same [SecurityService] instance.
class Bootstrap {
  const Bootstrap({required this.database, required this.authRepository});

  final AppDatabase database;
  final AuthRepository authRepository;
}

/// [startApplication] boots the app and then runs [builder].
///
/// Everything here sits between process start and the first frame, so the only
/// work allowed is work the first frame genuinely cannot be built without:
///
/// 1) [dotenv] — read by [constants] getters that a screen may touch on build.
/// 2) [HydratedBloc.storage] — every [HydratedBloc] reads it in its constructor,
///    and [ThemeBloc] is constructed while building the first frame.
/// 3) The database encryption key — the database cannot be constructed without
///    it, and the tree cannot be constructed without the database.
///
/// The three are independent, so they run **concurrently** rather than in the
/// sequence they used to: the bootstrap now costs the slowest of them instead of
/// the sum. The directories are resolved here as well, once, and handed to
/// [AppDatabase.encrypted] — otherwise `drift_flutter` resolves them again on
/// the first query, which is two more platform round-trips on the path to the
/// first row of data.
///
/// What is *not* here: opening the database. [AppDatabase.encrypted] only
/// describes the connection; sqlite3 is opened, keyed and verified lazily on the
/// first query, in drift's background isolate. Nothing about the security
/// verification changes — it simply no longer happens on the UI isolate ahead of
/// the first frame.
Future<void> startApplication(Widget Function(Bootstrap) builder) async {
  WidgetsFlutterBinding.ensureInitialized();

  final securityService = SecurityService(
    storage: const FlutterSecureStorage(
      // first_unlock rather than the default: background work (widget refresh,
      // scheduled notifications) needs the key after a reboot without the user
      // having opened the app, and the stricter `passcode` tiers would deny it.
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    ),
    localAuth: LocalAuthentication(),
  );

  final documentsFuture = getApplicationDocumentsDirectory();

  final (_, _, storage, documents, temporary, keyResponse) = await (
    _loadEnvironment(),
    _registerInferenceEngines(),
    documentsFuture.then(
      (directory) => HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory(directory.path),
      ),
    ),
    documentsFuture,
    getTemporaryDirectory(),
    securityService.databaseKey(),
  ).wait;

  HydratedBloc.storage = storage;
  Bloc.observer = const AppBlocObserver();

  if (!keyResponse.success) {
    // Continuing here would mean opening an unencrypted database, or none at
    // all. Both are worse than refusing to start.
    throw StateError(
      'Could not obtain the database encryption key: ${keyResponse.message}',
    );
  }

  final database = AppDatabase.encrypted(
    encryptionKey: keyResponse.data! as String,
    databaseDirectory: documents.path,
    temporaryDirectory: temporary.path,
  );

  // Not awaited: the platform applies the orientation lock to the window, and
  // nothing Dart-side reads the result. Awaiting it only held the first frame
  // back for a round-trip whose answer we discard.
  unawaited(
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  runApp(
    builder(
      Bootstrap(
        database: database,
        authRepository: AuthRepositoryImpl(securityService: securityService),
      ),
    ),
  );
}

/// [_registerInferenceEngines] tells `flutter_gemma` which inference engine it
/// may use (Phase 13).
///
/// It **registers, it does not load**: no weights are read and no memory is
/// claimed here, so it costs a function call rather than the seconds and
/// hundreds of MB that loading a model costs. That happens later, only if the
/// user has switched the feature on and only once [OnDeviceModelBloc] asks —
/// which is why this belongs in the concurrent block rather than being the one
/// thing that delays the first frame.
///
/// It is here at all because `flutter_gemma` registers **no** engine by default
/// and resolves them at the first model call, so a missing registration surfaces
/// as a `StateError` deep inside the first download rather than at startup.
///
/// A failure is not fatal, in keeping with the rest of this file's optional
/// work: no engine means the assistant is the rule-based engine, which is the
/// app's shipped behaviour, not a fault.
Future<void> _registerInferenceEngines() async {
  try {
    await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
  } on Exception {
    // Deliberately swallowed and not reported: there is no user-facing failure
    // here. The assistant works without a model, and a crash SDK entry for
    // "the optional LLM engine did not register" on every launch of a device
    // that will never download one is noise, not a signal.
  }
}

/// A missing .env must not be fatal: the app is offline-first and every module
/// except Weather and News works without any key at all.
Future<void> _loadEnvironment() async {
  try {
    await dotenv.load();
  } on Exception {
    dotenv.loadFromString(envString: '');
  }
}
