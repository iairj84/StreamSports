# Scores panel scope memory + My Teams spoiler mode — design

## Intent

The in-player Scores panel always reopens on Live (or All), even when the viewer spent last night in My Teams. And the only spoiler control hides every score, so a fan who checks other games still gets their own team's final spoiled. Remember the last scope, and let My Teams games hide their scores alone.

Who: TV-first viewers who follow 1-5 teams, check the panel mid-game or next morning.
Why: stop re-picking My Teams every open; let fans browse the league without ruining their own game.

## Goals

- Scores panel reopens on the last picked non-empty scope (LIVE, All, My Teams, sport). Empty remembered scopes fall back to the current Live-first rule.
- Watching-game landing still wins: opening while a game is playing lands on that game's card, as today.
- New toggle "Hide My Teams scores": when on, any game involving a followed team shows no score (records for pre-game, time/status for live/post, same as global hide) while all other games show scores normally.
- Both settings persist across restarts per viewer (existing `_vk` namespacing).

## Non-goals

- No change to Events My Teams row placement, filters, or hiding rules.
- No change to global Hide scores / Show odds behavior.
- No auto-spoiler by game state, no per-team toggles, no notifications.

## Constraints

- D-pad: scope change stays Up/Down, spoiler toggle must be reachable without breaking the card-row focus order.
- No new focus model; reuse existing `_changeScope` empty-skip logic.
- American spelling in UI strings.

## Approaches considered

### Scope memory

- **A. Remember last scope label (picked).** Store the label string (`LIVE`, `All`, `My Teams`, sport id) like card size / hide-scores. On open, restore it when that scope exists and has games; else Live-first fallback. Survives restarts, degrades cleanly.
- **B. Remember only My Teams preference (rejected).** Single bool is simpler but forgets sport scopes the viewer may live in.
- **C. Session-only memory (rejected).** Cheapest, but re-asks after every restart — the exact TV annoyance being fixed.

### My Teams spoiler

- **A. Global hide (rejected).** Already exists; hides everything, not what was asked.
- **B. Hide My Teams scores only (picked).** New `hideMyTeamsScores` key, default off. Predicate: `follows.involves(game)` gates score display in the Scores panel cards (and the Events My Teams row cards, same predicate, so the spoiler cannot leak one screen over). Other games untouched. Not complicated: one bool + one `involves` check at the two card render sites.
- **C. Finals-only auto-hide (rejected).** Unpredictable; viewer never knows what they will see.

## Decisions already made (with the requester)

- Scope memory: approach A.
- Spoiler: hide only My Teams games, as a toggle (approach B above).

## Builder calls (open to correction)

- Storage: add `keySportsScoresScope` (string label) + `getSportsScoresScope/setSportsScoresScope`, and `keySportsHideMyTeamsScores` (bool, default false) + getter/setter in `AppConstants` + `StorageService`, viewer-namespaced via `_vk` like hide-scores.
- Scores panel: on `_load`, after ordering, prefer remembered scope when `_scopes` contains it and `_games.any(scope.accepts)`; watched-game landing overrides when it matches. Persist in `_changeScope`. Header adds Hide-My-Teams toggle chip beside LIVE/All (TV-focusable, localized via `tr`).
- Events: My Teams row cards (and Scores panel cards) pass `hideScores: hideMyTeams && follows.involves(game)` ORed with global `_hideScores`.
- Tests: scope-memory test (remembered My Teams restored, empty fallback to Live) + spoiler test (followed game hides score, unfollowed shows). Extend `sports_my_teams_test` or the scores-panel harness.
- Docs at build time: CHANGELOG dated line, docs/NOTES.md entry (why), README only if the Scores description changes.
