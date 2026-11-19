# Design notes

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
