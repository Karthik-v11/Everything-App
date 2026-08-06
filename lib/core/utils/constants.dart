import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Application-wide constants.
///
/// This app is offline-first: the only network calls are Weather and News, so
/// those are the only base URLs here. Everything else is served from the local
/// Drift database.
///
/// DO NOT MODIFY.

// ── Remote (the only two networked features) ─────────────────────────────────

/// [kWeatherURL] is the Weather_Service base URL.
String get kWeatherURL => dotenv.get(
      'WEATHER_URL',
      fallback: 'https://api.openweathermap.org/data/2.5',
    );

/// [kWeatherAPIKey] authenticates against the Weather_Service.
String get kWeatherAPIKey => dotenv.get('WEATHER_API_KEY', fallback: '');

/// [kNewsURL] is the News_Service base URL.
String get kNewsURL =>
    dotenv.get('NEWS_URL', fallback: 'https://newsapi.org/v2');

/// [kNewsAPIKey] authenticates against the News_Service.
String get kNewsAPIKey => dotenv.get('NEWS_API_KEY', fallback: '');

const String kCurrentWeatherPath = '/weather';
const String kForecastPath = '/forecast';
const String kTopHeadlinesPath = '/top-headlines';

/// The search endpoint. Reaches every publisher NewsAPI indexes rather than the
/// ~78 curated ids `/top-headlines` accepts as `sources`, which is the only way
/// to get live Indian coverage — see [NewsCategory].
const String kEverythingPath = '/everything';

// ── Storage keys ─────────────────────────────────────────────────────────────

/// [kDatabaseKey] is the secure-storage key holding the 256-bit SQLCipher key.
const String kDatabaseKey = 'db_encryption_key';

/// [kHydratedKey] is the secure-storage key holding the HydratedBloc cipher key.
const String kHydratedKey = 'hydrated_encryption_key';

/// [kPINHash] is the secure-storage key holding the salted PIN hash.
const String kPINHash = 'pin_hash';

// ── Database ─────────────────────────────────────────────────────────────────

const String kDatabaseName = 'everything.db';

// ── Timing (Requirements 11.2, 18.5, 24.x) ──────────────────────────────────

/// [kAutoSaveInterval] is how often the Document_Writer persists (Req 11.2).
const Duration kAutoSaveInterval = Duration(seconds: 30);

/// [kWidgetRefreshInterval] is the home-screen widget refresh cadence (Req 18.5).
const Duration kWidgetRefreshInterval = Duration(minutes: 30);

/// [kSearchDebounce] keeps Global_Search inside its 300 ms budget (Req 24.2).
const Duration kSearchDebounce = Duration(milliseconds: 200);

/// [kPINLockoutDuration] is the lockout after 3 failed attempts (Req 1.4).
const Duration kPINLockoutDuration = Duration(seconds: 30);

/// [kMaxPINAttempts] is the number of failures that triggers the lockout.
const int kMaxPINAttempts = 3;

/// [kAutoLockDuration] is how long the app may sit in the background before it
/// re-locks (Requirement 1.5). This is the default; Settings makes it
/// user-configurable in a later phase.
const Duration kAutoLockDuration = Duration(minutes: 1);

/// [kMaxDocumentRevisions] is the version-history cap (Req 11.3).
const int kMaxDocumentRevisions = 10;

/// [kStaleCacheThreshold] is how old cached weather/news may be before the UI
/// tells the user it is stale.
const Duration kStaleCacheThreshold = Duration(hours: 1);
