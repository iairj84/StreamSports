# Changelog

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
