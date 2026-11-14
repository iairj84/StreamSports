import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/models/epg_program.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/services/sports_channel_matcher.dart';
import 'package:nox_iptv/services/sports_match_inputs.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nox_iptv/services/storage_service.dart';

/// Term-honoring fake: substring retrieval like the SQL title scan, so the
/// test catches broadening the scorer but forgetting to retrieve candidates.
class _Guide implements SportsMatchGuide {
  _Guide(this.rows);
  final List<EpgProgram> rows;
  final List<List<String>> termQueries = [];
  @override
  int get changeRevision => 1;
  @override
  DateTime? get lastUpdated => null;
  @override
  EpgProgram? getCurrentProgram(String channelId) => null;
  @override
  EpgProgram? getNextProgram(String channelId) => null;
  @override
  Future<List<EpgProgram>> findProgrammesByTitle(
          DateTime from, DateTime to, List<String> terms,
          {List<String>? channelIds}) async {
    termQueries.add(List.of(terms));
    return rows
        .where((p) =>
            p.stop.isAfter(from) &&
            p.start.isBefore(to) &&
            terms.any((t) => p.title.toLowerCase().contains(t.toLowerCase())))
        .toList();
  }

  @override
  Future<List<EpgProgram>> findSportsProgrammesForChannels(
          List<String> ids, DateTime from, DateTime to) async =>
      const [];
}

class _Picks implements SportsMatchPicks {
  @override
  String? channelIdFor(SportsGame game) => null;
}

final _now = DateTime.utc(2026, 11, 14, 17);

SportsGame _game(String id, String leagueId, String home, String away) =>
    SportsGame(
      id: id,
      league: sportsLeagueById(leagueId)!,
      start: _now.subtract(const Duration(minutes: 30)),
      state: GameState.live,
      statusText: 'Live',
      home: SportsTeam(id: 'h', name: home, shortName: home, abbreviation: ''),
      away: SportsTeam(id: 'a', name: away, shortName: away, abbreviation: ''),
    );

Channel _channel(String id, String name) => Channel(
      id: 'test::$id',
      rawId: id,
      playlistId: 'test',
      name: name,
      group: 'Sports',
      url: 'https://example.invalid/$id',
    );

EpgProgram _programme(String channelId, String title) => EpgProgram(
      channelId: channelId,
      title: title,
      start: _now.subtract(const Duration(hours: 1)),
      stop: _now.add(const Duration(hours: 2)),
    );

void main() {
  test(
      'one home-group term per team game retrieves both shared-term fixtures',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    // Same-city cross-sport pair: one shared term must serve both games, and
    // each game's own check must claim only its rows.
    final rows = [
      _programme('nhl-network', 'Seattle Kraken vs Edmonton Oilers'),
      _programme('espn', 'Seattle Seahawks vs San Francisco 49ers'),
      _programme('mls', 'Seattle Sounders vs Portland Timbers'),
    ];
    final guide = _Guide(rows);
    final matcher = SportsChannelMatcher(guide);
    final channels = [
      _channel('nhl-network', 'US: NHL Network HD'),
      _channel('espn', 'US: ESPN HD'),
      _channel('mls', 'US: MLS Channel'),
    ];
    await matcher.prepare(channels);
    final games = [
      _game('kraken', 'nhl', 'Seattle Kraken', 'Edmonton Oilers'),
      _game('seahawks', 'nfl', 'Seattle Seahawks', 'San Francisco 49ers'),
    ];
    final result =
        await matcher.matchDay(games, _Picks(), includeGuide: true);
    final kraken = result['nhl:kraken']!;
    expect(kraken.map((m) => m.programme?.title),
        contains('Seattle Kraken vs Edmonton Oilers'));
    final seahawks = result['nfl:seahawks']!;
    expect(seahawks.map((m) => m.programme?.title),
        contains('Seattle Seahawks vs San Francisco 49ers'));
    // Neither game may claim the other Seattle-titled row.
    for (final matches in [kraken, seahawks]) {
      expect(matches.map((m) => m.programme?.title),
          isNot(contains('Seattle Sounders vs Portland Timbers')));
    }
    // Retrieval dropped the away-only groups but kept a shared home term.
    final terms = guide.termQueries.expand((q) => q).toSet();
    expect(terms, isNot(contains('edmonton')));
    expect(terms, isNot(contains('oilers')));
    expect(terms, contains('seattle'));
  });
}
