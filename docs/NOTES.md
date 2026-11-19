# Design notes

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
body and decoding flags are asserted once. The standings service still has its
own if-chain; converting it to the same shape is the next slice, and it is
harder because ESPN supplies teams there and several leagues enrich those with a
second source.

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
