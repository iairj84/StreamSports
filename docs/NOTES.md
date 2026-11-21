# Design notes

## The cut no longer reruns the tests

A cut's gate used to rerun nine suites and 94 cases locally before the build
started. On the release machine that step was the whole gate: 177-182s wall,
with the test step at 177-182s, the analyzer at 100-114s (the tests held all
eight cores), the source audit at 9-10s and the tools' own tests at 15-16s. It
also re-tested code the cut was not shipping. A cut's own commit changes
`pubspec.yaml` and `CHANGELOG.md`; the app it packs is the previous `beta`
commit, and CI runs the full suite in four shards on that push (ci.yaml triggers
on `beta`). So the local rerun covered nothing the release carried.

The cut now runs `python3 tools/preflight.py` with no test files: analyzer,
source audit, tools tests. Five runs after the change measured 18s, 18s, 17s,
19s and 93s wall (source audit 7-9s and tools tests 10-11s throughout), against
177-182s before. The analyzer is all of it now, and it moves with its cache:
17-18s warm, 93s on a run that re-analyzed after a source change, and about
181s cold in the 0.2.83 run - level with the old gate at worst, and the warm case
is the saving.

`python3 tools/preflight.py` with no test paths used to run `flutter test` over
the whole suite, contradicting its own docstring ("analyze and the audits
only") and AGENTS.md's rule against the full suite in one checkout. An empty
list now means no test step, so the documented release command cannot quietly
start a 22-minute run, and `test_preflight.py` pins it. The first attempt at this
measurement was that accidental run: it starved the analyzer to 247s and had to
be killed.

What the trade costs: CI reports after the cut has published, not before it.
The green that protects a release is the feature commit's run on `beta`; a red
run on the release commit itself arrives post-hoc and means fixing forward.

## A version bump invalidates the whole AOT compile, and reordering cannot help

Two builds on one warm tree, with a 54.7 MB release APK already in `build/`:

- Nothing changed: `flutter build apk --release --target-platform
  android-arm,android-arm64` took 127s. `kernel_snapshot_program` was skipped
  and no `gen_snapshot` ran.
- Only `version: 0.2.84+2577` became `0.2.85+2578`: 186s. Flutter opened a new
  `.dart_tool/flutter_build/bf41f56a12d4e703947559929c8126b0`, ran
  `kernel_snapshot_program` for 39.1s and executed both AOT snapshots.

The version is part of the build system's environment (FLUTTER_BUILD_NAME and
FLUTTER_BUILD_NUMBER), so a bumped version is a different build directory, and
Flutter's release compile is all-or-nothing: it skips the target or recompiles
the kernel. `--build-name`/`--build-number` feed those same two defines, so they
change nothing about this. The 127s case also needs unchanged Dart source, which
a release carrying code never has: the same bump before a cut with real changes
costs nothing extra, because the kernel and AOT snapshots were going to run
anyway. So the version bump adds about 59s only to a release with no Dart change,
and "build first, stamp the version afterwards" would trade that for an APK
stamped with the previous version.

## The release gate runs its four checks at once

Non-build time in a cut was mostly waiting. Measured in the 0.2.83 release run
(8 cores, Windows): `flutter analyze` 181s, three focused test files 280s with
`--concurrency=1`, `tools/audit_repository.py` 11s and the tools' unit tests
13s — 485s of work that never had to happen in sequence. The four read
independent inputs (sources, fixtures, the worktree, the APK) and none writes
what another reads, so `tools/preflight.py` starts them together, reports each
one as it finishes and fails with that check's own output.

The same gate through the runner measured 317s wall: analyze 88s, tests 317s,
source audit 9s, tools tests 13s. The saving is the checks that used to add up
behind the slowest one, which is why the wall time is now the test step rather
than its sum. Analyze varies with cache warmth (88s here against 181s in the
cold release run), so read the runner's per-check numbers rather than trusting
a fixed budget.

Parallel `flutter test` is not what buys most of the time. Those three files
take 266s at the default concurrency and 280s serial. Beside the analyzer the
test step measured 317s, so the contention costs about 50s and the overlap
still returns 2.8 minutes.

The 253s file was not one long test. Its 84 cases measured 285s with the JSON
reporter: the first case paid a 45s cold start (compile, sqflite, first widget
tree), the largest single case was 30s (`Live column drills ...
fullVideo=false`) and the rest were mostly 1-4s. Six suites now carry those
same 84 cases — `live_layout_navigation_test.dart` (26),
`sports_tabs_navigation_test.dart` (10), `sports_panels_navigation_test.dart`
(5), `sports_card_navigation_test.dart` (14),
`sports_matching_navigation_test.dart` (15) and `live_layout_fit_test.dart` (14,
split in two below) over one `live_layout_test_support.dart` holding the fake services. Alone
they measure 69s, 30s, 49s, 53s, 49s and 97s; together 174s. The gate around
those six plus `live_sports_channels_test.dart` and `l10n_parity_test.dart`
went from 317s wall to 211s, and its test step from 317s to 210s.

Each suite pays about 12s of compile and harness startup of its own, so the
split adds work as well as removing a serial block: the parts sum to roughly
350s against 285s for the original file, and all of the gain comes from
overlap. That is why the largest suite was the floor then rather than a 253s
block. It was not the floor for long: at 97s it was still the biggest single
file, so it was measured case by case in the next pass.

## The fit suite is two files, because its cost is spread

The 97s fit suite's 14 cases carry 98.7s of test time in the JSON reporter's
own durations, so almost none of it is startup: `guide and navigation fit`
24.8s, 25.4s and 17.5s at 960x540, 390x844 and 1280x720; `guide sports
survive scores and refresh` 20.6s (that file's cold start) then 2.3s and
2.1s; `tennis tournament cards fit` 0.8-2.1s across four sizes; `sports
header keeps its controls readable` 0.3s across four. No case dominates, and
the expensive ones are not waits that a restructure could delete: the three
fit cases are 68s of real work, mostly inside `settleSports`, which drives
200 rounds of a 5ms real delay so background matching can settle.

So the four loops became two files: `live_layout_fit_test.dart` (3 cases, the
fit loop, 74s alone) and `live_layout_cards_fit_test.dart` (11 cases, survive,
tennis and header, 17s alone). Same names, same assertions, same 14 cases; a
statement-by-statement comparison against the previous commit reports none
missing, added or duplicated. The 68s fit loop is left in one file on
measurement rather than taste: those three cases share its cold start, and
each further file would buy nothing with its ~12s of compile and harness
startup.

Gate after the split, on the same machine: 211s wall to 182s and then 177s on a
second run, test step 210s to 182s and 177s, with analyze 114s/100s, source
audit 10s and tools tests 16s/15s (322s and 302s if the four checks ran one
after another). The nine suites on their own run 163s and
report 94 passing tests, the same 94 as before. One earlier run of the same
command failed its test step at 200s, before these two clean runs; the
failure's output was lost to a truncated log, so it is recorded as an
unexplained flake rather than a saving.

`dart analyze` measured 127s against `flutter analyze`'s 181s on the same clean
tree, and the gate keeps `flutter analyze`: CI runs exactly that command, and a
gate that is faster because it checks something else is not a saving.

The full suite stays out of the runner. It runs in CI's sharded matrix, and a
single serial local run is the only local form that does not flake; wrapping
four checks together does not change that.

## The picker search reads the listing, and the query outranks the guess

The sports card said the game was on CBSSN and offered "No Channel - Choose".
Typing CBSSN into the picker answered with zero channels plus a stray shopping
channel whose current programme was a basketball sitcom, while the same query in
the live guide found the service immediately. Two independent causes:

The live guide search has always matched channel name plus current programme
title *and description* (`lib/utils/live_guide_search.dart`). The picker's search
matched channel name, network alias and programme *title* only - so a listing
that names the network in its synopsis ("Duke at North Carolina (CBSSN)") was
invisible to it. Providers name the network in the synopsis far more often than
in the title, which is why the guide found it and the picker did not. The
picker's now/next slots now carry title plus the first 400 characters of the
synopsis, lowercased but not punctuation-normalized: the searched words already
are, and regex-cleaning a paragraph for every channel on every keystroke is not
worth it on a TV box (measured about +50-90ms on a 20,000-channel catalogue full
of long synopses, in a debug VM; searches are debounced and cancellable).

The stray row was a second bug. The matcher seeds the event's own matched
channels into every search result so a viewer looking at a card always sees its
channels. That seeding sorted above every row the query found, because the
comparator ranked by evidence tier before score - a weak sport match (a sitcom
that mentions basketball) therefore beat the network's own channel. Results now
carry a lens instead of a tier: explicit pick, then a confident match, then "it
answers the typed words", then "the card's weak guess". The bottom lens is the
new one, and it is what stops a stray programme from leading a search it does
not answer.

Widening "the query found it" to the whole lens was wrong in the other
direction: a test pins that a channel the viewer explicitly picked still leads a
search for a rival's name, and the confident case is the same one seeding was
added for (a typed team name is usually absent from the name of the channel that
carries its game). Only the weak guess moved.

The day-window fallback stays title-only: it reuses the guide store's
title-indexed scan, so widening it to synopses would mean a full description
scan of two days of programmes per keystroke. The now/next slot covers the case
that matters for a network query, because the channel airing now is the one the
viewer wants.

## The scoreboard pipeline is a table, not six switches

Adding a league used to mean finding `switch (league.source)` in six places:
`supportsSportsScoreboard`/`supportsSportsSchedule` (two predicates), the URL
builder in `_download`, the cache key in `_scoreboardKey`, the expiry rule in
`_freshEntry`, the parser dispatch in `_parseScoreboardResult`, the bounded-read
host allowlist in `_getScoreboard`, and the schedule-window branch that chose
monthly/ESPN vs daily/regional vs motorsport. Two of those were separate switches
over the same four cases (cache key and expiry are the same axis), and the
bounded-read set was a host list that had to match the URL builder exactly - a
copy-paste bug there silently removes the size cap.

`lib/services/scoreboard_feeds.dart` now holds one `ScoreboardFeed` per
provider: the URI builder, the optional POST body, whether to read with the size
cap, whether to decode UTF-8 rather than trust the charset, the cache window
(day/month/season/current season, which yields both the key and the expiry
anchor), the schedule strategy, and the parser. Everything else reads that
table. ESPN stays the default because most leagues name no provider of their
own, and an unknown source keeps falling back to ESPN's *parser* while still
reporting as unsupported - a saved league from a newer build must not request a
path this build cannot score.

The ESPN parser itself moved to `lib/services/espn_scoreboard.dart` (about 760
lines: team, golf, racing, fight and tennis event shapes plus their helpers) so
the catalogue can reference it without a circular import, and `sports_service`
re-exports it so every existing import path still works. It also leaves the
service about fetching and caching rather than parsing.

What deliberately did not move: the per-league parsers. EASL's pools, K League's
split ranks and RugbyPass's published table are different formats, and a
generic field-mapping engine over them would be longer than the six parsers and
lose their specific validation (position uniqueness, UUID shape, split-phase
codes). The catalogue removes the wiring duplication, not the format knowledge.

`test/scoreboard_feed_catalogue_test.dart` keeps the table honest: every entry
is filed under the source it serves, no two requested feeds share an address,
every catalogue-scored league reports score support, and each provider's URL,
body and decoding flags are asserted once.

## Standings: same shape where it is a dispatch, explicit where it composes

`sports_standings_service._load` held a chain of `if` blocks, one per
own-source competition (B.League, NPB, KBO, ABL, EASL, K League). Each did
read → compute → assign, and because a league has exactly one source, exactly
one block ran: it was a dispatch wearing an if-chain, with the season rule and
the ABL's previous-season retry buried in the middle of it.

`lib/services/standings_feeds.dart` makes that dispatch a table keyed by league
id, carrying the request, method, headers, the season rule (`yearOf`) and the
retry flag. The league id is only half the match: an entry also names its
source and the lookup checks both, because the old code did — a saved league or
a hand-built instance with a catalogued id and a different source must fall
through to the ESPN path rather than being answered by a provider it does not
belong to. The one generic loader is `_loadOwnSource`.

Deliberately not tabled:

- **ESPN itself.** Its table, one-season retry and team-directory fallback are
  one pipeline with three stages, and several leagues then enrich the directory
  with a second source (field hockey, World Rugby rankings, the annual rugby
  competitions and RugbyPass, NPC, the NCAA soccer polls). That composes rather
  than dispatches; a table would have to grow a mini-language for "and then".
  The enrichment order is the correctness property, so it stays visible.
- **MotoGP.** A class table needs a season lookup before the category table, so
  it is not one request and one parser; it keeps its own source object behind
  the same transport.

The standing value types (`StandingTeam`, `StandingTable`, `LeagueStandings`)
moved to `lib/models/standings.dart`, re-exported from the service so every
existing import still works. That was not cosmetic: the per-league parsers
imported the service that calls them, so the table would either have created a
real import cycle or forced the service to own data that is not its business.
Every parser now imports the model instead.

## No OS backup, and three ways a bad payload is refused

Three audit findings shared one property: the configuration plane could leave
the device or replace itself without validation. AUD-002, AUD-003 and AUD-004.

**Android backup is off.** Xtream and Stalker logins are ordinary shared
preferences, with no backup policy in the manifest, so auto-backup could copy
provider passwords to Google's transport and into device-to-device migration
without the viewer opting in. `allowBackup="false"` is the switch that matters;
`backup_rules.xml` (API 23-30) and `data_extraction_rules.xml` (31+) keep the
exclusion explicit for vendor ROMs that ignore it, and exclude the whole data
set rather than just preferences because the app's own backup files are
unencrypted by design. The long-term alternative - moving secrets into
Keystore-backed storage - was rejected for now: it adds a native dependency and
a migration for every existing install, and it solves nothing that backup-off
does not, because the app already offers its own encrypted transfer as the way
to move a configuration between devices. `test/backup_policy_test.dart` reads
the shipped manifest and both rule files, so re-enabling backup fails a test
instead of shipping.

**Fetch errors are rebuilt from the origin.** `http.ClientException`,
`SocketException` and `TimeoutException` put the request URI in their text, and
an Xtream guide URL carries `username=` and `password=` in the query. The guide
and playlist paths assigned `e.toString()` straight to the user-visible `error`
field, so a failure published the viewer's login in Settings and in any
screenshot of it. `safeFetchError` reduces every address to `scheme://host:port`,
redacts credential pairs that arrive outside a URL, and keeps classified
failures ("connection refused") as one sentence plus `host:port` - the port
matters, because one panel host usually serves several subscriptions. It is
deliberately not `safePlaybackError`: playback hides the address entirely, while
a guide failure is only actionable with the host. Provider messages with no
address in them (`Invalid Xtream username/password`) pass through untouched, so
account rejection still reads as itself.

**An unreadable configuration can no longer brick startup.** `getPlaylists`
decoded the preference with hard casts and no guard, so one corrupt entry made
every launch fail, and Retry re-ran the same parse. It now skips unreadable
entries (the rest of the configuration still loads) and logs the failure; a
silent fallback to `[]` was rejected because losing one playlist beats losing the
app, and a partially readable list is the common case after a transfer.
`SettingsBundle.fromJson` therefore had to tighten too, or a corrupt payload
would simply be written and tolerated later: it drops keys the transfer contract
calls device-only (so a hand-built bundle cannot write `nox_active_viewer_id`),
and refuses outright a playlist section that does not decode into
`PlaylistProfile`s - the payload was never valid, and refusing it before the
write is clearer than accepting three of four playlists. `applyTo` re-filters
independently, because `SettingsBundle` can be constructed without `fromJson`.

## Retry rebuilds the service graph

The startup error screen's Retry re-ran `_bootstrap`, but every service field was
`late final`; the second assignment threw `LateInitializationError`, so a failed
launch could never recover without killing the app. The fields are now nullable
with ordinary getters, `_disposeServices` tears down the previous EPG, playback,
playlist and preference objects, and a `_bootstrapping` guard ignores double
taps. Re-keying the whole root widget was considered, but that leaves the first
attempt's timers and database work alive and makes every test recreate the tree;
teardown at the one retry boundary is smaller and testable. `startup_test.dart`
fails the first bootstrap with a wrong-typed preference, repairs the store, taps
Retry and expects the welcome screen instead of `LateInitializationError`.

## Promotions stamp the tag, not the checkout

`promote_stable.py` used `publish_mirror`, which read `pubspec.yaml` from the
current checkout. The documented order promotes before fast-forwarding `main`,
so promoting 0.2.74 from a 0.2.64 `main` wrote `Build: 0.2.64 (2557)` into
`stable-latest` while serving the 0.2.74 APK; the updater trusts that line and
stable clients were never offered the build. Promotion now parses the version
and build from `--tag` and passes them through, and a unit test promotes from a
deliberately stale checkout to pin the behavior. Requiring an up-to-date
checkout was rejected: the tool should be safe regardless of operator order.

The CI gate now also runs on pushes to `beta`, because releases are cut there
and a PR-only or `main`-only trigger never sees the branch being shipped. That
gate immediately caught a settings test still assuming the Multiview row was
built above a 390x844 fold; it now uses a viewport tall enough for every lazily
built section instead of scrolling the list back and forth.

## The phone page wears the app's clothes

`pair.html` used to be a web form that happened to talk to a TV: its own grey
palette, its own square buttons, and the pre-rename project name in every
heading. That page is where a viewer is asked for provider logins, so looking
like an unrelated website undermines the one moment the app has to look
trustworthy on a second screen. It now reads as another screen of StreamSports.

Nothing here is a second design system. The page carries the same tokens the
app does, expressed as CSS variables:

The palette blocks are not approximations: they are the values
`buildPaletteColorScheme` actually produces for each `CyberpunkPalette`,
printed from a throwaway test and pasted in. Re-deriving Material's HCT seeding
in CSS would mean shipping colour-science code to a phone for a page whose job
is one form.

Two traps only showed up once the page was rendered. A custom property that
aliases another (`--select: var(--accent)`) is resolved where it is *declared*,
so a per-palette `--accent` override still left every palette selecting in
Classic's blue — selection is now its own value in every palette. And the app's
true-black branch builds on `ColorScheme.dark()`, whose neutrals resolve to
pure white: faithful alphas there would draw a white outline around every
panel and field, so Lime black's hairlines are white at 8–13% and its secondary
text is white at 62% instead of 100%, which is what keeps the reading
hierarchy the rest of the app has.

The surface tokens copy `SurfaceTokens`' three-way split rather than one general
"rounded" flag: Classic keeps flat fills and 8px corners, Modern adds its glow,
and Stadium Night brings its 16px panels, 18px chips and 12px buttons with
tracked uppercase labels, tracked uppercase buttons and ring-only selection
(`box-shadow: inset 0 0 0 2px` instead of an accent fill) — the same
`focusRingOnly` distinction the widgets make. A selected tab therefore fills
with the accent in Classic and keeps its surface in Stadium Night, which is
exactly how a focused row behaves on the TV.

The look reaches the phone through the query string (`?p=<palette>&s=<surface>`,
next to the existing `b=restore`), not through the payload: it changes nothing
about what the TV accepts, the fragment still carries the relay key, and both
the relay and the LAN server route on the path alone. On the setup form the
selects start on that same look, so sending never resets a theme the viewer
already chose, and changing either one repaints the page — the choice previews
itself while the thumb is still on the screen.

## First run sets up on the phone, not the remote

A new install used to ask "add a playlist?" and then hand over a form built
for a remote: provider login, then a second trip through Settings for the
look, the clock and the update channel. Each of those already had a phone
path — but as five separate QR codes, each knowingly limited to one thing.

So `PairingKind.setup` is one payload with two halves:

```json
{"mode":"setup",
 "playlist":{"mode":"xtream","name":"…","server":"…","username":"…","password":"…"},
 "settings":{"palette":"oled","surface":"stadium","clock24":"true",
             "scores":"false","update":"stable"}}
```

The phone page reuses the Add Playlist form rather than growing a second
one, so Xtream, M3U and Stalker share the same fields, validation and
"Send to TV" button as the existing flow; `.setup` only unhides the Stalker
tab, the content-type choices and an appearance section. That keeps a fix to
the playlist form from having to land twice.

On the TV side the settings are applied *before* the playlist is added. The
add starts its own guide refresh and catalogue load, and those paint the
first guide rows; applying the theme afterwards would show the old colours
for a second and then switch. Playlist failures roll back the empty profile
and leave the screen up — the phone page has already stopped its session, so
`PhonePairPanel` shows "Code expired" with a New code button and the viewer
rescans after fixing the details.

`PairingResult.fromJson` only accepts the keys in `setupSettingKeys`, and
`PairingKind.playlist` refuses a setup payload even though it carries a
valid playlist mode. Between them, a stale page, a hand-edited one, or an
old QR code still on screen cannot write a preference the phone page was
never meant to touch. Unknown palette or surface ids are ignored at apply
time instead of being rejected, so a newer phone page that offers a theme
this build does not know cannot break the whole setup.

### Setup is not a one-time screen

The same screen opened from Settings > Your TV > Set up from phone, because a
second playlist or a later look change is the same job as the first one. It is
the identical route and payload handling, not a copy: the tile pushes
`SetupFromPhoneScreen`, and the success path pops to the first route, which
from Settings means back to the app rather than to an empty welcome page.

The apply path is covered by `test/phone_setup_test.dart`, which follows the
fake-manager pattern the Add Playlist tests use and drives the panel's own
`onResult` callback rather than a test-only door into the screen. It asserts
all five settings land in storage and in the live preference objects, that the
playlist is saved with the phone's credentials and its guide starts, that an
unsupported key writes nothing, that a failed first load removes the profile
and leaves the QR panel showing a New code button, and that the two session
kinds refuse each other's payloads. `PhonePairingSession.acceptsResult` exists
for that last assertion: opening a real socket to prove a refusal rule would
test the server, not the rule.

The panel keeps a waiting spinner while it is on screen, so its tests pump
frames instead of settling; `pumpAndSettle` only returns once the success path
has popped the screen, which is exactly why the failure case needs the former.

What stayed out of the setup form: league and team picks, the language, and
the playback buffer choices. The point of that screen is the five-minute path
from install to a picture; every one of them is on the settings page below.
Hidden-channel and rename flows keep their own QR codes, because they act on
a catalogue that does not exist yet at first run.

### Settings without a playlist

The QR code under Settings > Your TV is a *setup* code: it carries a playlist
because that is the job there. Every other preference — clock, language,
startup buffering, live buffer, playback at startup, the resume pill, the
Movies / Series / Multiview rows, hidden scores, the update channel — could
only be changed by scanning that code and writing a provider login into it
first, which made the phone's settings page unusable as a settings page.

`PairingKind.settings` and a `.settings` view in `pair.html` split them:
`{"mode":"settings","settings":{…}}` carries no playlist at all, and
`SettingsFromPhoneScreen` applies it with no `PlaylistManager` in scope. The
page shows the app-wide preferences a remote makes tedious, grouped the way
the settings screens group them. The setup page falls back to the same
payload: with every playlist field left blank it sends the look and update
choices alone instead of demanding a login, and `SetupFromPhoneScreen`
applies them and pops with the settings-saved confirmation. Any single typed
playlist field still means a playlist, so the full validation runs and a
half-filled login cannot silently drop the provider. Either QR code can now
change a setting; only a typed playlist adds one.

Two rules keep a short visit from doing more than was asked:

- The device's current values travel in the URL query
  (`phoneSettingsSnapshot`), under the same keys the payload uses; the look
  keeps its existing `p`/`s`. Both forms open on them, so sending after
  changing one row leaves the rest alone — and the setup form's clock, scores
  and update choice no longer start from hardcoded defaults either.
- `phoneSettingKeys` is the one allow-list for both payload modes and
  `applyPhoneSettings` the one writer. `PairingKind.playlist` refuses a
  `settings` payload and `PairingKind.settings` refuses a setup payload, so an
  old code still on screen can neither add a playlist nor write a preference
  its page never offered; `PairingKind.setup` accepts both, because its page
  can now send either. An unknown value inside a known key (a palette or a
  buffering preset from a newer build) is ignored rather than fatal.

`test/phone_settings_test.dart` covers it: all fifteen keys land in storage and
in the live preference objects, a payload of values this build does not know
changes nothing, the payload parses with no playlist fields, the snapshot
round-trips through the allow-list, the session kinds refuse each other, and
the screen renders with no `PlaylistManager` provider at all.

Two pieces of the phone path stopped waiting on work that is not the viewer's
business. The page is read once per process and only when a phone first asks
for it, so opening a code no longer loads 55 KB that may never be fetched; and
a channel change goes through `setChannelLocally` rather than the updater's
`setChannel`, whose release-feed check used to sit between tapping Send and the
confirmation screen — with a slow network the phone could sit on "Sending…"
until the session expired.

## Gold Rush: black first, gold for focus, scarlet for everything else

The 49ers palette (`gold_rush`) is a true-black palette like Lime black and
OLED, but its two accents are not interchangeable. Gold carries the focus
ring, the focused text and the selection, because that is the one accent a
viewer has to read from ten feet and the team's scarlet does not survive it:
`#AA0000` on pure black is under 2.5:1, so a focus border in it disappears.
Scarlet is therefore lifted to `#E03A45` (4.9:1 on black) and kept to badges,
the swatch's second bar and secondary gradient stops, where it reads as the
team colour without competing with focus. The scheme is explicit rather than
seeded — `trueBlack` already bypasses HCT — so the phone page's CSS carries
the same values, and scarlet doubles as that page's error tone rather than a
third red being invented for it.

## Stadium Night is a look, not a palette

Direction B first shipped as a colour palette and read as "different colours,
not a new look" — correct, because colour is the one dimension every install
already changes. The look now lives in `SurfaceTokens` as a third
`SurfaceStyle`, which is where geometry already lived:

- **Shape**: 18/12/14 radii turn rows, chips and settings tiles into pills.
- **Focus**: `focusRingOnly` keeps the resting surface and shows focus with a
  2px ring plus a 22px halo, instead of Classic's accent-fill slab. This is the
  single change that most reads as a modern streaming UI on a TV.
- **Type**: `uppercaseLabels` + tracking for section headings, `titleWeight`
  w800 for team and fixture names, `scoreSize` 19 for scores, and tracked caps
  for status words (LIVE, FINAL); sentence-case legacy stays untouched.
- **Colour** is still the separate `Lime black` palette (`stadium_night` id).

Widgets read tokens instead of hardcoded values so nothing else in the layout,
focus order or data path moved: `settings_section`, `tv_menu_tile`,
`live_navigation_body`, `sports_widgets` (chips) and `sports_fixture_row`.
The look is opt-in; Classic and Modern are byte-identical to before.

The palette label had to change from "Stadium Night" to "Lime black" once the
look took that name — two entries with identical labels made the row
ambiguous on screen and in tests.

### The look reaches every screen through the theme, not per-widget edits

The first pass only converted the Sports hub and settings, so dialogs, the
player sheet, chips, inputs and menus kept their own baked-in radii and
rendered as a hybrid. The fix is at the top: `buildAppTheme` now takes the
`SurfaceStyle` and builds dialog, card, chip, popup-menu, tooltip, snackbar,
input and button shapes from the tokens, and `withTvThemeIfNeeded`, the root
`MaterialApp`, the TV home shell and the library shell pass the saved style
through. A screen that never mentions tokens still follows the look.

Everything below the theme that owned a surface was then converted with
`lookTokens(context)`: settings tiles and section cards, the bottom bar, mode
buttons, player dialogs/rows/actions, search headings and empty state,
transfer error cards, poster cards and sports detail cards. Each conversion
uses `rounded ? token : legacyNumber`, so Classic and Modern keep the exact
pixels they had — asserted in `test/surface_style_test.dart`, which checks
Classic dialog 12 / card 10 / chip 8 and no dialog title style, alongside
Stadium's 22 / 16 / 18 and its w800 title.

Scores and records are wrapped in `Flexible` + `FittedBox(scaleDown)`: the
19px score, or a long record, shrinks to the card instead of clipping. The
same test renders the card at 320px — the tightest of the four layout sizes —
with three-digit scores and asserts no overflow plus the w800 title and 19px
score, so the look cannot regress into a palette swap.

## RadioGroup traps a TV remote

The update channel picker shipped as `RadioGroup` + `RadioListTile` and had
to be reverted to plain `TvMenuTile` rows: the group's shortcuts map
Up/Down (and Left/Right) to intra-group selection with wraparound, so on a
remote — where Up/Down *is* focus traversal — pressing Down on the last
option wrapped back to the first instead of leaving for Download/Install
below. The codebase's standing rule for exclusive choices on TV is one
ordinary focusable per option with document-order traversal (`ModeButton`'s
doc comment); the leading radio icon now carries the selected state so the
rows keep their radio affordance without the group's key handling.
`test/app_update_channel_test.dart` walks Down out of the section with
arrow keys so a regression traps the test instead of the viewer.

## A beta install was never offered the next beta

The channel defaults to Stable, and nothing recorded that an install came
from `beta-latest`: both channels download the same bytes, and promotion
republishes those bytes unchanged, so the APK cannot carry the answer. A
tester who installed `StreamSports-early.apk` therefore followed the stable
feed, whose newest build is the last promotion — behind the build that
tester runs. The startup prompt only offers something
*newer* than the installed build, so it never fired, and the only way to
get the next beta was opening App updates and switching to Early builds by
hand.

The fix adopts Early on the first check whose stable mirror is behind the
running build. That reaches exactly that population: stable is never older
than a stable install, so nobody who never opted in can be offered a beta,
which is what the channel default exists to guarantee. The adoption is
written to storage as a real choice, so it survives the promotion that
lifts the stable build to the tester's number (a detection remembered only
for the moment would flip back to Stable exactly then), and it never runs
once a channel was chosen, so a tester who picked Stable keeps it. Two
alternatives were rejected: a build-time flag (the promoted bytes are the
same file, so every stable viewer would inherit it) and always checking
both feeds and offering whichever is newer (that prompts non-testers for
betas).

## Update offers name their channel

The roadmap required that a user can tell from the prompt whether a build is
early or promoted. `AppRelease` carries `isEarly` from whichever rolling
release it was read (`beta-latest` vs `stable-latest`), and both the startup
prompt and the App updates status show a Stable/Early build line under the
version. One alternative was stuffing the channel into the versioned release
notes, but the notes are written at cut time on beta when the channel isn't
decided yet — the rolling release is the only thing that knows. The seven
channel strings ship with real fr/es/it translations instead of joining the
untranslated fixture, since an opt-in screen that shows English to half its
audience defeats its own purpose.

Decisions that shaped the code, and the alternatives that were rejected.

## Leagues and teams in one screen

The league picker was a flat list of the whole catalogue (213 competitions), so
choosing a sport meant scrolling past every other sport, and followed teams lived
behind Standings with an add flow that required picking a league, waiting for its
table, then finding the team in it.

Three shapes were considered:

1. **A sport tree with a Teams tab** (built). Sports are rows that open in place;
   only sports that already show a league start open. Search flattens the tree so
   a rare league is still one query away. Teams are the second tab: the followed
   list, plus an add flow that walks sport → league → every team the league lists.
2. **One three-level tree** (sport → league → team). Neatest, but the deepest
   level loads over the network, and a lazily-loaded third level is the hardest
   thing to drive with a D-pad and to keep focus-stable.
3. **Two screens behind one entry.** Least work, but keeps the split the design
   was meant to remove.

The tab shape won because each tab stays a flat, fixed-height list — what
`CompactChoiceList` and its remote navigation already handle well — and the team
list loads one league on demand instead of scanning everything.

Ordering is `sportDisplayPriority` (US football, basketball, baseball, hockey,
soccer, then the rest alphabetically); within a sport it stays
`leagueDisplayPriority`. `sportsStandingsLeagues` moved into
`lib/utils/sports_presentation.dart` so Standings and the team picker can never
offer different leagues.

Bulk "Show/Hide listed" acts on the open sports only, which is why a closed sport
can never be changed by accident. Hiding everything remains a draft: an empty
selection is never persisted, and Restore selection brings back the last saved
set.

## A conference pick reads its conference

College conferences are stored as separate leagues bound to a scoreboard group
(`espnGroup`) and keep `hasStandings: false`, because they reuse the parent
competition rather than owning a feed. The team picker inherited that literally:
it asked for the sport's team directory, so "SEC Football" listed every college
football team ESPN knows (763 of them, across every division).

ESPN's standings endpoint honours `group` (`/standings?group=8` returns the SEC
alone, 16 rows), and the parameter survives the season retry. So a league with
an `espnGroup` now reads grouped standings, and it is never allowed to fall back
to the whole-sport directory — an honest empty list beats 763 wrong teams. The
same rule fixes Standings when a conference pick is selected there.

Poll views (Top 25) stayed out of this: they filter games by rank, not by a
roster, so Add team does not offer them as team lists.

## A My Teams row, not a pinned strip

Followed teams already sorted first inside each sport row, but the viewer still
hunted row by row. A separate strip pinned above the list was considered and
rejected: it needs its own focus zone (up into it, down out of it), which is the
exact plumbing that caused the Teams-tab focus bug, and it holds screen space on
days none of your teams play.

So My Teams is a synthetic first `_Section` in the grouped Events list, built
from the same games the sport rows show. It rides the existing row focus, scroll
and lazy-build machinery unchanged — up from the first sport row lands on it, up
again reaches the toolbar — and it vanishes on team-less days so the rows below
never shift for an empty strip.

Duplicating cards across rows forced one piece of new plumbing: two rows shared
a card's focus node and widget key, and a focus node can only belong to one
row. Only the My Teams row gets section-scoped card keys (`my-teams:<game>`);
every other row keeps the plain game key, so existing navigation and tests are
untouched. The heading is the same exception: it carries a star and drops focus
into its first card instead of selecting a sport.

The in-player Scores panel needed nothing structural either: its Up/Down scope
cycle (Live, All, each sport) already skips empty scopes, so My Teams is one
more scope with a followed-team predicate, hidden when nothing is followed.

## A Live Sports row is named for the game, not the channel

The pinned category listed the channel each followed game is on, so a golf
afternoon read "GOLF CHANNEL HD" down the list and nothing said which
tournament was being played. The row's name is now the game's own title - the
tournament from the provider's event name ("RSM Classic"), or "Away at Home"
for a team game.

The second line was the channel's EPG programme, which describes the feed and
not the game: a golf tournament read as whatever the cable channel had
scheduled. It is now the game's own state - the score, then the clock with who
has the ball ("BUF 17-14 · Q3 4:12 · 2nd & 7 at NE 32"), or for a field
event the leader ("Round 3 · Leader · S. Scheffler · -12"). Hiding scores
keeps the clock and drops the possession line, the same spoiler gate the sports
cards use, so following a team never leaks its score from the guide.

`LiveSportsChannels.titleFor` owns the substitution and returns null for the
Sunday lead channel and for anything that is not a live game, so RedZone (a
channel, not a fixture) and every other category keep their channel names. The
Timeline Guide's label column and the fast-browse banner read the same method,
so the category is named one way in all three places.

The guide's timeline carried the channel's EPG title and nothing else, so a row
named "Northwestern at Virginia Tech" while the game sat at 48-68 told the
viewer only who was playing, and a game with no EPG entry (tennis on a channel
the guide has no schedule for) was a "No program data available" block. The
block covering now reads the score first and the game second, and stands in for
the missing programme where there is none.

Only the block airing now carries it: a score is a fact about the minute it was
read, so stamping "48-68" on the row's evening programmes would claim they are
being played at that score. The block order is deliberate too - a two-line block
has room for two lines, and a game name long enough to wrap would push a score
placed second out of the block entirely.

The score in the label column is its own line above the name. It started as a
tag in the playlist slot, which is a pill drawn over the name and 12dp of top
padding, so a two-line column clipped both; set beside the name it also ate a
third of the 152dp column, leaving the name too little to say which game it
was. A landscape row is 36dp and holds the score plus one line of name, so the
name loses its second line there.


## A stopped cut puts its own bump back

The release script edits `pubspec.yaml` and `CHANGELOG.md` before it builds, so
a run that stopped at the APK audit left both files bumped with no release
commit behind them. The next cut refuses to start on a dirty tree, which meant
discarding the leftovers by hand every time - and forgetting that step left the
retry building a version nobody had released. The script now captures both files
before the bump and writes them back if anything fails before its release
commit, staged copies included, so a retry starts exactly where the failed
attempt did. Once the release commit exists the bump stays: that is what makes
the tag, the CHANGELOG entry and the version inside the APK agree.


## The guide's block names both sides, and the label column stops repeating it

"MAN 32-51" fit the block but asked the viewer to decode a box score, and the
same fact appeared twice: the cell's score line and an orange score line above
the game's name in the label column. The cell now reads "Manhattan 31 / Miami
52" - both sides spelled out, away first to match the row's own "Away at
Home" - with the winning side's score in bold, then the clock and who has the
ball on the second line.

Giving the cell the game's title as well is what cut it off at the block edge:
"MAN 32-51 * 15:00 * 1st" plus "Manhattan at Miami" is three lines of text in a
two-line block, and the overflow landed on the score. The title left the cell
because the label column already names the game, so the two now divide the
work: one says which game, the other says what the game is doing.

Bold is a span, not a second string: `guideLines` returns each line as
(text, strong) segments and the block renders them in one `Text.rich`, so the
winning score is set apart without the cell parsing scores. The names come from
the same `shortName` the row title uses, which keeps "Thunder 31 / Lakers 52"
consistent with "Thunder at Lakers" beside it.

The score line is first for the same reason it always was: a long game name
wraps, and a wrapped second line ellipsizes the tail of the block, not the
score. A block with no score at all - tennis, golf, a game before it starts -
puts its status and leader on that first line instead, and hiding scores leaves
the status alone.

Live Sports no longer passes a label status. `selectionStatus` was doing two
jobs - the Multiview picker's "In use" tag, and "these rows are games" - so
dropping the score needed a separate `liveSports` flag rather than a callback
that always returned null.

## A stall waits 3 s before the main player resumes, but never a channel change

The main player started, and resumed after a stall, at media3's 500 ms. That
keeps channel changes fast, but live TS arrives at real-time speed: after a
stall the buffer is empty and refills at 1x, so 500 ms of media runs out again
at the provider's next gap and every hiccup becomes a stutter loop instead of
one clean pause. Multiview already waited 4 s for the same reason.

The floor lives in `LiveBufferLoadControl`, not in the DefaultLoadControl
thresholds. Raising `bufferForPlaybackAfterRebufferMs` there would also apply
to a viewer who chose "Small (1.5 s)", because the delegate keeps its own
larger threshold after the reserve is met - a settings screen would be
advertising a number the player ignores.

So the wrapper now tells apart three things it used to collapse: Off, Gradual
and a chosen reserve. It keeps the raw setting (negative is Gradual) instead
of storing both as zero, and the constructor records whether a Buffering
preset is set, since a preset already brings its own resume threshold and the
floor must not add to it. The floor applies only when all three hold: Live
buffer Off, no preset, and media3's rebuffering flag, which is false on the
first start and after a seek, so channel changes and scrubbing stay at 500 ms.
The byte-budget escape hatch is untouched, so a RAM-capped device still starts
when the delegate's budget says it must instead of waiting for media it can
never hold.

The trade is deliberate: a real stall shows Buffering for up to about 3 s on a
link that delivers at 1x, rather than flickering through repeated short
rebuffers.

## A followed team belongs to its competition, not to the league view

Favorites are stored as `leagueId|teamId`, and matching a game was exact: the
game's league id had to equal the stored one. College football breaks that,
because one competition is browsable through several ids - the full College
Football list, and each conference pick ("ACC Football", "Big Ten Football")
that narrows it by ESPN group - and the same game is labelled with whichever of
them the viewer shows. A team saved from the ACC table then vanished from the
College Football list, and one saved from the College Football list vanished
from the ACC list. Two favorites could show as one, alternating with the
leagues that were shown.

`SportsLeague.parentLeagueId` already records that a pick narrows a full list
(the league manager uses it so a pick and its parent are never shown together).
Favorites use the same relation through `sameSportsCompetition`: an exact id
still wins, otherwise a conference or poll pick and its full list count as one
competition and the team id decides. Nothing widens past that relation, so the
same numeric team id in another sport stays unfollowed - ESPN reuses ids across
sports.

The team picker's tick marks stay exact on purpose. They report whether this
league's own entry exists, and its toggle writes that entry; widening the tick
would let a tick unfollow a different id and appear stuck.


## The device transfer said "did not answer" for three different failures

Four faults sat behind that one red box on the sending screen.

The search was a fixed ten seconds: probe, wait 8 s, probe again, wait 2 s. A
receiver normally answers in one or two, so its row appeared at once and then
stayed disabled behind a spinner (`enabled: !_busy`) for the rest of the window.
`discover()` now returns on the first offer; the socket keeps listening
afterwards, so a device that answers later still reaches the live list without
another search. The repeat probe stays, one at 3 s while nothing has answered,
because a dropped broadcast is the reason a receiver goes unseen at all.

Starting Receive twice, or switching roles, left the previous receiver holding
the discovery port. The new receiver lost the bind inside `_openDiscovery`'s
catch and kept only its HTTP server, while the old one went on advertising a
session the screen no longer drove - so a tap was refused, or the approval woke
a session nobody was watching. `_stopListening()` now tears down whichever role
was running before either starts, and one sender owns the list after Search
again.

The sender's timeout sat ten seconds past the receiver's approval window, too
little slack for a cheap box to write its answer, so a decline could arrive
after the sender had given up and been reported as silence. It is thirty seconds
now, which lets the receiver's own answer win.

Every handshake failure shared one sentence. `handshakeFailure()` separates a
refused connection ("that device is no longer waiting"), a silent receiver ("did
not answer in time") and a rejected request, with its status code. A refusal is
the tell for a receiver whose screen is gone, silence the tell for a suspended
one; neither is timing, which is why the first reports could not be reproduced.

## A transfer list where both devices were "This device"

The receiver advertised the hardcoded name `'This device'`, so the sender's list
showed a row that read like the phone in your hand. Both roles now ask a
`deviceName` method on the existing device channel: Android's own device name
(what Android TV's Device name setting writes), else manufacturer and model,
with an "unknown" maker or model treated as empty. `DeviceTypeService` exposes
it as `transferName()`, which never returns null - `unnamedDevice` is "Android
device" - because a fallback that reads like the local device is the confusion
being fixed. The constructor defaults use the same name, so no path can produce
the old row.

## A transfer approval outlived by its request

Accepting the code on the receiving device could still end with "that device is
no longer waiting" on the sender. The sender held one POST open for the whole
two-minute approval window, so everything between acceptance and success was
that single TCP connection surviving the walk to the other device: a phone that
locked, a Wi-Fi power save, or a box that dropped the idle socket took the
answer with it, and the sender reported the loss as a device that had stopped
listening. The receiver had answered - its answer went nowhere.

The approval now lives on the receiver. A hello that asks for it (`poll: true`)
is answered at once with `pending` and the code, the sender asks `/status` every
second on a fresh connection, and the receiver keeps the approval until it is
used, declined, or the window closes. `_startApprovalClock` ends it by itself,
because nothing waits on it any more. A dropped poll costs a second, never the
transfer.

Both old directions still work: a hello without `poll` takes the original
blocking path, and a reply without `pending` is read as a final answer, so an
older build on either side transfers as before. The code, the X25519/AES-GCM
keys and the single-use approval are unchanged.

## A reset that arrived before the approval did

The 0.2.93 report was a sender that failed seconds after the code was accepted,
not minutes, so the approval was never the thing that timed out: the connection
died while the request was in flight. Two gaps came out of that.

The sender treated a dead hello as a device that had stopped listening, when it
could equally be a reset after the request had been read. The approval now
lives on the receiver, so after a socket failure the sender asks `/status` once
before giving up: if the other device is holding the approval, the transfer
continues and nothing is lost. Only a device that does not answer at all is
reported as gone.

The refusal also hid its cause. `handshakeFailure()` now appends the OS reason
in one short line - "Connection reset by peer", "Connection refused",
"Connection closed before full header was received" - because those point at
different faults: a reset means the request landed and the answer died, a
refusal means nothing was listening on that port. One sentence for both left
the field reports unreadable.

## The league category beat the channel that was actually airing the game

A Saturday board of college football games all named one channel: the provider's
"NCAAF 01", while the scoreboard said each game was on a real network. The
channel the scoreboard listed was found, too - it just lost. Two orderings did
that, and neither was the score anyone could tune into.

The evidence rank put a channel's own category above a guide programme. A group
named "NCAAF" matched every college football game at once and scored 340, while
the FS1 slot that read "Rutgers at Penn State" scored 500 but sat one rank
lower. The category is a guess about a whole league; the guide listing is proof
about one game. Guide now ranks above category, and the category still ranks
above the generic league/sport fallback.

The second defect was the merge. A game's evidence is collected per channel and
the old rule kept whichever hit had the larger score, carrying its reason along.
A channel that was both a listed broadcaster (250, rank 2) and a guide airing
(500, rank 4) came out of that merge as the weaker kind, so the scoreboard's
listing was thrown away exactly when the guide agreed with it. The merge now
compares the kind of evidence first and the score second, and keeps the
programme found on the way for display.

The picker also offered the league label before the broadcaster in its search
chips, so "NCAAF" was the term staring back at a viewer who needed "FS1". The
broadcasters are now first, because they are the only suggested term that names
one feed rather than every feed in a league.

Measured before the change on a synthetic playlist (FS1 plus two "NCAAF" group
feeds, Rutgers at Penn State): with the FS1 guide slot present the order was
NCAAF 01, NCAAF 02, FS1 (guide, 500); with the scoreboard listing also present
FS1 still came out as a guide hit rather than a broadcaster. After it, FS1 leads
as the guide airing, and as the listed broadcaster when the scoreboard names it.
