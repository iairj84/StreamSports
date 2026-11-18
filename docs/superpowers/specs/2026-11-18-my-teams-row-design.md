# My Teams row — design

## Intent

Followed teams' games are scattered across the per-sport Events rows (they
sort first inside each row, but the viewer still hunts row by row). A single
**My Teams** row at the top of Events puts every game involving a starred
team in one glanceable, one-press place on the TV remote. The same idea
applies to the in-player Scores panel, whose Up/Down scope cycle (LIVE, All,
each sport) has no followed-teams view.

## Goals

- Events (grouped-by-sport view): a `My Teams` row sits above the sport rows,
  built from the same game cards and the existing row focus/scroll machinery.
- The row follows the selected day and the time and channel filters, and
  ignores the sport/league filter (your teams, wherever they play).
- Games stay in their sport rows too; following a team never removes a card
  from below.
- The row hides entirely on days none of the followed teams play.
- Player Scores panel: a `My Teams` scope joins the Up/Down cycle, showing
  only games involving followed teams (empty scopes are already skipped).

## Non-goals

- No changes to Schedule, Standings or Replays views.
- No new focus/navigation model; no reordering inside existing rows.
- No change to what "followed" means (`SportsFollows.involves`, league-scoped).

## Constraints

- D-pad navigation must keep working: up from the first sport row lands on
  My Teams, up from My Teams reaches the toolbar (existing `_moveEventRow`
  handles any first section generically).
- Section ordering and caching in `_sections` must stay consistent; the row
  participates in the same `sourceKey` invalidation (follows revision is
  already part of it).

## Approaches considered

- **A. Synthetic first `_Section` (picked).** Built in `_makeSections` for the
  grouped view from `_scopedGames(favorites: false)` filtered by
  `_follows.involves`, ordered live → upcoming → final. Zero new focus code.
- **B. Pinned strip above the rows (rejected).** A separate widget needs a new
  focus zone and stays on screen when empty — the exact plumbing that caused
  the recent Teams-tab focus bug.
- **C. Promote the Favorites filter (rejected).** Replaces the sport rows
  instead of sitting above them; not what was asked for.

## Decisions already made (with the requester)

- Approach A; duplicates stay in sport rows; day + time/channel filters apply;
  sport/league filter ignored; hidden when empty. Scores panel gains a scope.

## Builder calls (open to correction)

- Section id `my-teams`, label `My Teams` (localized via existing `tr`).
- Grouped-by-sport Events view only. When a sport or league filter is active
  the list already switches to Live/Upcoming/Final sections; no My Teams row
  there — the filter itself is the narrowing.
- Scores panel: `My Teams` scope sits right after `All` in the cycle; default
  landing (Live when anything is live, else All, else watched game) unchanged.
- Tests: extend the sports follow/Events tests (row present and first, only
  involved games, absent when no team plays) and add a Scores-panel scope
  test if the harness allows it.
- Docs at build time: CHANGELOG dated line, docs/NOTES.md entry (why),
  README if the Events/Scores description changes.
