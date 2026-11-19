# Design notes

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

What stayed out: league and team picks, the language, and playback
buffer choices. They need live catalogue data or a restart to take effect,
and the point of this screen is the five-minute path from install to a
picture. Hidden-channel and rename flows keep their own QR codes, because
they act on a catalogue that does not exist yet at first run.

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
