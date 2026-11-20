import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/services/sports_standings_service.dart';
import 'package:nox_iptv/services/standings_feeds.dart';

/// The own-source standings table replaced a chain of per-provider `if` blocks.
/// These tests keep the table equivalent to the code it replaced: the league
/// that owns each entry, the request each provider sees, the season each one
/// asks for, and the one provider that retries the previous season.
/// A published MLB-statsapi table, the shape the ABL endpoint returns.
String ablTable(String year) => jsonEncode({
      'records': [
        {
          'league': {'id': 595},
          'sport': {'id': 17},
          'teamRecords': [
            // The ABL parser refuses a table under four clubs: a partial
            // publication must not become a standings table.
            for (var i = 1; i <= 4; i++)
              {
                'season': year,
                'team': {
                  'id': 100 + i,
                  'name': 'Club $i',
                  'shortName': 'Club $i',
                  'abbreviation': 'C$i',
                  'league': {'id': 595},
                  'sport': {'id': 17},
                },
                'leagueRank': '$i',
                'gamesPlayed': 12,
                'leagueGamesBack': '-',
                'leagueRecord': {
                  'wins': 8,
                  'losses': 3,
                  'ties': 1,
                  'pct': '.727',
                },
              }
          ]
        }
      ]
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 11, 2);
  StandingsRequest requestFor(String id, {bool previous = false}) => (
        league: sportsLeagueById(id)!,
        now: now,
        year: 2026,
        previous: previous,
      );

  test('every entry is filed under a real league of that source', () {
    for (final entry in kStandingsFeeds.entries) {
      final league = sportsLeagueById(entry.key);
      expect(league, isNotNull, reason: '${entry.key} is not a known league');
      expect(entry.value.source, league!.source,
          reason: '${entry.key} is filed under ${entry.value.source}');
      // An own-source entry must not shadow the ESPN pipeline.
      expect(entry.value.source, isNot('ESPN'), reason: entry.key);
      expect(standingsFeedFor(league), isNotNull, reason: entry.key);
    }
  });

  test('MotoGP stays an explicit source, not a one-request feed', () {
    // Its class standings need a season lookup before the table, which this
    // shape cannot express; the service keeps it behind the same transport.
    for (final id in ['racing.motogp', 'racing.moto2', 'racing.moto3']) {
      expect(kStandingsFeeds.containsKey(id), isFalse, reason: id);
    }
  });

  test('a league whose source differs is not answered by the entry', () {
    // Saved leagues and hand-built instances can carry an id with another
    // source; the old code checked both halves, so the lookup must too.
    const borrowed = SportsLeague(
      id: 'kor.1',
      espnPath: 'soccer/kor.1',
      name: 'K League 1',
      shortName: 'KOR',
      logoUrl: '',
      source: 'ESPN',
    );
    expect(standingsFeedFor(borrowed), isNull);
    expect(standingsFeedFor(sportsLeagueById('kor.1')!), isNotNull);
  });

  test('ESPN-covered leagues have no own-source feed', () {
    for (final id in ['eng.1', 'usa.1', 'rugby.270559', 'hockey.ehl']) {
      final league = sportsLeagueById(id);
      if (league == null) continue;
      expect(standingsFeedFor(league), isNull, reason: id);
    }
  });

  test('each provider keeps the request it was built around', () {
    // These are the addresses that silently break when a publisher moves a
    // page; one assertion per provider is the cheapest canary.
    final kbo = kStandingsFeeds['baseball.kbo']!;
    final kboUri = kbo.uri(requestFor('baseball.kbo'));
    expect(kboUri.host, 'eng.koreabaseball.com');
    expect(kboUri.path, '/Standings/TeamStandings.aspx');

    final npb = kStandingsFeeds['baseball.npb']!;
    expect(npb.uri(requestFor('baseball.npb')).path, '/bis/eng/2026/stats/');

    final bleague = kStandingsFeeds['basketball.bleague']!;
    expect(bleague.uri(requestFor('basketball.bleague')).path,
        '/en/standings-stats/');

    final easl = kStandingsFeeds['basketball.easl']!;
    expect(easl.uri(requestFor('basketball.easl')).path, '/api/v1/standings');

    final abl = kStandingsFeeds['baseball.abl']!;
    final ablUri = abl.uri(requestFor('baseball.abl'));
    expect(ablUri.queryParameters['season'], '2026');
    expect(ablUri.queryParameters['leagueId'], '595');

    // One entry serves both divisions, and the request names which one.
    final kor1 = kStandingsFeeds['kor.1']!;
    expect(kor1.method, 'POST');
    expect(kor1.headers['Accept-Language'], 'en');
    expect(kor1.uri(requestFor('kor.1')).queryParameters['leagueId'], '1');
    expect(kStandingsFeeds['kor.2']!.uri(requestFor('kor.2'))
        .queryParameters['leagueId'], '2');
  });

  test('no two providers share a request', () {
    final seen = <String, String>{};
    for (final entry in kStandingsFeeds.entries) {
      final uri = entry.value.uri(requestFor(entry.key));
      // K League's two divisions share one endpoint and differ by query, so the
      // whole request is the identity.
      final address = '${entry.value.method} $uri';
      expect(seen[address], isNull,
          reason: '${entry.key} and ${seen[address]} both request $address');
      seen[address] = entry.key;
    }
  });

  test('the season each provider asks for', () {
    // A calendar year by default.
    for (final id in [
      'basketball.bleague',
      'baseball.kbo',
      'basketball.easl',
      'kor.1',
      'kor.2',
    ]) {
      expect(kStandingsFeeds[id]!.yearOf(DateTime(2026, 11, 2)), 2026,
          reason: id);
    }
    // NPB keeps last season's final table until spring.
    final npb = kStandingsFeeds['baseball.npb']!;
    expect(npb.yearOf(DateTime(2026, 2, 28)), 2025);
    expect(npb.yearOf(DateTime(2026, 3, 1)), 2026);
    // The ABL season starts in November.
    final abl = kStandingsFeeds['baseball.abl']!;
    expect(abl.yearOf(DateTime(2026, 6, 30)), 2025);
    expect(abl.yearOf(DateTime(2026, 7, 1)), 2026);
  });

  test('only the ABL retries the previous season', () {
    for (final entry in kStandingsFeeds.entries) {
      expect(entry.value.previousSeasonFallback, entry.key == 'baseball.abl',
          reason: entry.key);
    }
  });

  test('an own-source league is dispatched to its feed, not to ESPN',
      () async {
    final requested = <Uri>[];
    final service = SportsStandingsService(
      clock: () => now,
      client: MockClient((request) async {
        requested.add(request.url);
        return http.Response(
            jsonEncode([
              {
                'team': {
                  'id': '11111111-1111-1111-1111-111111111111',
                  'name': 'Hong Kong Eastern',
                  'code': 'HKE',
                },
                'pool': {'name': 'Group A'},
                'position': 1,
                'stats': {
                  'gamePlayed': 6,
                  'wins': 5,
                  'losses': 1,
                  'pointDifference': 42,
                  'pointsFor': 500,
                  'pointsAgainst': 458,
                  'winPercentage': 0.833,
                },
              }
            ]),
            200);
      }),
    );
    addTearDown(service.close);
    final data = await service.load(sportsLeagueById('basketball.easl')!);
    expect(requested.single.host, 'easl.joshricha.com');
    expect(data.hasRows, isTrue);
    expect(data.tables.single.rows.single.team.name, 'Hong Kong Eastern');
  });

  test('the ABL asks for the previous season when this one is empty',
      () async {
    final seasons = <String>[];
    final service = SportsStandingsService(
      clock: () => DateTime(2026, 11, 2),
      client: MockClient((request) async {
        final season = request.url.queryParameters['season']!;
        seasons.add(season);
        if (season == '2026') return http.Response('{"records":[]}', 200);
        return http.Response(ablTable('2025'), 200);
      }),
    );
    addTearDown(service.close);
    final data = await service.load(sportsLeagueById('baseball.abl')!);
    // Asked for the running season first (empty before it starts), then the
    // season that actually has a published table.
    expect(seasons, ['2026', '2025']);
    expect(data.hasRows, isTrue);
    expect(data.previousSeason, isTrue);
  });
}
