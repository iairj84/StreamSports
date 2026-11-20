import 'dart:typed_data';

import '../models/sports.dart';
import '../models/standings.dart';
import 'b_league.dart';
import 'easl_standings.dart';
import 'k_league_standings.dart';
import 'regional_baseball.dart';

/// One standings request and the season it belongs to.
///
/// It is also the parse isolate's payload, so every field must be sendable:
/// [league] is a plain value object, and the rest are numbers, a date and a
/// flag.
typedef StandingsRequest = ({
  SportsLeague league,
  DateTime now,
  int year,
  bool previous,
});

/// A competition that publishes its own table: one request, one parser.
///
/// The service used to test `league.source`/`league.id` in a chain of `if`
/// blocks, one per provider, each repeating the same read → compute → fallback
/// shape. The chain is a dispatch: a league has one source, so exactly one
/// block ran. This table says the same thing as data, and a new own-source
/// league is one entry. Leagues ESPN covers, and the ESPN pipeline that ranks
/// its team lists with a second source, are handled in the service because they
/// compose rather than dispatch.
class StandingsFeed {
  const StandingsFeed({
    required this.source,
    required this.uri,
    required this.parse,
    this.method = 'GET',
    this.headers = const {},
    this.yearOf = _calendarYear,
    this.previousSeasonFallback = false,
  });

  /// The `SportsLeague.source` that owns this competition. Checked on lookup so
  /// a league carrying an id but a different source keeps the old behaviour:
  /// it is not answered by this provider.
  final String source;

  /// The competition's request for [request]. Most providers key on the season
  /// year; K League also keys on which division was asked for.
  final Uri Function(StandingsRequest request) uri;

  /// Runs in a background isolate, so it must be a top-level function.
  final LeagueStandings Function((Uint8List, StandingsRequest)) parse;

  final String method;
  final Map<String, String> headers;

  /// The season the table covers. A calendar year unless the competition's
  /// season starts mid-year or is reported late.
  final int Function(DateTime now) yearOf;

  /// Ask for the season before [yearOf] when the first table comes back empty.
  /// Only the ABL does this: its standings endpoint answers for the requested
  /// season, and the next one is not published until the season is under way.
  final bool previousSeasonFallback;
}

int _calendarYear(DateTime now) => now.year;

/// The ABL season starts in November, so a table asked for in the first half of
/// the year belongs to the previous season.
int _ablYear(DateTime now) => now.month < 7 ? now.year - 1 : now.year;

/// NPB publishes a season's final table until the new one starts in spring.
int _npbYear(DateTime now) => now.month < 3 ? now.year - 1 : now.year;

// `compute` needs a top-level entry point and each parser takes only the part
// of the request it understands, so each provider gets a one-line adapter.
LeagueStandings _bLeagueTask((Uint8List, StandingsRequest) input) =>
    parseBLeagueStandings(input.$1);

LeagueStandings _npbTask((Uint8List, StandingsRequest) input) =>
    parseNpbStandings((input.$1, input.$2.year));

LeagueStandings _kboTask((Uint8List, StandingsRequest) input) =>
    parseKboStandings(input.$1);

LeagueStandings _ablTask((Uint8List, StandingsRequest) input) =>
    parseAblStandings((input.$1, input.$2.year, input.$2.previous));

LeagueStandings _easlTask((Uint8List, StandingsRequest) input) =>
    parseEaslStandings(input.$1);

LeagueStandings _kLeagueTask((Uint8List, StandingsRequest) input) =>
    parseKLeagueStandings((input.$1, input.$2.league, input.$2.year));

/// Competitions whose own feed is their table, by `SportsLeague.id`.
///
/// MotoGP is deliberately absent: its class standings need a season lookup
/// before the category table, which this one-request shape cannot express, so
/// it stays an explicit source behind the same transport.
final Map<String, StandingsFeed> kStandingsFeeds = {
  'basketball.bleague': StandingsFeed(
    source: 'B.League',
    uri: (request) =>
        Uri.https('www.bleague.jp', '/en/standings-stats/'),
    parse: _bLeagueTask,
  ),
  'baseball.npb': StandingsFeed(
    source: 'NPB',
    uri: (request) => Uri.https(
        'npb.jp', '/bis/eng/${request.year}/stats/'),
    parse: _npbTask,
    yearOf: _npbYear,
  ),
  'baseball.kbo': StandingsFeed(
    source: 'KBO',
    uri: (request) =>
        Uri.https('eng.koreabaseball.com', '/Standings/TeamStandings.aspx'),
    parse: _kboTask,
  ),
  'baseball.abl': StandingsFeed(
    source: 'ABL',
    uri: (request) => Uri.https('statsapi.mlb.com', '/api/v1/standings', {
      'leagueId': '595',
      'season': '${request.year}',
      'standingsTypes': 'regularSeason',
      'hydrate': 'team',
    }),
    parse: _ablTask,
    yearOf: _ablYear,
    previousSeasonFallback: true,
  ),
  'basketball.easl': StandingsFeed(
    source: 'EASL',
    uri: (request) =>
        Uri.https('easl.joshricha.com', '/api/v1/standings'),
    parse: _easlTask,
  ),
  // One entry serves both divisions; the request carries which one.
  'kor.1': const StandingsFeed(
    source: 'K League',
    uri: _kLeagueUri,
    parse: _kLeagueTask,
    method: 'POST',
    headers: {'Accept-Language': 'en'},
  ),
  'kor.2': const StandingsFeed(
    source: 'K League',
    uri: _kLeagueUri,
    parse: _kLeagueTask,
    method: 'POST',
    headers: {'Accept-Language': 'en'},
  ),
};

/// K League filters by query even though the request is a POST.
Uri _kLeagueUri(StandingsRequest request) =>
    Uri.https('www.kleague.com', '/record/teamRank.do', {
      'leagueId': request.league.id == 'kor.1' ? '1' : '2',
      'year': '${request.year}',
      'stadium': 'all',
      'recordType': 'rank',
      'lang': 'en',
    });

/// The own-source feed for [league], or null when ESPN (or its enrichment
/// pipeline) answers for it.
///
/// Both halves are checked: a league whose id is catalogued but whose source
/// says otherwise — a hand-built instance, or a saved league whose provider
/// changed — is not answered by that provider's feed.
StandingsFeed? standingsFeedFor(SportsLeague league) {
  final feed = kStandingsFeeds[league.id];
  return feed != null && feed.source == league.source ? feed : null;
}
