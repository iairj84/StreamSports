# Changelog

## 0.2.91 — 20 November 2026

- The update prompt now reaches testers running an early build: an install whose build is newer than the stable mirror is recognised as an early build and follows Early builds on its own, instead of being compared against a stable feed that is always behind it.
- A channel you pick yourself is never changed, and a viewer who never opted in is still never offered a beta.

## 0.2.90 — 20 November 2026

- A favorite college team now counts in every view of its competition: a team saved from the ACC or Big Ten list shows in the full College Football list, and a team saved there shows in the conference list. Before, two favorites could show as one depending on which leagues you had selected.
- The same rule covers Top 25 views and college basketball, and a team id that happens to repeat in another sport is still not treated as your team.

## 0.2.89 — 20 November 2026

- A live channel that stalls now waits for three seconds of video before it resumes, so one dropout is one short pause instead of a loop of micro-stutters.
- Channel changes, seeking and a first start still begin at once, and a Buffering preset, a Live buffer reserve or Gradual mode keeps its own threshold.

## 0.2.88 — 20 November 2026

- The Live Sports guide names the game in its block now: "Manhattan 31 / Miami 52", away first, the winning score in bold, then the clock and who has the ball - instead of "MAN 32-51 * 15:00 * 1st" over a repeated game title that ran past the block.
- The channel label drops its orange score line, so the game's name gets both lines of that narrow column, and the score lives only in the guide.
- A tennis or golf block without a score reads its round and leader instead, and hiding scores leaves the clock on its own.

## 0.2.87 — 20 November 2026

- The Live Sports guide shows the game now: the score sits above the row name, and the block airing right now leads with it - "NU 48-68 · Q3 4:12" - then the game itself, instead of a programme title that only named who was playing.
- Games the guide has no schedule for, tennis included, read as the game and its score instead of "No program data available", and only the current block carries the score, so later programmes are not painted with a score from an hour ago.
- Cutting a release no longer leaves its version bump behind when it stops before its release commit, so a retry starts from the same version instead of refusing a dirty tree.

## 0.2.86 — 20 November 2026

- Live Sports rows are named for the game now: a golf afternoon reads "RSM Classic" instead of "GOLF CHANNEL HD" three times, and the line under it is the game rather than the channel's EPG - "Round 3 · Leader · S. Scheffler · -12", or "BUF 17-14 · Q3 4:12 · 2nd & 7 at NE 32" for a team game. Hiding scores keeps the clock and leaves out the possession line, and the Sunday lead channel keeps its own name because it is a channel and not a fixture.

## 0.2.85 — 20 November 2026

- Releases cut in well under half the time: the release gate no longer reruns the 94 layout and navigation cases locally. CI's four-shard matrix has already run them on the pushed commit, and on the release machine that step was the entire gate (177-182s) while covering nothing the release commit changed.
- Both privacy audits stay in the local gate because CI runs neither of them, and a cut carrying Dart changes CI has not seen still passes the focused tests through the same gate.
- `tools/preflight.py` with no test files now runs the analyzer and both audits alone. It used to start `flutter test` over the whole suite, which is the form the project's own rules forbid in one checkout.
- The layout test suite is split into seven focused files, so its cases run in parallel instead of one 253s file setting the gate.
- `docs/NOTES.md` records the measurements, including why the version bump cannot move after the build: the bump invalidates Flutter's AOT compile, and a release carrying Dart changes pays that compile either way.

## 0.2.84 — 20 November 2026

- The release checks now run at the same time. `tools/preflight.py` starts the analyzer, the focused Flutter tests and both privacy audits together, prints each one's wall time as it finishes and fails with that check's own output; the gate that took 485s in sequence measured 317s.
- `docs/development.md` and `docs/release.md` show the one-pass gate, and `docs/NOTES.md` records the measurements, why the saving comes from overlap rather than parallel `flutter test`, and the next lever (the 253s live-layout test file).

## 0.2.83 — 20 November 2026

- Live TV's groups column gains a pinned Live Sports category above the playlist groups: one row for each live game in your followed leagues and teams, on the channel Sports would start for it, followed teams first.
- It loads when opened and rechecks on every open, says so while it looks, and shows a plain "no live games" line when nothing is on rather than an empty guide.
- Each row carries its game's score under the channel, or the game clock when scores are hidden, and keeps it current while the category is open.
- On NFL Sundays the playlist's own RedZone channel leads the category when it carries one, since that afternoon is on that one channel.

## 0.2.82 — 19 November 2026

- **Fixes**
- Search results are ordered by evidence: your explicit pick, then the card's confident match, then anything that answers what you typed, and only then the card's weak guesses. The previous change put every typed hit above every card channel, which buried a channel you had picked for the event under any channel whose name contained the word.

## 0.2.81 — 19 November 2026

- **Fixes**
- The channel picker now searches the same evidence as the live guide. Typing a network the card names (for example CBSSN) found nothing when the network only appeared in the listing's synopsis, because the picker read programme titles alone; it now reads title and synopsis, as the guide search always has.
- A row the query actually answers now outranks the card's own low-confidence guesses. Searching a network no longer puts an unrelated programme that merely mentions the sport above the service itself.
- **Internal**
- docs/NOTES.md records why the picker reads listings and why seeded evidence sorts below query hits; the day-window fallback stays title-only because it reuses the guide store's title index.

## 0.2.80 — 19 November 2026

- Standings for the leagues that publish their own table (B.League, NPB, KBO, ABL, EASL and both K League divisions) now come from one table instead of a per-provider chain of ifs, so the season rule and the ABL's previous-season retry are declared with the request they belong to. Same requests, same seasons, same tables.
- ESPN's own standings and enrichment pipeline (field hockey, World Rugby, the rugby competitions, NPC, the NCAA soccer polls) stays explicit because it composes rather than dispatches, and MotoGP keeps its own source because a class table needs a season lookup first.

## 0.2.79 — 19 November 2026

- Adding a scoreboard league is one entry in a feed catalogue instead of edits in six switches. lib/services/scoreboard_feeds.dart now declares each provider's request, POST body, size cap, decoding, cache window, schedule strategy and parser; the ESPN parser moved to its own library so sports_service is about fetching and caching only.
- No behaviour change for any league: same feeds, same cache keys, same expiry rules, same parsers. An unknown or newer-build league source still reports as unsupported instead of requesting a path this build cannot score.

## 0.2.78 — 19 November 2026

- AUD-002: the app no longer participates in Android backup, so a provider login cannot be copied to Google's backup transport or a device-to-device migration. Both rule files exclude the whole data set, and SECURITY.md now explains where credentials live and how a configuration moves between devices.
- AUD-003: a failed guide or playlist request no longer publishes the viewer's login. Error text shown in Settings and on the home screen is rebuilt from the provider's host and port, with username/password pairs redacted; provider messages that carry no address, such as an account rejection, read exactly as before.
- AUD-004: an unreadable saved configuration can no longer make the app unlaunchable. Playlist entries that do not decode are skipped instead of failing every launch, and a restore or transfer whose playlist section is unreadable is refused before it replaces a working configuration - as is any payload that tries to write a device-only setting.

## 0.2.77 — 19 November 2026

- AUD-001: device transfer now requires the viewer's approval before applying a bundle, consumes that approval once, resets the handshake after refusal/timeout and closes the listener when the transfer ends. Adds regression coverage for unapproved, replayed, declined and timed-out handshakes.

## 0.2.76 — 19 November 2026

- Add docs/ARCHITECTURE.md: one map of the service graph, storage layers, data flow, build/test commands and beta/stable release flow, linked from the README.

## 0.2.75 — 19 November 2026

- Startup Retry now recovers instead of failing again with a late-initialization error.
- Promoting a beta to stable labels the build from its version tag, so stable devices are offered the promoted APK even when promotion runs from an older checkout.
- CI now analyzes and tests pushes to beta, and the settings navigation test no longer assumes the Multiview row is above the fold.

## 0.2.74 — 19 November 2026

- New Gold Rush appearance theme: true black surfaces with 49ers gold focus and a lifted scarlet for badges, swatches and the phone page's error tone.
- The phone settings and setup pages show Gold Rush as a theme choice and paint themselves in it when the TV already uses it.
- The Themes tile no longer quotes a palette count that goes stale with every new look.

## 0.2.73 — 19 November 2026

- The "Set up from phone" page no longer demands a playlist for a settings change: with every playlist field left blank it sends the theme, surface, clock, scores and update choices alone, and the TV applies them straight away.
- Typing anything in a playlist field still means a playlist, so the full login validation runs and a half-filled provider cannot be silently dropped.
- Either QR code can now change a setting; only a typed playlist adds one.

## 0.2.72 — 19 November 2026

- Settings from phone is its own page: Settings > Settings from phone opens a code that changes the TV's settings and nothing else, so a clock or buffer change no longer asks for a playlist.
- The phone page now covers what a remote makes tedious: theme and surface, clock and language, start-up buffering, live buffer, playback at startup, playlists at startup, picture-in-picture, the resume reminder, the Movies, Series and Multiview rows, hidden scores, and the update channel.
- Both phone forms open on the values the TV has now, so changing one switch leaves every other setting alone.
- Codes appear without waiting for the phone page to load, and changing the update channel no longer keeps the phone on Sending while the app checks the release feed.

## 0.2.71 — 18 November 2026

- The phone page now uses the app's own colours: every palette takes the exact surface, container, outline and accent values the TV's theme builds, and neutrals stay neutral so the accent only marks selection, the primary action and focus.
- Lime black no longer looks like a wireframe on the phone: fields, switches and cards are filled panels with faint hairlines, section labels are tracked caps, the selected chip keeps a ring instead of a fill, and Send is a solid accent button.
- Narrow phones stack the playlist-type chips rather than cutting their labels, the footer sits at the bottom of the sent screen, and the Light palette's selection colour now follows the palette instead of staying Classic blue.

## 0.2.70 — 18 November 2026

- The phone page is now a StreamSports screen instead of a generic web form: it carries the app's name and mark, its Dark grey, OLED, Light, Midnight, Ember, Forest and Lime black palettes, and the Classic, Modern and Stadium Night surfaces, so it matches the TV that showed the code.
- The phone page also picks up the TV's current theme and surface automatically, and choosing a theme or surface in the setup form repaints the page so the choice previews itself before it is sent.
- The playlist form, link box, channel renames and backup transfer were rebuilt on that same set of controls: app-style section labels, settings switches, a pill Send button and a proper sent state.

## 0.2.69 — 18 November 2026

- Set up from phone is now in Settings > Your TV, so a second playlist, a Stalker portal or a later theme change is one scan away without reinstalling.
- The phone setup page also offers the Live/Movies/Series choice per playlist, and a failed setup leaves the code screen up so the details can be corrected and scanned again instead of starting over.

## 0.2.68 — 18 November 2026

- A new install can now be set up entirely from a phone: one QR code carries the playlist plus the theme, surface, clock, spoiler setting and update channel, and the device applies all of it at once and opens ready to watch.
- Stadium Night now reaches the last surfaces that kept their own corners, so multiview thumbnails, category icons, the quality badge, the warm-up banner and picker chips follow the look. Classic and Modern render exactly as before.

## 0.2.67 — 18 November 2026

- Stadium Night now reaches every screen: dialogs, player sheets, menus, text fields, chips, posters and search follow the look's shapes, ring focus and type instead of keeping square corners and accent fills.

## 0.2.66 — 18 November 2026

- Stadium Night is now a real look, not just new colours: Settings > Themes > Surface adds it with pill shapes, ring-and-halo focus, tracked caps for headings and LIVE/FINAL, heavier team names and larger scores across the Sports hub and guide, keeping the same layout.

## 0.2.65 — 18 November 2026

- Settings > Themes gains an opt-in Stadium Night look: true black surfaces with an electric lime LIVE and focus accent across the Sports hub and guide, keeping the same layout.

## 0.2.64 — 18 November 2026

- Update channel options are plain rows again: RadioGroup trapped the remote inside Stable/Early builds so Download/Install below could never be reached.

## 0.2.63 — 18 November 2026

- Update offers now name their channel: the startup prompt and App updates show Stable build or Early build under the version.

## 0.2.62 — 18 November 2026

- Beta and stable release channels: cuts ship from beta, promotions copy the exact bytes to stable, and App updates gains a Stable/Early toggle.

## 0.2.61 — 18 November 2026

- The in-player Scores panel remembers the scope you left it on — Live, All, My Teams or a sport — and reopens there whenever that scope still has games, instead of always falling back to Live.
- Sports options has a new Hide My Teams scores toggle: scores are hidden only for games involving a followed team, and the Scores panel, Events rows, live list, schedule and details all show the record or kick-off time in their place, so switching scope cannot reveal the result.

## 0.2.60 — 18 November 2026

- Events opens with a My Teams row above the sport rows: every game involving a followed team in one place, ordered live, then upcoming, then final. The row follows the selected day and the time and channel filters, ignores the sport and league filters, keeps the games in their sport rows too, and hides on days none of your teams play.
- The in-player Scores panel cycles through a My Teams scope after All, showing only games involving followed teams; the scope is hidden when no teams are followed.

## 0.2.59 — 18 November 2026

- On the Teams tab, pressing up from the first followed team now lands on Add team instead of jumping to Close, so the remote walks up through Add team and the Leagues/Teams tabs in order.
- Add team lists a conference's own teams: picking SEC Football (or any college conference) asks the provider for that conference's standings instead of handing back every known team in the sport, and Top 25 views are no longer offered as team lists since a poll has no roster.

## 0.2.58 — 18 November 2026

- Leagues and teams are managed in one screen now: every competition sits under a sport that opens in place, ordered the way viewers reach for them (American football, basketball, baseball, hockey, soccer, then the rest), so choosing baseball shows baseball's leagues instead of the whole catalogue, and search still finds any league in any sport.
- Followed teams sit beside followed leagues: a Teams tab lists who you follow, Add team walks sport, league and then every team that league's table or team directory lists, and removing a team offers an undo.
- Leaving Sports while a channel or match check was still being written no longer throws that work away, so returning to the hub reuses what it already matched instead of re-checking the board.

## 0.2.57 — 18 November 2026

- Opening the sports hub no longer re-checks the whole board: matches completed earlier in the hour are reused, and a check that has aged only asks for that event to be rechecked instead of blanking its channels, so the card keeps the feeds it already had until a new check replaces them. The guide discovery from the same visit is reused too, so returning does not rescan the day.
- The roadmap now records the planned beta-to-main release channels, with beta builds promoted to main and an in-app option to be offered early builds.

## 0.2.56 — 18 November 2026

- Update playlists at startup refreshes the channels only: the full guide download that followed every launch is gone, and the guide updates on its own schedule, which already runs at launch when its listings are stale.
- After the in-app update finishes downloading, focus moves to Install update, so a remote finishes the update with one press instead of hunting for the button.
- Sports remembers each game's matched channels between launches: the stored-match keys were built from per-process hashes, so every start re-derived the whole board, and entries expired after five minutes. Keys are now deterministic, a match lives as long as its evidence (five minutes on air, half an hour later today, six hours once final), and a guide change still invalidates it.

## 0.2.55 — 17 November 2026

- Back from a sports guide returns the cursor to the category row you picked, instead of jumping to an earlier row in the rail.
- The schedule test suite now passes on Windows machines: the month and day filters are queried by each fixture's local calendar day.

## 0.2.54 — 17 November 2026
- Tennis listings name players as "Sinner, Jannik - Alcaraz, Carlos" again: matching kept reworking the channel name until the commas were gone, so the exact-fixture check never saw them. Renamed channels also fall back to their provider name here.
- The channel picker's search no longer reports "Search unavailable" when only its optional day-ahead guide read fails; names and now/next results stand on their own.
- Formula One coverage is treated as a known feed only once the build-up window opens, instead of flagging a race channel as live coverage an hour and a half early.
- Loading a playlist with no renamed channels no longer reads the whole catalogue twice, which halves that work on very large lists.
## 0.2.53 — 17 November 2026
- One shared OK-button check for TV remotes: the select/enter/numpad-enter/gamepad-A test lived in six copies across five files and is now a single helper, so a new remote spelling only needs adding once. Handlers with deliberately narrower key sets keep their own conditions.
- Workspace cleanup: removed about 100 MB of ignored local clutter (a stale 0.2.32 APK, an already-imported asset drop, and stray build logs).
## 0.2.52 — 17 November 2026
- Translation safety net: a new parity test checks every dictionary key still exists in the code, that {placeholders} match between English and translations, and that new user-visible strings are either translated or recorded. Backup and device-transfer screens fixed three labels that interpolated values before lookup, which had made them untranslatable.
- Continuous integration: pushes and pull requests now run analysis and the full test suite, sharded four ways.
- The patched Android player fork documents its three local changes against upstream 2.12.2 in third_party/video_player_android/PATCHES.md.
## 0.2.51 — 16 November 2026
- Sports hub rows no longer lose focus when the list refreshes or reorders mid-press: if the focused card is gone from its row, the row holds focus instead of letting the key fall through to a distant row.
## 0.2.50 — 16 November 2026
- Sports matching stays warm between hub visits: the title dictionary builds after the first screen and after every guide refresh, the matching worker idles for 20 minutes instead of two on capable devices, and every entry point indexes channels in the same preferred-first order so returning to the hub reuses the index instead of rebuilding it.
## 0.2.49 — 15 November 2026
- The sports picker search now reaches later listings, not just what is on now or next: a typed team that plays tonight shows those streams the same way the main guide search does. Short prefixes keep the instant now-and-next behavior.
## 0.2.48 — 15 November 2026
- Live down and distance gets its own line on sports hub cards instead of sharing the crowded status row, so it can no longer be squeezed off the card. Renamed channels also stay findable: matching now falls back to the provider name underneath a rename when the display name does not fit.
## 0.2.47 — 15 November 2026
- Live football cards no longer lose the down-and-distance line early in games: when ESPN has not composed the text yet, the app builds it from the numeric down and distance, and the short line is used when only that is present. Channel names also gain a Reset all renames button, restoring provider names everywhere for verifying matches.
## 0.2.46 — 15 November 2026
- Sports matching does less guide searching on busy days: team games now retrieve on one side of the matchup instead of every name, so a shared term serves both same-city games at once (each game still claims only its own listings). Guide searches also carry every stored form of each channel id, so mixed-case provider ids can no longer fall silently out of scope.
## 0.2.45 — 14 November 2026

- The sports hub's Live now cards were missing the possession dot and down-and-distance line — they now show who has the ball and the spot, same as the schedule and player score cards.

## 0.2.44 — 14 November 2026

- Catch-up TV for M3U and Xtream playlists: live channels that offer it get a "Watch from start" button in the player (with "Back to live" to return), and already-aired guide programmes play from the archive when opened. Providers without catch-up behave exactly as before.

## 0.2.43 — 14 November 2026

- Live sports cards now show who has the ball: football cards carry a possession dot plus down and distance ("3rd 04:12 · 2nd & 7 at NE 32"), and baseball cards show the count, outs, and runners. The player score cards show the same.

## 0.2.42 — 14 November 2026

- Sports channels fill in faster on slow hardware: when the guide database is busy with a refresh, each check used to wait out the full read timeout again, stacking stalls back to back. The hub now backs off and matches on the in-memory guide instead, retrying the store once it is free.

## 0.2.41 — 13 November 2026

- Sports first opens are faster again: the channel index no longer JSON-encodes and hashes every catalogue row just to fingerprint it, which was seconds of single-threaded work on TV boxes on every cold build.

## 0.2.40 — 13 November 2026

- The Sports loading line now shows live seconds per stage, so a slow device reports whether its minute goes to indexing, guide reading or matching. The single-worker fallback now only applies below 2GB, so 3GB-class TV boxes get the faster overlapped path.

## 0.2.39 — 13 November 2026

- Sports first opens on memory-constrained TV boxes no longer risk a memory-pressure kill (and full restart) of the match: these devices now match on a single worker instead of running a second discovery isolate alongside it, returning the same results with roughly half the peak memory.

## 0.2.38 — 13 November 2026

- Sports first opens are faster on large providers: preparation returns once the channel index is built while guide discovery runs alongside it, concurrent discovery scans share one flight instead of each rescanning, less data crosses to the matching worker, and snapshot change checks no longer re-encode every programme row.

## 0.2.37 — 13 November 2026

- The Sports Hub index now warms up in the background after startup, so the first visit on large providers matches immediately instead of sitting on "Waiting for guide" for a minute.

## 0.2.36 — 13 November 2026

- The Sports Hub no longer restarts matching on guide ticks that change nothing, and it matches on in-memory listings instead of stalling when a heavy EPG refresh holds the database.

## 0.2.35 — 13 November 2026

- Large EPG imports skip programme text outside the retained guide window and reuse sports guide slices during refreshes, so heavy providers load faster and slow the Sports Hub less.

## 0.2.34 — 13 November 2026

- Channel zapping no longer waits on external subtitle files for live streams, and each tune now records where its time goes to guide further speed work.

## 0.2.33 — 13 November 2026

- Sports cards get a consistent type ramp: uppercase letterspaced league labels, bolder team names and event titles, tabular scores that never reflow as the game updates, and a stronger channel action.

## 0.2.32 — 13 November 2026

- Settings > Theme gains a Surface section: Modern rounds rows, cards, guide blocks and dialogs and softens focus to a thin border with a glow, while Classic keeps the current flat look.
- The player quality badge now labels 720p and 480p feeds too and is bigger and easier to read at TV distance.

## 0.2.31 — 12 November 2026

- Sports opens without waiting for every provider's guide: it reads only the channels it checks, so a large secondary guide no longer delays the hub.
- The guide's now and next window is indexed, so startup and the periodic refresh seek a few hours of listings instead of walking the whole store.

## 0.2.30 — 12 November 2026

- The guide wraps at the top too: Up on the first channel jumps to the last, and Menu still opens search.

## 0.2.29 — 12 November 2026

- Playing a game now picks the 4K copy when the provider lists the same feed more than once, while the channel list keeps its usual order and labels.
- The live channel list wraps at both ends: down on the last channel returns to the first, and up on the first drops to the last.
- The player shows the picture quality of the stream that is actually playing, read from the video track rather than the provider's name.
- A manual channel search labels a result as a Search match when the query matches that channel's guide programme.

## 0.2.28 — 9 November 2026

- Sports options adds Show betting lines: the book's spread and total from the scoreboard sit on each game card under the matchup and above the channel, and the preview and game details follow the same switch. It is on until you turn it off.
- Narrowing Schedule to a sport now shows that day's games from the day already loaded instead of requesting it again, so switching between All sports and Basketball is instant; widening still fetches the leagues it is missing.

## 0.2.27 — 9 November 2026

- Clean up names now strips type labels too, such as MOVIE, NEWS or SPT, and Settings > Channel names > Clean up names takes words you add yourself for labels it misses.
- Restoring a backup from your phone works now: the phone page has Save to phone and Restore from phone sides, Backup & restore has a tile for each, and the file you saved shows up in the phone's file picker.

## 0.2.26 — 9 November 2026

- Clean up names can now be reached with a remote: Apply sits above the preview, moving down walks the list of changes, and selecting a row leaves that channel alone.

## 0.2.25 — 9 November 2026

- Channel names can be cleaned up in one pass: Settings > Channel names > Clean up names strips region tags, quality markers and slot numbers, shows exactly what would change, and can undo the whole batch.
- Backups can now travel by phone: Backup & restore > Set up another device saves a backup onto your phone and sends it to another device, which restores it after asking — no computer or account needed.

## 0.2.24 — 9 November 2026

- Channel names can now be edited from your phone: Settings > Channel names shows a QR code, and scanning it opens a searchable list of your channels where new names go straight to the TV.
- College games whose channel shortens each team to three letters, such as "GRA @ 7 TEX", now match the game on the scoreboard.

## 0.2.23 — 9 November 2026

- A transfer or a backup restore now reloads the playlists in place, so the app no longer has to be closed and reopened afterwards.
- Restored channel names are applied in the same pass, so renamed channels show their new names straight away.

## 0.2.22 — 9 November 2026

- Settings, Devices & app adds Backup & restore: save a copy of this device's playlists, settings, sports picks, favorites and channel names, and put one back later.
- Up to five backups are kept on the device; older ones are removed as new ones are written, and restoring asks before it replaces anything.
- Transfer to another device now carries channel names with favourites, hidden channels and channel links.

## 0.2.21 — 9 November 2026

- Settings, Your TV adds Channel names: search your live channels and give any of them the name you want to see.
- A renamed channel shows the new name in the guide, the channel picker and Sports, and the name survives a playlist refresh or a provider update.
- Renaming never changes the playlist itself, and Use provider name puts the original back.
- Sports matching uses the name you gave a channel, so a renamed channel lines up with its games.

## 0.2.20 — 9 November 2026

- Sports options adds a game card size: small, standard or large. The size changes the cards and the rows around them, so remote navigation still lands on the right card.
- Sports options adds a preferred playlist. Games are matched against its channels first; the playlist you browse still covers games it does not carry.
- Playback and preferences now calls the two buffering settings Start-up buffering and Live buffer, with a line explaining that they do different jobs.

## 0.2.19 — 9 November 2026

- Beta releases now publish through one command that bumps the version, builds, audits, tags, uploads the versioned release and refreshes the rolling download.
- The TV installation guide documents the Downloader code for that rolling download, so a box can install without typing an address.
- No app screens or playback changed in this build; the download address and update checks stay the same.

## 0.2.18 — 8 November 2026

- Settings > Devices & app > Launcher icon saves the transparent artwork into Pictures/StreamSports on the device itself, so Projectivy — or any launcher that takes a picture per app — can pick it with "From picture" without a file being copied onto the television from a computer. Four versions ship: the mark and the 16:9 banner, each in white ink for dark backgrounds and in blue for light ones.
- The screen repeats where Projectivy keeps that setting and that turning off Tint custom icons leaves the cut-out colors alone, since the launcher otherwise repaints them.
- Android 10 and later writes the file through MediaStore and asks for no permission at all; older releases ask for storage access at the moment you tap, not at launch.

## 0.2.17 — 8 November 2026

- Every launcher surface now carries the designed artwork instead of the mark this build used to generate: a TV frame with yard lines and an on-field football, in the app's blue. That covers the phone and tablet icons, the adaptive icon and its themed (monochrome) variant, the television and Fire TV banner, and the transparent logos Projectivy uses on its own background.
- The iOS app icon and the web icons use the same artwork, and so does the logo shown inside the app, so nothing in the build is still wearing the old ring.
- The television banner now carries the wordmark, so the app is named on the TV row without relying on the label under the icon.

## 0.2.16 — 8 November 2026

- A channel written "Redzone" or "Red Zone" now counts as NFL RedZone, so an NFL RedZone game finds your provider's channel however the playlist spells it — from the game's channel suggestions and from the channel search alike.
- A provider's own team short codes now match ESPN's: a feed whose guide reads "ARZ @ SEA" finds ESPN's "ARI @ SEA", and the same holds for Washington, Jacksonville, San Francisco, Tampa Bay, New England, Green Bay, New Orleans, Kansas City and Las Vegas. Because the game matches, that feed also carries the fixture title in the guide.

## 0.2.15 — 8 November 2026

- The player's Scores tray shows one card per game again. A conference feed and its Top 25 poll can publish the same fixture under different event ids, and the old check read those as two different games; the tray now matches on the fixture itself — both teams and the kickoff time, in either order — and falls back to the event id for races, rounds and fight cards, which have no two sides to name. The Live now list, the Schedule panel and the Multiview game picker share the same check.
- Settings > Remote control can reach "What your remote does": each line there now takes focus and scrolls itself into view, so a remote stops on the reference instead of skipping past it into Extra buttons.
- Multiview hands the sound over on Up and Down as well as Left and Right, so a stacked pair of screens changes the voice from the remote without a sideways move.

## 0.2.13 — 7 November 2026

- NFL RedZone now has a card of its own in the football section on Sundays, carrying your provider's channel artwork, and the same card opens the player's Scores tray. It appears only on Sundays, only when the NFL is one of your leagues, and only while the playlist carries a channel for it.
- Tap it to open the remembered RedZone channel through the usual preview; hold it to choose between the RedZone channels in your playlist. That choice is remembered for every Sunday rather than for one day's fixture.
- The toolbar RedZone pill is gone: the card is the way in, on the day it is actually on.

## 0.2.12 — 7 November 2026

- Every tray that lists a day's games now shows one card per event: the scores pane in the player, the Live now list, the Schedule panel and the Multiview game picker. A conference feed and its Top 25 poll publish the same scoreboard row, and each tray had its own path to that data.
- Choosing only the poll still lists the game; the surviving card is labelled with the conference rather than the poll view.

## 0.2.11 — 7 November 2026

- A game that is both in a conference and in its Top 25 poll now gets one card, labelled with the conference, instead of appearing under each league in Events and Schedule. The poll view itself still shows the game when it is the only league selected.
- Stream info's "Buffered ahead" reports the live cushion the player actually holds. It previously grew with the time watched, because a live stream's media position keeps climbing.
- Each card in the Scores pane carries its sport's icon beside the league, so a football row and a basketball row are told apart at a glance when both are on.
- Scores opens on the game already playing when it was tuned from the Sports hub or from the pane, and falls back to the first live card otherwise.

## 0.2.10 — 7 November 2026

- Settings > Playback & preferences > Live buffer keeps a live channel playing through the short dropouts IPTV providers leave in a stream: Off, a reserve of 1.5, 4, 8 or 12 seconds, or Gradual.
- A reserve holds playback until that much live video is buffered, and re-earns it after a stall, so a gap plays out of the cushion instead of stopping the picture. A bigger reserve hides longer dropouts, but the channel starts later and plays that much further behind live.
- Gradual starts at once like Off, then plays at 96 % speed until it has built the same cushion, so a channel steadies the longer it is left on. Sound is time-stretched with pitch kept, so picture and sound stay in sync, and a speed the viewer chose is never overridden.
- The choice applies to the next channel opened, and only to live channels: a movie or episode keeps its normal start. Multiview is unchanged.

## 0.2.9 — 7 November 2026

- Settings > Playback & preferences > Buffering offers four presets — Automatic, Quick start, Balanced and Smoothest — that set how much the main player buffers before it starts and before it resumes after a rebuffer. Automatic keeps the tuning this build ships with, so nothing changes unless a viewer picks one, and it applies to the next channel opened.
- The vendored Android player accepts those load-control values through its Pigeon API instead of hardcoding them. Multiview keeps its own smaller buffers, so several grid decoders cannot each reserve a deep one.

## 0.2.8 — 7 November 2026

- One table now holds every known spelling of a linear network — `BTN`/`Big Ten Network`, `ACCN`/`ACC Network`, `SECN`/`SEC Network`, `CBSSN`/`CBS Sports Network`, `NBATV`/`NBA TV`, `NFLN`/`NFL Network`, `MLBN`, `NHLN`, `LHN`/`Longhorn Network`, `P12N`/`Pac-12 Network`, `ESPNU`/`ESPN U`, `FS1`/`F-Sports 1`, `ESPN2`/`ESPN 2`, and the 2024 Bally/FanDuel rename — so a game listed under one spelling finds a playlist carrying another, in either direction and from the channel search as well.
- The persisted channel-name cache is versioned, so an install that had already indexed its playlist rebuilds the keys instead of keeping the spellings it learned earlier.
- An unscoped US shorthand still cannot pull in another region's copy of the network, and the playlist's own exact spelling is kept beside it.

## 0.2.7 — 7 November 2026

- The scoreboard's own broadcaster now outranks a guess made from a channel's category, and the primary network counts for more than a secondary one, so a game listed on ACC Network no longer falls to whichever listed network sorts first alphabetically.
- Provider spellings resolve: "F-Sports 1" for FS1, "ESPN 2" for ESPN2, and an unlabelled "TNT" in a plain sports group no longer fails the region check when it is the only copy of that service.
- Picking a channel for a game now lists that game's own channel at the top of the search, even when the typed words are team names the channel name does not contain, and a broadcaster's spelling finds the service on your playlist.

## 0.2.6 — 6 November 2026

- Remap the playback buttons themselves: OK/Select, Left, Right, Up and Down can each be set to Scores, Channel list, Last channel, Channel up/down, Stream info, Channel card, Play/pause, Top bar, Player controls, Back to guide, or Do nothing.
- The shipped behaviour is the default for every button and is stored as data, so an untouched install is unchanged and every choice survives a restart. Back, Play/pause and the channel keys keep their hardware meaning.

## 0.2.5 — 6 November 2026

- Settings > Remote control: a plain-language guide to what every button does in Live TV, the guide, the player and menus, including the ones the TV itself consumes and the extra buttons most remotes send no default for.
- Remap a spare button to Live TV, Sports, Search, Multiview, Movies, TV Shows or Settings. Nothing is remapped until you choose it, a button can only do one thing, and the buttons the app's navigation depends on are refused.

## 0.2.4 — 6 November 2026

- Carry matched fixture titles into the Live TV guide for the whole session, not only while Sports is open. Guide titles now publish from the match session itself, so a catalogue restored from the Sports cache retitles its channels too.
- Keep those rows current when the guide was hidden while matching finished, and show the fixture while fast-scrolling the guide.

## 0.2.3 — 6 November 2026

- Show matched fixtures in the Live TV guide for sports event channels whose provider publishes no listings. A channel the Sports hub has already matched to a game now reads “Chelsea vs Arsenal” for that game’s slot instead of “No information”.
- Keep the generated titles display-only. They are never written to the guide database and never read back as matching evidence, so a wrong channel cannot confirm itself, and the provider’s own listings always win where they exist.

## 0.2.2 — 6 November 2026

- Make **Schedule** follow the league list. It was listing every competition in the catalogue whatever had been hidden, so sports that were switched off still appeared in its sport and league pickers and in the fixtures it loaded. Schedule now uses the same shown leagues as Events and Standings.

## 0.2.1 — 6 November 2026

- Keep Sports to the competitions you can actually show or hide. Extra schedules used to invent a league for every competition a free feed listed that day (club friendlies, continental cups and other one-off events), so fixtures appeared a minute or two after opening Sports under leagues that had no row in the league list and could not be switched off.
- Match extra fixtures only to a listed competition, by name, by the feed's known aliases, or by short name. ONE Championship cards now sit under the ONE Championship entry.
- Drop any event whose league is not one of the shown leagues before it reaches the listings, so no later feed can put unlisted competitions back on Sports. Rugby's live feed still reports its per-competition slugs under the live rugby entry.

## 0.2.0 — 6 November 2026

- Rename the app to **StreamSports**, with a new launcher icon, adaptive and themed (monochrome) icon layers and a TV banner. The application ID is unchanged, so existing installs update in place.
- Add **Transfer to another device** over the local network: playlists and their logins, settings, sports picks, favorites, hidden channels, group order, channel links and guide overrides. The receiving device is replaced rather than merged, and says so before accepting.
- Encrypt transfers with an ephemeral X25519 exchange and AES-256-GCM; both screens show the same six-digit code before anything is sent. No server or account is involved, and device-only state (resume positions, update checks, caches, layout) never travels.
- Replace per-league favorites with a single shown/hidden list, including bulk show/hide, restore selection and a coverage hint.
- Add college conferences and Top 25 picks to the league list. Selecting a pick narrows its full competition; selecting both never silently means every game.
- Check for app updates hourly, with **Later** to dismiss and **Skip** to ignore a specific version.
- Keep Sports to the leagues the viewer selected: guide-discovered competitions no longer appear alongside chosen leagues.

Beta builds between 0.1.6 and 0.1.21 were incremental previews and did not get individual entries here.

## 0.1.5 — 4 November 2026

- Preserve the native video view across Live TV, Sports and fullscreen transitions to avoid video freezes while audio continues.
- Keep suspended and interrupted matches visible in Events, including medical timeouts, without treating them as finished results.
- Show sports channel matches and guide events progressively, including with the Possible channels filter, and retain fresh matches when changing filters or reopening Sports.
- Reduce rendering and background work during Live TV and Sports navigation, with more consistent remote focus while results load.
- Populate cached guide and category information sooner on startup, preserve custom grouping, and refine the Live TV guide's spacing, typography and column shading.
- Clarify All, Favourites, Favourite leagues and Favourite teams & athletes filters. Keep Events selections independent while sharing browsing selections between Standings and Schedule.
- Improve favourite-league management with search, sport filters, bulk selection, compact controls and consistent sport and league icons.
- Refine team and game details with clearer records, sport-specific statistics, period scores, rosters and fixture rows. Keep long lists lazy and details on demand.
- Improve calendar remote navigation and add an optional, cancellable Load month action using cached monthly feeds and compact day summaries.
- Add custom XMLTV guide sources with editing, enable/disable controls and background updates.
- Add optional per-playlist user-agent presets and custom values for playlist setup, provider requests, guide downloads and playback.
- Improve Xtream setup and imports, including copied endpoint URLs, panel paths, URL-encoded credentials, authentication responses and connection errors.
- Fix mobile favourites-search keyboard focus, improve theme consistency and preserve category and guide navigation when returning from Sports.

## 0.1.4 — 3 November 2026

- Show existing Events channel suggestions in Schedule, with direct playback and quick access to game details, without additional matching requests.
- Hide completed fixtures by default, add a visibility toggle and show a current-time marker in chronological schedules.
- Keep schedule dates, scroll position and remote focus consistent while browsing and applying fixture updates.
- Improve remote navigation through Sports tabs, schedule controls, standings, league selectors and long lists.
- Add sport and enabled-state filters, scoped bulk changes and paging to league management.
- Refine Sports favourites with search, restored team names, team details and filters across Events, Schedule and Standings.
- Keep landscape Sports panels beside the preview and portrait panels centred, with more compact controls and clearer team statistics.
- Show supplied player leaders, possession and last-play information while respecting hidden scores.
- Reduce off-screen rendering, reuse unchanged results and cancel replay/highlight scans when leaving their tabs.
- Separate the selected Sports tab from remote/keyboard focus and remove retained focus borders during touch navigation.
- Improve playlist refresh, partial-failure recovery, setup error messages and remote access to save and retry controls.
- Improve Stalker portal compatibility, field correction and optional-field navigation.

## 0.1.3 — 2 November 2026

- Add Stalker / MAC playlists alongside M3U and Xtream, with on-demand catalogue loading and native portal guide support.
- Add a Schedule tab that opens on today's enabled leagues, with local search, time ordering, optional sport grouping and week/month calendars.
- Keep schedule summaries and additional dates on demand, with cached results and cancellation when leaving a view.
- Browse standings, match details and team information beside the Sports preview, with compact controls, team badges and sport-specific tables.
- Expand regional scores, fixtures and standings, including Japanese and Korean baseball, New Zealand NPC, K League, NCAA competitions and more motorsport series where sources provide coverage.
- Add searchable sports favourites and clearer league selection, retaining sport and league choices between tabs.
- Improve Watch on channel selection with consistent suggestions, remembered sorting and filters for channels, regions, playlists and match evidence.
- Make Sports controls, fixtures and tables more compact on phones, while keeping remote navigation and enlarged text supported.
- Prevent portrait tennis cards from overflowing after choosing a channel.
- Show cached Live TV guide rows earlier during startup and reduce channel-name processing during sports matching.
- Add separate Live TV, Movies and Series visibility controls, with search and a persistent Done action.
- Keep playlist submission buttons accessible on small screens and improve local phone pairing when VPN interfaces are present.
- Load replays, highlights and optional sports details only when opened.
- Remove unused media-server, desktop, account-tracking, profile and online subtitle features and their dependencies.
- Remove the unused APK installer and its install-packages permission. Updates remain available through the published APK download.

## 0.1.2 — 1 November 2026

- Faster opening of Settings, Movies, Series and other pages, with less background layout work.
- Smoother TV category navigation after visiting Favourites or History.
- Faster multiview channel selection for large playlists, with the selected category kept visible when returning from the guide.
- Immediate TV transitions for nested settings and detail pages, while retaining phone navigation behaviour.
- Improved sports team-name matching and fewer unsupported channel suggestions for events with limited broadcast information.

## 0.1.1 — 1 November 2026

- Faster sports channel matching on cold starts, with improved cache reuse and guide processing.
- Improved matching for Japanese, Korean and other Asian leagues, plus NCAA events.
- Smoother browsing while sports results load, with more consistent focus and scroll position.
- Faster page navigation and Live TV menu, category and guide transitions.
- Search across all enabled Movies or Series categories and playlists, with missing categories loaded in the background.
- Search playlist categories in Group Management and enable or disable just the matching groups.
- Keep Add Playlist and Save buttons accessible on phones, including when the keyboard is open.
- Hide Android system bars during mobile multiview, with temporary swipe-to-reveal controls.
- Improved playback recovery, replay discovery and remote navigation reliability.

## 0.1.0 — 27 October 2026

- First public Android release for phones, Android TV and Google TV.
- Live TV guide, sports events, replays, highlights, Movies, Series and multiview.
- M3U and Xtream playlist support, category organisation, favourites and picture-in-picture.
- APK downloads with installation instructions, checksums and corresponding source packages.
