# Code audit

Audit scope: `lib/`, `android/`, `tools/`, CI and release configuration on the
0.2.76 (2569) tree. No code was changed. Verified with `flutter analyze` (clean),
`tools/audit_repository.py` (0 findings) and `python3 -m unittest discover -s
tools/tests` (80 passed, 2 skipped); the full Flutter suite is covered by CI.

## Summary

The codebase is healthy for its size: streaming parsers avoid whole-feed
buffers, provider responses are mostly bounded and sanitized, the Stalker and
device-transfer paths were clearly hardened deliberately, and 236 test files
cover the risky areas. The weaknesses are concentrated in the configuration
plane (transfer, restore, credential storage) rather than in playback or
matching.

The three biggest risks:

1. **AUD-001 — Device transfer runs without enforced approval.** Any device on
   the LAN can discover the one-session token and replace the receiver's entire
   configuration — including playlist logins — without the six-digit code ever
   matching or the viewer accepting. This defeats the feature's stated threat
   model.
2. **AUD-002 — Provider credentials sit in plaintext preferences with Android
   backup enabled by default.** Xtream/Stalker passwords can leave the device
   through OS-level backup and device-to-device migration without the viewer's
   knowledge.
3. **AUD-004 — A malformed playlist payload is a permanent startup failure.**
   Restore/transfer accept unvalidated JSON; one corrupt value makes every
   launch fail, and Retry re-runs the same parse with no recovery path.

Recommended fix order: AUD-001 → AUD-002 → AUD-003 → AUD-004 → AUD-005 →
AUD-006 → AUD-007 → AUD-008 → AUD-009 → AUD-012 → AUD-011 → AUD-010.
Fix 001–004 before the next release; 005–007 belong in the same release train
since they share the restore/transfer surface; the rest are scheduled
hardening and maintenance.

---

## AUD-001 — Transfer bundles are applied without approval and can be replayed

- **Severity:** Critical
- **Category:** security
- **Location:** `lib/services/device_transfer_service.dart:186-211` (discovery
  publishes the bearer token), `:298-323` (`_hello` derives the session key
  before any approval), `:326-385` (`_receiveBundle` never checks approval)

**Problem.** The receiver's only gate on accepting a configuration bundle is
knowing a path token — but `_openDiscovery` hands that token to *any* UDP probe
on the LAN. A single `hello` request then establishes the decryption key before
the viewer is asked anything:

```dart
_code = transferCode(_publicKey, peerKey, _sessionId);
await cipher.derive(peerKey);          // key is live now
final approved = await approval.future
    .timeout(kTransferApprovalWindow, onTimeout: () => false);
```

`_receiveBundle` never consults `approved`; it only checks that the payload
decrypts with the already-derived key:

```dart
final clear = await cipher.open(sealed);
...
report = await bundle.applyTo(_storage);   // replaces all configuration
```

So a LAN attacker can POST `hello`, ignore the on-screen dialog (or wait out the
two-minute timeout, or have the viewer press Decline — the key survives all
three), then POST `bundle` and silently overwrite every transferred section.
Because nothing invalidates the key after a completed or refused transfer, the
same bundle (or a new one) can also be replayed while the Receive screen stays
open.

**Why it matters.** The code's own contract — "a device that is not the one in
the other hand is visible before anything is replaced" — is not enforced.
Impact is full configuration takeover: playlists and their logins are replaced
(attacker-controlled credentials harvest whatever the viewer types next),
favorites/picks are destroyed, and the viewer sees only the normal success
flow.

**Fix.**
1. In `TransferReceiver`, record the approved peer public key (or a one-shot
   nonce returned in the `hello` response) only when `approve()` completes.
2. `_receiveBundle` must reject with 403 unless a matching approval exists,
   then consume it (single-use) so a bundle can be applied exactly once.
3. On `reject()`, timeout, or a second `hello`, clear the derived key and
   restart the handshake (`_cipher = TransferCipher(...)`).
4. After `done`/`failed`, close the HTTP server instead of leaving it listening.

**Done when.** New tests in `test/device_transfer_test.dart` prove: (a) `hello`
followed by `bundle` without `approve()` returns 403 and storage is unchanged;
(b) an approved bundle applies once and an immediate replay is refused; (c) a
declined/timed-out handshake cannot be used afterwards. The existing loopback
transfer test still passes.

**Effort:** M  
**Depends on:** —  
**Status:** [x] fixed in `e9bfd00`

---

## AUD-002 — Provider credentials are plaintext and exposed to Android backup

- **Severity:** High
- **Category:** security
- **Location:** `android/app/src/main/AndroidManifest.xml:25-31`,
  `lib/models/playlist_profile.dart:290`,
  `lib/services/storage_service.dart:221-227`, `lib/services/backup_service.dart:25-29`

**Problem.** Playlist logins are stored as ordinary SharedPreferences JSON,
including the password verbatim:

```dart
'xtreamPassword': xtreamPassword,   // playlist_profile.dart:290
```

The manifest declares no backup policy:

```xml
<application
    android:label="StreamSports"
    ...
    android:usesCleartextTraffic="true"
    android:largeHeap="true"
```

With no `android:allowBackup="false"` and no `dataExtractionRules`, Android's
default auto-backup can copy these preferences to Google's backup transport and
into device-to-device migration. Local backup files are also unencrypted JSON by
design (`backup_service.dart:25-29`), so every path that moves configuration
off the device carries raw provider passwords.

**Why it matters.** A viewer's IPTV credentials are the only secret this app
holds; they grant access to their paid subscription. They should not leave the
device through a channel (OS backup) that the app never mentions and the viewer
never opted into.

**Fix.**
1. Set `android:allowBackup="false"` and add
   `android:dataExtractionRules="@xml/data_extraction_rules"` /
   `android:fullBackupContent="@xml/backup_rules"` that exclude
   `sharedprefes/`, for Android 12+ and 11- respectively.
2. Alternatively (better long term), move secret fields (Xtream/M3U/Stalker
   passwords, portal MAC/signature) out of SharedPreferences into
   EncryptedSharedPreferences or the Android Keystore-backed store, keeping
   non-secret settings where they are.
3. Document the at-rest posture in `SECURITY.md`.

**Done when.** `adb shell bmgr backupnow` (or a backup/restore round-trip on a
Google-account device) shows no `nox_playlists` payload with passwords in the
transport; a manifest policy test (see `test/release_configuration_test.dart`)
asserts the attributes; `SECURITY.md` states where credentials live.

**Effort:** M (S for step 1 alone)  
**Depends on:** —  
**Status:** [x] fixed in `1d35069`

---

## AUD-003 — Raw network errors can publish credential-bearing URLs

- **Severity:** High
- **Category:** security
- **Location:** `lib/utils/xtream.dart:17-18`,
  `lib/services/epg_service.dart:678-683`,
  `lib/services/playlist_session.dart:508`, `:850`

**Problem.** Xtream guide URLs embed the password in the query:

```dart
return '$base/xmltv.php?username=$user&password=$pass';   // xtream.dart:18
```

On failure both fetch paths publish the raw exception to user-visible state:

```dart
} catch (e) {
  _sourceStatuses[url] = (stored: null, finishedAt: DateTime.now());
  error = e.toString();                 // epg_service.dart:681
```

```dart
} catch (e) {
  error = e.toString();                 // playlist_session.dart:508 / 850
```

`http.ClientException.toString()` includes the full request URI, and
`SocketException`/`TimeoutException` texts can carry it too. Those strings are
rendered in Settings and the home screen (`epg_settings_screen.dart:338`,
`tv_home_screen.dart:1989`, `add_playlist_screen.dart:1518`) and copied into
logcat, bug reports and screenshots.

**Why it matters.** The app otherwise treats URLs as sensitive (the Stalker
service explicitly never logs a URL, MAC or token; `safePlaybackError` scrubs
stream addresses from playback errors). The guide/catalog paths break that
rule, leaking the viewer's subscription password to anyone who sees the error
message.

**Fix.**
1. Add a small sanitizer (or reuse `safePlaybackError`'s approach) that strips
   `userinfo`, `username=`/`password=` query pairs and full URLs from exception
   text; use it everywhere a fetch error is assigned to a user-visible field.
2. Wrap the four sites above so only provider-neutral messages ("Couldn't reach
   {host}") reach `error`; keep the raw exception in `debugPrint` limited to
   `e.runtimeType` as the surrounding code already does.
3. Prefer building errors from `Uri.parse(url).host` (as
   `M3uParser._fetchPlaylist` already does) instead of `e.toString()`.

**Done when.** A test drives a failing fixture URL containing
`password=supersecret` through `EpgService._refreshOne` and
`PlaylistSession.loadFromUrl` and asserts `error`/`sourceStatuses` contain the
host but neither `supersecret` nor `password=`; `flutter analyze` clean.

**Effort:** S  
**Depends on:** —  
**Status:** [x] fixed in `1d35069`

---

## AUD-004 — Unvalidated restore payloads can permanently break startup

- **Severity:** High
- **Category:** bug
- **Location:** `lib/services/storage_service.dart:221-227`,
  `lib/services/settings_bundle.dart:156-175`, `:212-224`,
  `lib/main.dart:271-274`

**Problem.** `SettingsBundle.fromJson` validates only shapes and key lengths;
`applyTo` writes values verbatim. Anything that decodes as `String` passes,
including a corrupt `nox_playlists` blob. Reading it back is unguarded:

```dart
final decoded = jsonDecode(raw) as List<dynamic>;    // storage_service.dart:224
return decoded
    .map((e) => PlaylistProfile.fromJson(e as Map<String, dynamic>))
    .toList();
```

and `PlaylistProfile.fromJson` hard-casts required fields
(`id: json['id'] as String`). One malformed entry throws inside
`PlaylistManager.init`, which `main.dart` turns into the startup error screen:

```dart
} catch (e) {
  ...
  if (mounted) setState(() => _bootstrapError = e.toString());   // main.dart:274
```

Retry re-runs the identical parse against the same corrupt preference — the
app is stuck until app data is cleared. Separately, `fromJson` accepts keys
that `capture` classifies as device-only (e.g. `nox_active_viewer_id`), so a
hand-crafted bundle can overwrite state the transfer contract promises never to
touch.

**Why it matters.** "Restore from my phone" and device transfer are the
disaster-recovery features; a payload they accept must never turn into an
unbootable app. Silent overwrite of device-only keys also breaks the
documented boundary ("Device-only keys … are never sent and never cleared").

**Fix.**
1. Make `getPlaylists()` tolerant: decode in a `try`, skip entries whose
   `fromJson` throws, and fall back to `[]` (optionally retaining the raw
   blob under a debug key) instead of propagating.
2. In `SettingsBundle.fromJson`/`applyTo`, drop keys where
   `transferSectionOf(key) == null` so device-only keys can never be written
   by a bundle.
3. Validate `PlaylistProfile`-shaped values (or the decoded list) before
   `replaceRawPreferences`, and reject the bundle with the existing "settings
   this version cannot read" error.

**Done when.** Tests prove: a bundle whose `nox_playlists` is not profile JSON
is refused (or sanitized) and the app completes bootstrap afterwards; a bundle
carrying `nox_active_viewer_id` leaves that key unchanged; the existing
`device_transfer_test` / `backup_test` suites pass.

**Effort:** M  
**Depends on:** —  
**Status:** [x] fixed in `1d35069`

---

## AUD-005 — Restore/transfer leave AppPreferences and language stale

- **Severity:** Medium
- **Category:** bug
- **Location:** `lib/services/app_preferences.dart:58-70`,
  `lib/screens/settings/backup_screen.dart:114-118`, `:232-234`,
  `lib/screens/settings/device_transfer_screen.dart:166-175`, `lib/main.dart:50`

**Problem.** After applying a bundle, only the playlist manager reloads:

```dart
final report = await BackupService.restore(_storage, backup);
await manager.reloadFromStorage();          // backup_screen.dart:117
```

`reloadFromStorage` rebinds `ChannelRenames` and rebuilds playlist sessions,
but `AppPreferences` caches palette, surface style, clock, tab visibility,
24-hour time etc. once in `init()` (`app_preferences.dart:58`), and `L10n.apply`
runs only at startup (`main.dart:50`). The success message claims "settings
were restored", while the visible theme/language stay from the old
configuration until the app restarts.

**Why it matters.** The transfer and restore screens tell the viewer the job
is done; partially-applied settings read as a bug (or as an unsuccessful
restore), and a user who then tweaks any setting writes from the stale
in-memory model, masking the restored values further.

**Fix.** After `bundle.applyTo`/`BackupService.restore`, add a `reload()` on
`AppPreferences` (re-read every field from storage and `notifyListeners()`),
run `L10n.apply(storage.getLanguage())` and re-apply
`applyPlaybackBufferPreset`/`LiveResumeHint.pillEnabled` the way
`_bootstrap` does; keep `manager.reloadFromStorage()` for catalogue state.

**Done when.** A widget/service test restores a bundle with a different
palette, clock format and language and asserts the in-memory
`AppPreferences`/`L10n` reflect it immediately (no restart), and that the
existing restore tests still pass.

**Effort:** S  
**Depends on:** AUD-004 (safe payload application)  
**Status:** [ ] open

---

## AUD-006 — Configuration replacement is not atomic

- **Severity:** Medium
- **Category:** bug
- **Location:** `lib/services/storage_service.dart:1063-1086`,
  `lib/services/settings_bundle.dart:212-224`

**Problem.** `applyTo` computes a removal list and then runs a per-key loop:

```dart
for (final key in remove) {
  await _prefs.remove(key);            // storage_service.dart:1067
}
for (final entry in values.entries) {
  ... await _prefs.setString(key, value);   // one SharedPreferences commit each
}
```

Each `setX` is its own persisted commit. If the process is killed (or a write
throws) halfway, the device ends with a mix of the old and new configuration —
e.g. new playlists but old favorites, or cleared sections with no replacement —
with no record of the interruption.

**Why it matters.** Transfer/restore is sold as "the receiving device is
replaced, never merged"; a torn write violates exactly that guarantee and is
very hard for a viewer to diagnose or repair (there is no per-item undo).

**Fix.** Capture the current raw preferences first (already available via
`rawPreferences()`), attempt the replace, and on any exception restore the
snapshot; better, stage the whole bundle under one key and swap atomically
(single `setString`), then materialise keys from the staged copy and drop it.
Keep the pre-change snapshot as a one-shot undo offered by the restore UI.

**Done when.** A test injects a storage failure at the Nth write (mocked
`SharedPreferences`) and asserts the pre-restore configuration is intact
afterwards; a kill-mid-write simulation leaves either the complete old or the
complete new configuration.

**Effort:** M  
**Depends on:** AUD-004  
**Status:** [ ] open

---

## AUD-007 — Concurrent profile writes lose updates

- **Severity:** Medium
- **Category:** bug
- **Location:** `lib/services/playlist_session.dart:718-727`, `:765-787`,
  `lib/services/playlist_manager.dart:487-495`

**Problem.** Every profile mutation is a read-modify-write of the whole list
from independently captured state:

```dart
final updated = storage
    .getPlaylists()
    .map((p) => p.id == profile.id ? profile : p)
    .toList();
await storage.setPlaylists(updated);        // playlist_manager.dart:489-493
```

Background refreshes write `lastWorkingServer`
(`_rememberWorkingServer`, `:718`), `expiresAt` (`:771`) and `maxConnections`
(`:782`) through the same pattern while the settings UI can be editing the
same profile. Two overlapping writers each serialise their own snapshot; the
later `setPlaylists` silently drops the other's field change.

**Why it matters.** The loss is silent and only happens during real usage
(edit a playlist while a slow provider refresh completes), so it surfaces as
"user's rename/backup server disappeared" with no error anywhere.

**Fix.** Route all profile writes through one serialized helper (e.g.
`PlaylistManager.updateProfile(id, transform)` that re-reads storage
immediately before applying the transform and chains writes through a single
queue), and have `PlaylistSession` call it instead of writing storage
directly.

**Done when.** A test runs a user edit and a background
`rememberWorkingServer`/expiry update concurrently and asserts both changes
survive in `getPlaylists()`; existing playlist tests pass unchanged.

**Effort:** S  
**Depends on:** —  
**Status:** [ ] open

---

## AUD-008 — Xtream API responses are buffered without a size bound

- **Severity:** Medium
- **Category:** performance
- **Location:** `lib/services/xtream_api_service.dart:75-99`

**Problem.** `_getJson` uses `client.get(...)` (whole-body buffering) and then
ships the bytes to an isolate:

```dart
response = await client.get(_apiUri(action, extra), headers: _headers)
    .timeout(const Duration(seconds: 30));
...
return await compute(_decodeJsonBody, response.bodyBytes);
```

There is no byte cap. The Stalker transport explicitly bounds responses
(`_maxBytes = 16MB`, `stalker_portal_service.dart:95`) and XMLTV is streamed
line-by-line, but a hostile or misbehaving Xtream provider — or an on-path
attacker, since cleartext is permitted — can return a multi-GB `player_api.php`
body that is materialised fully in memory before any parsing, defeating the
app's careful streaming work everywhere else and OOM-ing capped-heap devices.

**Why it matters.** Playlist connect is the app's most common remote input; one
absent bound gives any provider trivial local denial of service and re-opens
the exact `OutOfMemoryError` class the streaming parsers were built to avoid.

**Fix.** Switch `_getJson` to `client.send` with a streamed cap (e.g. 32 MB,
consistent with `_maxBytes`); abort past the cap with a clear
`XtreamException('The server response is too large to load safely.')`, then
decode the collected bytes as today.

**Done when.** A loopback fixture returns an oversized body and the app
reports the size error without allocating the payload (assert in a focused
test); existing Xtream tests pass.

**Effort:** S  
**Depends on:** —  
**Status:** [ ] open

---

## AUD-009 — Privacy audit and tools tests are not gated in CI

- **Severity:** Medium
- **Category:** testing
- **Location:** `.github/workflows/ci.yaml:1-47`,
  `tools/source-audit.workflow.yml`, `docs/development.md:25`

**Problem.** CI runs only `flutter analyze` and four `flutter test` shards. The
repository privacy scan and the tools unit tests run only from
`tools/source-audit.workflow.yml`, which `docs/development.md` instructs a
human to copy into `.github/workflows/source-audit.yml` — that file does not
exist in the repository, so nothing enforces the copy. Whether
`tools/audit_repository.py` and `python3 -m unittest discover -s tools/tests`
gate a release therefore depends on the operator remembering AGENTS.md.

**Why it matters.** The project's central privacy guarantee — no secrets,
keystores or private datasets in source/APK — is only as good as a manually
installed workflow; a fresh clone or a rushed release can skip it entirely.

**Fix.** Commit `.github/workflows/source-audit.yml` (content of
`tools/source-audit.workflow.yml`) or fold its two commands into an extra job
in `ci.yaml` so every push/PR runs `tools/audit_repository.py` and the tools
unit tests; update `docs/development.md` accordingly.

**Done when.** A PR adding a synthetic `.env` fixture with a fake secret fails
CI; both commands appear in the Actions log for a normal push.

**Effort:** S  
**Depends on:** —  
**Status:** [ ] open

---

## AUD-010 — A few giant files carry most behavior

- **Severity:** Medium
- **Category:** maintainability
- **Location:** `lib/screens/tv_home_screen.dart` (6,515 lines / 265 KB),
  `lib/screens/sports_screen.dart` (5,192 lines / 212 KB),
  `lib/services/sports_channel_matcher.dart` (4,911 lines / 196 KB)

**Problem.** Three files account for roughly 16,600 lines. The matcher alone
mixes channel indexing, scoring, isolate protocol, guide snapshots and three
cache policies; `tv_home_screen.dart` contains the Live shell, guide, rails,
focus policy and theme plumbing. `docs/development.md` documents detailed
invariants for these areas, but nothing but convention keeps a change inside
its intended module.

**Why it matters.** Every sports or guide fix must be reasoned about inside
multi-thousand-line units, review cost and regression risk stay high, and the
architecture doc's "Matching flow and ownership" table has no enforcing code
boundary — drift between doc and code is inevitable.

**Fix.** Extract along seams the docs already name: worker transport
(`_BackgroundSportsMatcher`), batch planning, scoring and cache policy into
`lib/services/sports_matching/` modules; split `tv_home_screen.dart` by
route/panel (Live shell, guide surface, rails/navigation); add a line budget
check to `tools/audit_repository.py` (e.g. fail above 3,000 lines per file for
new growth). Migrate incrementally, keeping tests green per extraction.

**Done when.** Each listed file is under ~2,500 lines or a dated extraction
plan lives in `docs/NOTES.md` with the first slice landed; `flutter analyze`
and the focused suites for touched areas pass.

**Effort:** L  
**Depends on:** —  
**Status:** [ ] open

---

## AUD-011 — CI tests a different Flutter version than releases build with

- **Severity:** Low
- **Category:** testing
- **Location:** `.github/workflows/ci.yaml:15`, `AGENTS.md:9`,
  `docs/development.md:3`

**Problem.** CI pins `FLUTTER_VERSION: 3.47.4` while the documented build
machine (AGENTS.md, development.md) is Flutter 3.47.7. Analyze and the test
shards therefore certify a different toolchain from the one that produces the
shipped APK.

**Why it matters.** Analyzer lints and SDK fixes between patch releases can
pass CI yet fail on the release machine (or vice-versa), and the workflow's own
comment says to bump it "together with the build machine" — the two have
already drifted.

**Fix.** Bump `FLUTTER_VERSION` to `3.47.7` and note the single source of
truth (AGENTS.md) in the workflow comment; when upgrading Flutter, change
both in one commit.

**Done when.** The CI log shows 3.47.7 and analyze/tests are green on it.

**Effort:** S  
**Depends on:** —  
**Status:** [ ] open

---

## AUD-012 — In-app updater installs without checking the published digest

- **Severity:** Low
- **Category:** security
- **Location:** `lib/services/app_update_service.dart:297-365`, `:368-385`,
  `tools/cut_release.py:189`

**Problem.** The release tooling records `SHA-256` and byte size in the release
body, but `download()` streams the asset straight to disk and `install()` hands
the file to the package installer without ever comparing the two:

```dart
await for (final chunk in response.stream) {
  sink.add(chunk);                      // app_update_service.dart:334
  ...
}
...
await _channel.invokeMethod<String>('installApk', {'path': file.path});  // :374
```

A truncated or swapped asset (mirror or CDN misbehavior, storage fault) is
therefore offered to the installer as-is.

**Why it matters.** Android's signing check blocks unsigned or foreign-key
APKs, so this is defense-in-depth rather than an open exploit — but the
project already publishes the digest and never consumes it; a corrupted
download fails confusingly at the installer instead of at download time.

**Fix.** Parse the `SHA-256`/size from the release body in `_latestRelease`,
hash the file after download (and compare `contentLength`/size), and refuse
`install()` with a clear error when they differ.

**Done when.** A test downloads a fixture asset whose bytes differ from the
body digest and asserts `install()` reports the integrity error and never
calls the channel; the happy path still installs.

**Effort:** S  
**Depends on:** —  
**Status:** [ ] open
