import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/models/epg_program.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/services/epg_service.dart';
import 'package:nox_iptv/services/sports_channel_matcher.dart';
import 'package:nox_iptv/services/storage_service.dart';

class _Guide extends EpgService {
  _Guide(super.storage);
  List<EpgProgram> programmes = [];
  @override
  EpgProgram? getCurrentProgram(String id) => programmes
      .where((p) => p.channelId == id && p.isNowPlaying(DateTime.now()))
      .firstOrNull;
  @override
  EpgProgram? getNextProgram(String id) => programmes
      .where((p) => p.channelId == id && p.start.isAfter(DateTime.now()))
      .firstOrNull;
  @override
  Future<List<EpgProgram>> findSportsProgrammesForChannels(
          List<String> ids, DateTime from, DateTime to) async =>
      programmes
          .where((p) =>
              ids.contains(p.channelId) &&
              p.stop.isAfter(from) &&
              p.start.isBefore(to))
          .toList();
  @override
  Future<List<EpgProgram>> findProgrammesByTitle(
          DateTime from, DateTime to, List<String> terms,
          {List<String>? channelIds}) async =>
      programmes
          .where((p) =>
              p.stop.isAfter(from) &&
              p.start.isBefore(to) &&
              terms.any((t) => p.title.toLowerCase().contains(t.toLowerCase())))
          .toList();
}

Channel _channel(String id, String name, {String group = 'Sports'}) => Channel(
    id: 'test::$id',
    rawId: id,
    playlistId: 'test',
    name: name,
    group: group,
    epgIdOverride: id,
    url: 'https://example.invalid/never-opened');

/// Rutgers at Penn State, listed on FS1, against a provider that files
/// numbered college football feeds under a group named for the league.
SportsGame _game({List<String> broadcasts = const []}) => SportsGame(
    id: 'rutgers-pennstate',
    league: sportsLeagueById('college-football')!,
    start: DateTime.now().subtract(const Duration(minutes: 20)),
    state: GameState.live,
    statusText: '2nd',
    broadcasts: broadcasts,
    home: const SportsTeam(
        id: 'psu',
        name: 'Penn State Nittany Lions',
        shortName: 'Penn State',
        abbreviation: 'PSU'),
    away: const SportsTeam(
        id: 'rut',
        name: 'Rutgers Scarlet Knights',
        shortName: 'Rutgers',
        abbreviation: 'RUT'));

EpgProgram _airing(String channelId, String title) => EpgProgram(
    channelId: channelId,
    title: title,
    start: DateTime.now().subtract(const Duration(minutes: 25)),
    stop: DateTime.now().add(const Duration(minutes: 95)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Guide guide;
  late SportsChannelMatcher matcher;
  late SportsChannelPicks picks;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    guide = _Guide(storage);
    matcher = SportsChannelMatcher(guide);
    picks = SportsChannelPicks.load(storage);
  });
  tearDown(() => guide.dispose());

  final channels = [
    _channel('fs1', 'FS1'),
    _channel('ncaaf1', 'NCAAF 01', group: 'NCAAF'),
    _channel('ncaaf2', 'NCAAF 02', group: 'NCAAF'),
  ];

  Future<List<ChannelMatch>> match(SportsGame game,
      {List<EpgProgram> programmes = const []}) async {
    guide.programmes = programmes;
    await matcher.prepare(channels);
    return (await matcher.matchDay([game], picks, includePossible: true))[
        SportsChannelPicks.eventKey(game)]!;
  }

  test('the feed airing the fixture outranks a league category channel',
      () async {
    final rows =
        await match(_game(), programmes: [_airing('fs1', 'Rutgers at Penn State')]);

    expect(rows.first.channel.name, 'FS1');
    expect(rows.first.reason, MatchReason.guide);
    // The group name alone matches every college football game at once, so it
    // stays a suggestion behind real evidence about this fixture.
    expect(rows.where((m) => m.reason == MatchReason.category).length, 2);
  });

  test('a listed broadcaster keeps its rank when the guide agrees', () async {
    final rows = await match(_game(broadcasts: const ['FS1']),
        programmes: [_airing('fs1', 'Rutgers at Penn State')]);

    expect(rows.first.channel.name, 'FS1');
    // The guide scored higher than the listing did, but a broadcaster the
    // scoreboard named must not be demoted to a plain guide hit by it.
    expect(rows.first.reason, MatchReason.network);
    expect(rows.first.detail, 'FS1');
    // The guide slot found on the way still travels with it.
    expect(rows.first.programme?.title, 'Rutgers at Penn State');
  });

  test('picker search offers the broadcaster before the league label', () {
    final suggestions =
        SportsChannelMatcher.searchSuggestions(_game(broadcasts: const ['FS1']));

    expect(suggestions.indexOf('FS1'), lessThan(suggestions.indexOf('NCAAF')));
  });
}
