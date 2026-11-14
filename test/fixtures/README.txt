college_scoreboards_2026_10_21.json
Public ESPN scoreboards captured 21 October 2026 UTC; trimmed to event and team matching fields. Scores/states are a frozen regression fixture, not a live schedule.
Sources:
https://site.api.espn.com/apis/site/v2/sports/soccer/usa.ncaa.m.1/scoreboard
https://site.api.espn.com/apis/site/v2/sports/soccer/usa.ncaa.w.1/scoreboard
https://site.api.espn.com/apis/site/v2/sports/volleyball/womens-college-volleyball/scoreboard
Test channel labels are synthetic examples in the provider's naming style; they do not establish current subscription availability.

cfb_live_situation_2026_11_14.json
Public ESPN college-football scoreboard captured 14 November 2026 UTC (Miami vs Duke event, pregame at capture). Status flipped to a live 4th quarter and given a situation block mirroring a real live-game sample from the same day (same keys and value shapes); team ids and abbreviations are the event's own. Proves the parser keeps possession and down & distance end to end.
