# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.
``

## Project Overview

Cyrene Music is a cross‑platform Flutter music player (Windows, Android, Linux, macOS, iOS) with a Bun/Elysia backend that aggregates multiple music platforms (NetEase, QQ, KuGou, Spotify, Bilibili, Douyin, etc.) and provides user accounts, favorites, playlists, listening stats, and playback state sync.

The repo is organized roughly as:
- Flutter app: `lib/`, `android/`, `ios/`, platform build configs and assets.
- Aggregation backend: `backend/` (Bun + Elysia, SQLite persistence, Swagger docs, optional simple web UI in `backend/webui/`).
- Vendored KuGou API: `kugouapi_github/` (standalone NodeJS KuGou API, not required for normal app development).

---

## Commands

### Flutter app (main client)

From the repository root:

- Install dependencies:
  ```bash
  flutter pub get
  ```

- Run the app (auto‑selects a connected device or desktop target):
  ```bash
  flutter run
  ```

- Run on a specific platform (examples):
  ```bash
  flutter run -d windows
  flutter run -d android
  flutter run -d macos
  flutter run -d linux
  ```

- Build release artifacts (common targets):
  ```bash
  # Windows
  flutter build windows --release

  # Linux
  flutter build linux --release

  # macOS
  flutter build macos --release

  # Android APK (split per ABI)
  flutter build apk --release --split-per-abi

  # iOS (requires macOS)
  flutter build ios --release
  ```

- Run all Flutter tests:
  ```bash
  flutter test
  ```

- Run a single Dart test file (example):
  ```bash
  flutter test test/example_test.dart
  ```

> The Flutter project follows standard `flutter_lints` via `analysis_options.yaml`; use `flutter analyze` if you need static analysis.

### Aggregation backend (`backend/`)

The backend is a Bun + Elysia service exposing all music / auth / stats APIs on port `4055`.

From the repository root:

- Install dependencies:
  ```bash
  cd backend
  bun install
  ```

- Start the API server in watch mode (recommended for development):
  ```bash
  bun run dev
  ```

  This runs `src/index.ts` under Bun, mounts all route modules, and listens on:
  - `http://0.0.0.0:4055` (Swagger UI at `/swagger` by default via `@elysiajs/swagger`).

- Alternative one‑off run (no watch):
  ```bash
  bun run src/index.ts
  ```

- Start only the Bilibili media proxy (if you need a separate proxy process):
  ```bash
  bun run proxy
  ```

Notes:
- There is no automated test suite wired into `backend/package.json` yet; `npm test`/`bun test` are not configured.
- Persistent data (users, third‑party account bindings, sponsorships, playback state, etc.) are stored as SQLite databases under `backend/data/`.
- High‑quality media for some platforms requires valid cookie files under `backend/cookie/` (see `backend/README.md` and `src/lib/cookieManager.ts` for the expected files and formats).

### KuGou API subproject (`kugouapi_github/`)

This is a standalone KuGou API implementation, vendored from an external project. It is not required for running the Flutter app with the main backend, but can be useful for debugging KuGou behavior.

From the repository root:

- Install and run in development:
  ```bash
  cd kugouapi_github
  npm install
  npm run dev
  ```

Environment variables such as `PORT`, `HOST`, and `KUGOU_API_PROXY` can be set (see `kugouapi_github/README.md`) to customize port, host, and outbound proxy behavior.

---

## High‑Level Architecture

### 1. Flutter application (client)

- The Flutter client lives under `lib/` with platform‑specific wrappers in `android/` and `ios/`.
- `pubspec.yaml` declares a desktop‑ and mobile‑oriented dependency set: audio playback (`audioplayers`, `audio_service`, `media_kit`), window/system tray and acrylic effects on desktop (`bitsdojo_window`, `tray_manager`, `window_manager`, `flutter_acrylic`), networking (`http`, `shelf`), caching (`cached_network_image`), permissions, display mode, notifications, etc.
- Lints and analysis are configured via `analysis_options.yaml` with `flutter_lints`.

#### URL and backend integration (`lib/services`)

- `UrlService` (documented in `lib/services/README.md`) is the central abstraction for backend URLs:
  - Exposes a `baseUrl` and strongly‑typed per‑endpoint URLs (e.g. `searchUrl`, `songUrl`, `biliPlayurlUrl`, `qqSearchUrl`, `kugouSearchUrl`, `douyinUrl`, `versionLatestUrl`, etc.).
  - Supports switching between an **official source** and a **custom source** that must implement the same OmniParse‑style API surface.
  - Normalizes and validates URLs (trims trailing slashes, checks format) and notifies listeners when the base URL changes.
- UI components typically depend on `UrlService` rather than hard‑coding paths, so changing the backend host or swapping in a compatible third‑party backend does not require code changes.
- The settings UI (as described in `lib/services/README.md`) exposes a **Settings → Network → Backend Source** screen where users can:
  - Choose between official and custom sources.
  - Input and validate a custom backend URL.
  - Run a connection test before saving.

#### Data models (`lib/models`)

- `lib/models/README.md` document key models such as:
  - `Track`: represents a single track with `id`, `name`, `artists`, `album`, `picUrl`, and a `MusicSource` enum indicating the platform (NetEase/QQ/KuGou, etc.).
  - `Toplist`: represents a music chart/playlist with metadata (`id`, `name`, `coverImgUrl`, `creator`, `trackCount`, `description`) and a list of `Track` items.
  - `MusicSource`: enum for supported music platforms.
- Models provide `fromJson` / `toJson` helpers and convenience methods like `getSourceName()` and `getSourceIcon()`, which the UI uses to render source‑specific labels and icons.
- The client treats backend responses from different platforms through these normalized models so UI code can remain mostly platform‑agnostic.

### 2. Aggregation backend (`backend/`)

The backend is a monolithic Bun + Elysia service that normalizes access to multiple music/video platforms and exposes user‑facing features. The main entrypoint is `backend/src/index.ts`.

#### Core server setup

- Uses `Elysia` as the HTTP framework with plugins:
  - `@elysiajs/jwt` for JWT‑based user authentication.
  - `@elysiajs/cors` for CORS (currently configured open to all origins for development).
  - `@elysiajs/static` to serve temporary MPD files from `temp_mpd/` under `/mpd` (for Bilibili DASH streams).
  - `@elysiajs/swagger` to generate a Swagger/OpenAPI UI for all routes.
- On startup, the server:
  - Ensures `temp_mpd/` exists and logs all major API groups and endpoints to the console.
  - Runs `checkBiliCookieValidity()` to verify/update the Bilibili cookie and `getConfig()` to load runtime configuration (notably, log level).
- Global hooks:
  - `.onRequest` logs every incoming request.
  - `.onError` unifies error handling and returns structured JSON for validation and server errors.
  - `.onBeforeHandle` / `.onAfterHandle` emit detailed request/response logs when `log_level` is `DEV` (via `logger.dev` and `compactLogString`).

#### Route modules and responsibilities

`src/index.ts` composes the app from modular route files under `src/routes/`:

- Platform integrations:
  - `netease.ts`, `qq.ts`, `kugou.ts`, `spotify.ts` wrap music search, song detail, playlists, albums, and toplists for each platform.
  - `bili.ts` (via `createBiliRoutes({ mpdDir })`) exposes Bilibili ranking, play URLs, PGC endpoints, danmaku, search, comments, and proxy routes.
  - `douyin.ts` handles Douyin share link parsing and direct video URLs.

- User & content features:
  - `auth.ts` and `lib/authController.ts` implement email‑based registration/login, verification codes, password reset, and IP/location tracking, backed by SQLite tables in `data/users.db`.
  - `favorites.ts` and `lib/favoriteController.ts` manage per‑user favorites (add/list/remove tracks).
  - `playlists.ts` and `lib/playlistController.ts` implement user playlists (CRUD, track add/remove/batch operations).
  - `stats.ts` and `lib/statsController.ts` track listening time, play counts, and aggregated listening statistics.
  - `playback.ts` and `lib/playbackController.ts` store and retrieve the last playback state per user (track metadata, position, platform), with a 24‑hour expiry.
  - `accounts.ts` and `lib/*Login.ts` / `lib/*Apis.ts` manage third‑party bindings such as NetEase and KuGou accounts and tokens.

- Administration and system:
  - `admin.ts` exposes an admin login plus user and aggregate stats views.
  - `sponsors.ts` and `pay.ts` handle sponsorship/donation records and payment callbacks, using the `donations` table in `data/users.db`.
  - `weather.ts` exposes a simple weather endpoint used by the client.
  - `health.ts` implements health checks for monitoring and readiness.

Routes are grouped and tagged in Swagger under categories like `Netease`, `QQ`, `Kugou`, `Spotify`, `Bilibili`, `Douyin`, `Auth`, `Favorites`, `Playlists`, `Stats`, `Admin`, `Sponsors`, `Pay`, `Playback`, `Weather`, and `Version`.

#### Persistence and auth

- SQLite is used via `bun:sqlite` with simple schema‑migration logic that adds columns via `ALTER TABLE` wrapped in `try/catch` to avoid failures on existing databases.
- `src/lib/database.ts` centralizes user and sponsorship tables plus verification codes and third‑party account tables (`netease_accounts`, `kugou_accounts`) with appropriate indices.
- `src/lib/playbackController.ts` uses a dedicated `playback.db` under `data/` to store the last playback state per user, keyed by authenticated user ID.
- Authentication middleware (`src/lib/authMiddleware.ts`) verifies JWTs generated by the `jwt` plugin and is used across controllers like playback, favorites, playlists, stats, and admin routes.

#### Cookie handling and external platform access

- `src/lib/cookieManager.ts` manages cookie files for external platforms:
  - Looks for cookie files under `process.cwd()/cookie/` and falls back to `demo/cookie/`.
  - Abstracts reading/writing cookie strings and parsing cookie text into key/value maps.
- Platform API wrappers (e.g. `neteaseApis.ts`, `qqApis.ts`, `kugouLogin.ts`, `bilibili.ts`) rely on these cookie files to access high‑quality or VIP content; missing or invalid cookies will typically degrade available quality rather than fully break basic functionality.

### 3. KuGou API subproject (`kugouapi_github/`)

- This directory contains an upstream KuGou API implementation (separate from the main Bun/Elysia backend) with its own server entrypoints and `package.json` scripts.
- It exposes many more KuGou‑specific endpoints and can be run independently (e.g. for local debugging or alternative deployments), but the main Cyrene Music backend already provides KuGou integration via its own `kugou` routes.

---

## How pieces fit together

- The **Flutter client** uses `UrlService` and the models in `lib/models` to talk to the aggregation backend over HTTP, treating NetEase/QQ/KuGou/Bilibili/etc. through a normalized API and shared data models.
- The **backend** acts as an orchestration layer:
  - Handles user authentication/authorization, favorites, playlists, listening stats, playback state, and sponsorship data in SQLite.
  - Proxies requests to external music/video platforms, applying cookie‑based authentication where needed and normalizing responses.
  - Exposes a single, documented HTTP API (with Swagger) that the Flutter client and any other consumers can rely on.
- The optional **KuGou API subproject** can serve as an alternative or experimental backend for KuGou‑specific features but is not required for the primary app flow.
