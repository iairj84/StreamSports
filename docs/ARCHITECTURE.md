# Architecture

## Purpose

StreamSports is a free Android IPTV player for phones, TV boxes and Android TV.
The viewer supplies an M3U, Xtream or Stalker/MAC playlist plus optional XMLTV
guides; the app ships no channels or subscriptions. It provides Live TV with a
timeline guide, sports events matched against the viewer's own channels,
replays and highlights, movies/series, and multiview.

One application ID (`com.akus0.iptvpreview`) and one version-code stream serve
32-bit and 64-bit ARM devices on Android 7.0+. Beta and stable channels share
the same build; only the published GitHub release differs.

## Tech stack

- **Flutter / Dart** with `provider` state, Material theming and custom TV focus
  handling. French, Spanish and Italian ship as English-keyed dictionaries.
- **Persistence:** `shared_preferences` for small settings, `sqflite` for the
  VOD/series catalogue and EPG, and JSON files in the OS cache directory for
  larger recoverable payloads. Backups live in the app's documents folder.
- **Networking/parsing:** `http`, `xml`, streaming UTF-8/XMLTV parsing, and
  background isolates for large playlist/guide work.
- **Playback:** `video_player_hdr` over the vendored
  `third_party/video_player_android` fork (Media3/FFmpeg), plus wakelock,
  picture-in-picture and a foreground playback service.
- **Android native:** Kotlin method channels in `MainActivity.kt` for device
  type/memory, APK installation, launcher artwork and immersive system bars.
- **Tooling:** Python scripts in `tools/` cover source/APK privacy audits,
  dependency inventory, release cuts, beta/stable mirrors and device profiling.

## Folder structure

```text
lib/
  main.dart                 bootstrap, service graph, Provider tree, splash/retry
  models/                   channel, playlist, EPG, sports, VOD/series value types
  screens/                  Live TV, Sports, Library, player, multiview, settings
  services/                 data, playback, EPG, sports matching, updates, transfer
  utils/                    pure helpers: time, names, categories, themes, routes
  widgets/                  reusable guide, player, sports and settings widgets
  l10n/                     tr() and fr/es/it dictionaries
android/                    manifest, Kotlin channels, release signing, resources
assets/                     icons, launcher art, licence texts, phone-pair form
test/                       widget, service, parser, audit and layout tests
tools/                      Python release/audit/profile tooling and unit tests
third_party/                patched Android video plugin
docs/                       install, development, release and design notes
```

## Main modules

- **`main.dart`** owns startup. It creates `StorageService`,
  `AppPreferences`, `CatalogDatabase`, `PlaylistManager`, `EpgService`,
  `PlaybackService` and `AppUpdateService`, exposes them through `Provider`,
  and remounts home when the language changes. A failed bootstrap shows a
  Retry screen that tears down and rebuilds that service graph.
- **`PlaylistManager` / `PlaylistSession`** own playlist profiles, provider
  sessions, catalogue loading, categories, favourites, hidden groups, channel
  links and guide sources. `PlaylistSession` fetches and normalises M3U,
  Xtream and Stalker data through `M3uParser`, `XtreamApiService` and
  `StalkerPortalService`. `CatalogDatabase` stores on-demand VOD/series pages.
- **`EpgService` / `EpgDatabase`** download and refresh XMLTV feeds (including
  per-playlist and supplemental guides), parse them off the UI isolate and
  store programmes in SQLite. The service exposes now/next, timeline and
  search reads; the sports matcher reuses the same guide database.
- **`PlaybackService`** owns the shared video controller, stream URL selection,
  live buffering, health/reconnect handling, resume positions and
  picture-in-picture. `PlayerScreen` and `MultiviewSession` attach to it
  instead of opening duplicate decoders.
- **Sports services** split by responsibility: `SportsService` fetches
  scoreboards/schedules from ESPN and regional providers; `SportsStandingsService`
  handles tables; `SportsChannelMatcher` prepares catalogue/guide indexes,
  scores candidate channels in isolates and resolves shared feeds;
  `SportsReplayService` classifies replays/highlights. `SportsFollows` and
  `SportsChannelPicks` persist viewer choices.
- **`StorageService`** centralises SharedPreferences keys, per-viewer key
  namespacing and cache-file access. `SettingsBundle`, `BackupService` and
  `DeviceTransferService` reuse it for encrypted LAN transfers and restore.
- **`AppUpdateService`** reads GitHub's rolling `stable-latest` and
  `beta-latest` releases, downloads the APK and hands it to Android's
  installer. `RemoteControls` remaps physical and in-player buttons.
- **Screens** compose services through `Provider`; `TvHomeScreen` hosts the
  Live TV/sports shell, while settings screens write through `AppPreferences`
  or `StorageService` and notify their listeners.

## Data flow

1. `main()` reads the saved language before `runApp`, configures the image
   cache from device memory, then starts `NoxIptvApp`.
2. Bootstrap restores settings and playlist profiles. Live channel restore and
   EPG initialisation continue in the background so the guide is usable early.
3. A playlist fetch is parsed into `Channel`/`XtreamSeries` models, normalised,
   merged with saved names, links and picks, and cached in files/SQLite. The
   in-memory catalog feeds Live TV, Library, Search and Multiview.
4. EPG downloads stream through the XMLTV parser into `EpgDatabase`; guide
   widgets query now/next or time ranges. Sports matching reads the same rows,
   scores them against channels, and publishes progress incrementally.
5. Choosing a channel resolves provider headers/URL in `PlaylistManager` and
   `PlaybackService`; the player or multiview cell owns a controller and
   reports health. Favourites, history and resume points are written back.
6. Settings changes notify providers and persist immediately. Backups and
   device transfer bundle the same preference sections, excluding device-only
   keys such as update checks and resume positions.

## Run, build and test

```sh
flutter pub get
flutter run
flutter analyze
flutter test --concurrency=1
python3 tools/audit_repository.py
python3 -m unittest discover -s tools/tests
flutter build apk --release --target-platform android-arm,android-arm64
python3 tools/audit_apk.py build/app/outputs/flutter-apk/app-release.apk
```

CI runs `flutter analyze` plus four `flutter test` shards on `main` and `beta`
pushes and pull requests. Performance and layout tests are sensitive to
concurrency; run the full suite serially locally unless CI cannot cover it.

## Release flow

Cuts happen on `beta`: `tools/cut_release.py` bumps the patch/build, updates
`CHANGELOG.md`, builds and audits the APK, commits/tags, publishes the
versioned prerelease and refreshes the `beta-latest` early mirror. Stable is a
promotion of already-tested bytes: `tools/promote_stable.py --tag <tag>`
republishes the APK into `stable-latest` (GitHub latest), then `main` is
fast-forwarded. Details live in [release.md](release.md); design rationale in
[NOTES.md](NOTES.md).
