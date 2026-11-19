import '../models/sports.dart';
import 'b_league.dart';
import 'easl_scoreboard.dart';
import 'espn_scoreboard.dart';
import 'k_league_scoreboard.dart';
import 'regional_baseball.dart';

/// How often a feed's reply is allowed to be replaced, and what identifies one
/// reply in the cache.
///
/// These were two separate `switch (league.source)` chains (`_scoreboardKey`
/// and `_freshEntry`) over the same four cases; they are one axis of behaviour,
/// so they are declared together.
enum FeedWindow {
  /// One calendar day, as ESPN's `dates=` query means it.
  day,

  /// One calendar month: K League and NPB publish a month at a time, so every
  /// day of it shares a reply and stays fresh until the month ends.
  month,

  /// One season: the ABL season runs mid-year to mid-year.
  season,

  /// A single undivided current-season table that the source replaces in
  /// place, as EASL's does.
  currentSeason;

  /// What one request is cached under for [date].
  String cacheKey(DateTime date) => switch (this) {
        FeedWindow.day => sportsEspnDate(date),
        FeedWindow.month => sportsEspnDate(date).substring(0, 6),
        FeedWindow.season => '${ablSeasonYear(date)}',
        FeedWindow.currentSeason => 'current-season',
      };

  /// The date whose staleness rules this reply follows. A monthly reply is
  /// as stale as the end of its month; a season feed is judged against today.
  DateTime anchor(DateTime date, DateTime today) => switch (this) {
        FeedWindow.day => date,
        FeedWindow.month => DateTime(date.year, date.month + 1, 0),
        FeedWindow.season || FeedWindow.currentSeason => today,
      };
}

/// How a date window's fixtures are collected from this feed.
enum FeedSchedule {
  /// One request per day in the window (every regional league).
  daily,

  /// One request per month over the window, which ESPN caps at 1000 events.
  monthly,

  /// No requests: the locally cached motorsport calendar answers for the
  /// whole window.
  motorsport,
}

/// One provider's scoreboard feed: the request, its cache identity, its expiry
/// rule and the parser that runs in the isolate.
///
/// The scoreboard pipeline used to ask `switch (league.source)` six separate
/// questions — whether the league is score-capable, which URL to build, whether
/// to POST, how to decode the body, what cache key to use, when a cached reply
/// expires, which parser to run, and how the schedule window is collected.
/// Adding a league meant finding all six; now it means one entry here, and a
/// league that reuses an existing format is data alone.
class ScoreboardFeed {
  const ScoreboardFeed({
    required this.source,
    required this.parse,
    required this.uri,
    this.window = FeedWindow.day,
    this.schedule = FeedSchedule.daily,
    this.postBody,
    this.boundedResponse = false,
    this.utf8Body = false,
    this.calendarOnly = false,
  });

  /// The `SportsLeague.source` value this feed serves.
  final String source;

  /// Runs inside the scoreboard parse isolate. Null for a calendar-only feed,
  /// which is never requested.
  final List<SportsGame> Function(String body, SportsLeague league)? parse;

  /// Null for a calendar-only feed.
  final Uri Function(DateTime date, SportsLeague league)? uri;

  final FeedWindow window;
  final FeedSchedule schedule;

  /// JSON body for a POST feed; null means GET.
  final Map<String, Object?> Function(DateTime date, SportsLeague league)?
      postBody;

  /// Read through the 2 MB cap instead of buffering the whole reply. Regional
  /// league sites answer with HTML or oversized payloads; the cap keeps one
  /// slow publisher from holding a large buffer on a small box.
  final bool boundedResponse;

  /// Decode the reply as UTF-8 rather than trusting its declared charset.
  final bool utf8Body;

  /// Fixtures are listed but never scored (the motorsport calendar).
  final bool calendarOnly;
}

/// ESPN is the default: any league not named below is answered by its own
/// `espnPath`, and its kind (team, golf, racing, fight, tennis) decides how the
/// events are read.
final ScoreboardFeed _espnFeed = ScoreboardFeed(
  source: 'ESPN',
  parse: parseEspnScoreboardBody,
  uri: (date, league) => Uri.parse('$espnApiBase/${league.espnPath}/scoreboard'
      '?dates=${sportsEspnDate(date)}${espnScoreboardOptions(league)}'),
  schedule: FeedSchedule.monthly,
);

/// Every provider that publishes its own scoreboard, by `SportsLeague.source`.
///
/// Add a league here rather than a switch case in `SportsService`; a league
/// that shares a provider's format (another MLB statsapi competition, another
/// koreabaseball division) needs no code at all.
final Map<String, ScoreboardFeed> kScoreboardFeeds = {
  'K League': ScoreboardFeed(
    source: 'K League',
    parse: parseKLeagueScoreboard,
    uri: (date, league) =>
        Uri.https('www.kleague.com', '/getScheduleList.do'),
    window: FeedWindow.month,
    // The endpoint filters by POST body, not query.
    postBody: (date, league) => {
      'leagueId': league.id.split('.').last,
      'year': '${date.year}',
      'month': date.month.toString().padLeft(2, '0'),
      'teamId': '',
      'ticketYn': '',
      'lang': 'en',
    },
  ),
  'EASL': ScoreboardFeed(
    source: 'EASL',
    parse: parseEaslScoreboard,
    uri: (date, league) => Uri.https('easl.joshricha.com', '/api/v1/matches'),
    window: FeedWindow.currentSeason,
  ),
  'NPB': ScoreboardFeed(
    source: 'NPB',
    parse: parseNpbScoreboard,
    uri: (date, league) => Uri.https(
        'npb.jp',
        '/games/${date.year}/schedule_'
        '${date.month.toString().padLeft(2, '0')}_detail.html'),
    window: FeedWindow.month,
    boundedResponse: true,
    utf8Body: true,
  ),
  'KBO': ScoreboardFeed(
    source: 'KBO',
    parse: parseKboScoreboard,
    uri: (date, league) =>
        Uri.https('eng.koreabaseball.com', '/Schedule/Scoreboard.aspx', {
      'searchDate': '${date.year}-${date.month.toString().padLeft(2, '0')}'
          '-${date.day.toString().padLeft(2, '0')}',
    }),
    boundedResponse: true,
    utf8Body: true,
  ),
  'ABL': ScoreboardFeed(
    source: 'ABL',
    parse: parseAblScoreboard,
    uri: (date, league) => Uri.https('statsapi.mlb.com', '/api/v1/schedule', {
      'sportId': '17',
      'leagueId': '595',
      'season': '${ablSeasonYear(date)}',
      'hydrate': 'team,venue(timezone),linescore',
    }),
    window: FeedWindow.season,
    boundedResponse: true,
  ),
  'B.League': ScoreboardFeed(
    source: 'B.League',
    parse: parseBLeagueScoreboard,
    uri: (date, league) => Uri.https('www.bleague.jp', '/en/schedule/', {
      'year': '${date.year}',
      'mon': '${date.month}',
      'day': date.day.toString().padLeft(2, '0'),
      'tab': '1',
    }),
    boundedResponse: true,
    utf8Body: true,
  ),
  'RaceTV Guide': const ScoreboardFeed(
    source: 'RaceTV Guide',
    parse: null,
    uri: null,
    schedule: FeedSchedule.motorsport,
    calendarOnly: true,
  ),
};

/// The feed serving [league]; ESPN when the league names no provider of its
/// own. A league whose `source` is unknown to this build (a saved league from a
/// newer version) falls back to the same path, exactly as the old default arm
/// of every switch did.
ScoreboardFeed scoreboardFeedFor(SportsLeague league) =>
    kScoreboardFeeds[league.source] ?? _espnFeed;

/// Whether [league] publishes scores as well as fixtures.
///
/// Deliberately explicit rather than "any league falls back to ESPN": a saved
/// league this build does not know how to score must keep showing as
/// unsupported instead of requesting an ESPN path that does not exist.
bool supportsSportsScoreboard(SportsLeague league) {
  final feed = kScoreboardFeeds[league.source];
  return league.source == 'ESPN' || (feed != null && !feed.calendarOnly);
}

/// Whether [league] can list fixtures for a date window, scored or not.
bool supportsSportsSchedule(SportsLeague league) =>
    league.source == 'ESPN' || kScoreboardFeeds.containsKey(league.source);
