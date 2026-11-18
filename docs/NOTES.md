# Design notes

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
