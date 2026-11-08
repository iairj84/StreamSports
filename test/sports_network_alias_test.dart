import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/models/epg_program.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/services/sports_channel_matcher.dart';
import 'package:nox_iptv/services/sports_match_inputs.dart';

class _Guide implements SportsMatchGuide {
  final rows = <String, EpgProgram>{};
  @override
  int get changeRevision => 0;
  @override
  DateTime? get lastUpdated => null;
  @override
  EpgProgram? getCurrentProgram(String id) => rows[id];
  @override
  EpgProgram? getNextProgram(String id) => null;
  @override
  Future<List<EpgProgram>> findProgrammesByTitle(
          DateTime from, DateTime to, List<String> terms) async =>
      const [];
  @override
  Future<List<EpgProgram>> findSportsProgrammesForChannels(
          List<String> ids, DateTime from, DateTime to) async =>
      const [];
}

class _Picks implements SportsMatchPicks {
  @override
  String? channelIdFor(SportsGame game) => null;
}

final now = DateTime.utc(2026, 11, 7, 19);

SportsGame game(List<String> broadcasts,
        {String country = '', String groupLeague = 'college-football'}) =>
    SportsGame(
      id: 'alias-${broadcasts.join('|')}-$country',
      league: sportsLeagueById(groupLeague)!,
      start: now,
      state: GameState.live,
      statusText: '',
      home: const SportsTeam(
          id: 'h',
          name: 'Aster Athletic',
          shortName: 'Aster',
          abbreviation: 'AST'),
      away: const SportsTeam(
          id: 'a', name: 'Birch United', shortName: 'Birch', abbreviation: 'BIR'),
      scoreboardBroadcasts: [
        for (final name in broadcasts)
          SportsBroadcast(name, source: 'ESPN', country: country)
      ],
    );

Channel channel(String name, {String group = 'Sports'}) => Channel(
    id: name,
    rawId: name,
    playlistId: 'test',
    name: name,
    group: group,
    url: 'https://example.invalid/feed');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SportsChannelMatcher matcher;
  setUp(() => matcher = SportsChannelMatcher(_Guide(), clock: () => now));
  tearDown(() => matcher.dispose());

  Future<List<ChannelMatch>> match(SportsGame fixture) async =>
      (await matcher.matchDay([fixture], _Picks())).values.single;

  test('a provider spelling resolves the listed network without a region tag',
      () async {
    await matcher.prepare([channel('F-Sports 1')]);
    final rows = await match(game(['FS1']));
    expect(rows.map((m) => m.channel.name), ['F-Sports 1']);
    expect(rows.single.reason, MatchReason.network);
  });

  test('ESPN 2 and ESPN2 are the same service', () async {
    await matcher.prepare([channel('ESPN 2')]);
    final rows = await match(game(['ESPN2']));
    expect(rows.map((m) => m.channel.name), ['ESPN 2']);
    expect(rows.single.reason, MatchReason.network);
  });

  test('an exact unlabelled network still resolves its listing', () async {
    await matcher.prepare([channel('TNT', group: 'Entertainment')]);
    final rows = await match(game(['TNT']));
    expect(rows.map((m) => m.channel.name), ['TNT']);
    expect(rows.single.reason, MatchReason.network);
  });

  test('the primary listed broadcaster beats an earlier alphabetically secondary',
      () async {
    await matcher.prepare([channel('ABC'), channel('ACC Network')]);
    final rows = await match(game(['ACC Network', 'ABC']));
    expect(rows.first.channel.name, 'ACC Network');
    expect(rows.map((m) => m.channel.name), contains('ABC'));
  });

  test('a broadcaster outranks a league category guess', () async {
    await matcher.prepare([channel('TNT'), channel('NBA Extra', group: 'NBA')]);
    final fixture = game(['TNT'], groupLeague: 'nba');
    final rows = (await matcher.matchDay([fixture], _Picks(),
            includePossible: true))
        .values
        .single;
    expect(rows.map((m) => m.channel.name), contains('NBA Extra'));
    expect(rows.first.channel.name, 'TNT');
    expect(rows.first.reason, MatchReason.network);
  });

  test('search surfaces the game channel even without a name hit', () async {
    await matcher.prepare([channel('ACC Network')]);
    final rows = await matcher.searchWithGuide('Aster vs Birch', matches: [
      ChannelMatch(channel('ACC Network'), MatchReason.network, 250)
    ]);
    expect(rows.map((r) => r.channel.name), contains('ACC Network'));
  });

  test('search reaches a differently spelled service', () async {
    await matcher.prepare([channel('F-Sports 1'), channel('Other')]);
    final rows = await matcher.searchWithGuide('FS1');
    expect(rows.first.channel.name, 'F-Sports 1');
  });

  test('an abbreviation and its spelled-out service are one channel', () async {
    const pairs = [
      ['BTN', 'Big Ten Network'],
      ['ACCN', 'ACC Network'],
      ['SECN', 'SEC Network'],
      ['CBSSN', 'CBS Sports Network'],
      ['NBATV', 'NBA TV'],
      ['ESPNU', 'ESPN U'],
      ['NFLN', 'NFL Network'],
      ['MLBN', 'MLB Network'],
      ['NHLN', 'NHL Network'],
      ['LHN', 'Longhorn Network'],
      ['P12N', 'Pac-12 Network'],
      ['SN1', 'Sportsnet One'],
    ];
    for (final pair in pairs) {
      await matcher.prepare([channel(pair[1])]);
      expect((await match(game([pair[0]]))).map((m) => m.channel.name),
          [pair[1]],
          reason: '${pair[0]} should reach ${pair[1]}');
      await matcher.prepare([channel(pair[0])]);
      expect((await match(game([pair[1]]))).map((m) => m.channel.name),
          [pair[0]],
          reason: '${pair[1]} should reach ${pair[0]}');
    }
  });

  test('ESPN2 resolves a playlist that only spells it ESPN 2', () async {
    await matcher.prepare([channel('ESPN 2')]);
    expect((await match(game(['ESPN2']))).map((m) => m.channel.name),
        ['ESPN 2']);
    await matcher.prepare([channel('ESPN2')]);
    expect((await match(game(['ESPN 2']))).map((m) => m.channel.name),
        ['ESPN2']);
  });

  test('a renamed regional network still resolves', () async {
    await matcher.prepare([channel('Bally Sports Detroit', group: 'RSN')]);
    expect(
        (await match(game(['FanDuel Sports Network Detroit'])))
            .map((m) => m.channel.name),
        ['Bally Sports Detroit']);
  });

  test('search finds either spelling of an abbreviated service', () async {
    await matcher.prepare([channel('Big Ten Network')]);
    expect((await matcher.searchWithGuide('BTN')).map((r) => r.channel.name),
        contains('Big Ten Network'));
    expect(matcher.search('BTN').map((c) => c.name), contains('Big Ten Network'));
    await matcher.prepare([channel('BTN')]);
    expect(
        (await matcher.searchWithGuide('Big Ten Network'))
            .map((r) => r.channel.name),
        contains('BTN'));
  });

  test('the bare RedZone spellings are the same service', () async {
    for (final spelling in const ['RedZone', 'Red Zone']) {
      await matcher.prepare([channel(spelling)]);
      expect((await match(game(['NFL RedZone']))).map((m) => m.channel.name),
          [spelling],
          reason: '$spelling should reach an NFL RedZone listing');
      await matcher.prepare([channel('NFL RedZone')]);
      expect((await match(game([spelling]))).map((m) => m.channel.name),
          ['NFL RedZone'],
          reason: 'an NFL RedZone channel should reach $spelling');
    }
  });
}
