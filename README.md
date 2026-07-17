# Everything App

A single, offline-first Flutter app for the things that usually need four apps: your day, your tasks, your personal library, and your money. Everything lives in one encrypted local database on the device — there is no account to make and no server holding your data.

## Modules

The app is four bottom-nav modules, plus search and settings.

**Dashboard** — today at a glance: current weather (with a detail screen and a city picker), the tasks due today, and news headlines. Headlines open in the device browser rather than an in-app webview, because the article belongs to its publisher.

**Tasks** — tasks on a calendar strip with a by-date list, recurring items, and local notifications for deadlines plus a daily summary at a time you choose.

**Library** — five things that share a home:
- *Bookmarks* — saved links with fetched metadata
- *To Buy* — a shopping/wishlist
- *Watchlist* — a tracker for what you're watching or following
- *Vault* — passwords and documents, encrypted per item on top of the encrypted database
- *Projects* — nestable projects, each holding documents written in the built-in Markdown editor with live preview and export to Markdown, text, or PDF

**Finance** — income, expenses, and transfers across accounts, with budgets and alerts, category breakdowns, and charts.

## Other features

- **Assistant** — add a task or a transaction by typing a sentence. Parsing is rule-based, so it is instant, deterministic, and works offline. Prose paths (summarize a document, answer a grounded question) are backed by the Gemini API. Without `GEMINI_API_KEY` configured, the assistant still runs its rule-based engine.
- **Global search** across every module
- **Home screen widgets** (Android `AppWidgetProvider` / iOS WidgetKit)
- **Share into the app** from any other app, cold-start or already-running
- **App lock** — PIN or biometric
- **Backup and restore** — encrypted backup handed to the OS share sheet, so it reaches your cloud storage app without this app needing OAuth
- **Themes** — accent color, light/dark, font size
- **Offline support** throughout; the network is only ever for weather, news, and the optional Gemini path

## Architecture

BLoC + Drift + Dio + GoRouter, layered service → repository → bloc → view. See [CLAUDE.md](CLAUDE.md) for the conventions this codebase holds itself to, and [docs/requirements.md](docs/requirements.md) / [docs/design.md](docs/design.md) for the full specification.

Storage is SQLite compiled as **SQLCipher**, giving AES-256 encryption at rest. The vault adds AES-256-GCM per item on top. Tokens and credentials live in `flutter_secure_storage`, never in `HydratedBloc.storage`.

## Getting started

```bash
flutter pub get
cp .env.example .env      # fill in the keys you want
flutter run
```

Every key in `.env` is optional and degrades gracefully — a missing key costs you that one feature, not the app:

| Key | Enables | Where to get it |
| --- | --- | --- |
| `WEATHER_API_KEY` | Dashboard weather | [openweathermap.org](https://openweathermap.org/api) |
| `NEWS_API_KEY` | Dashboard headlines | [newsapi.org](https://newsapi.org) |
| `GEMINI_API_KEY` | Assistant prose paths | [aistudio.google.com](https://aistudio.google.com/apikey) |

Requires Flutter SDK ^3.12.2.

## Development

```bash
flutter analyze
flutter test
dart run build_runner build --delete-conflicting-outputs   # after changing Drift tables/DAOs
```
