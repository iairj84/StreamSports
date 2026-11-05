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

Channel _channel(String id, String name, {String group = 'Hockey'}) => Channel(
    id: 'test::$id',
    rawId: id,
    playlistId: 'test',
    name: name,
    group: group,
    url: 'https://example.invalid/never-opened');

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

  Future<List<ChannelMatch>> match(
      SportsGame game, List<Channel> channels) async {
    await matcher.prepare(channels);
    // The app asks for possible feeds too, which is where a league network used
    // to be promoted above the channel actually airing the game.
    return (await matcher.matchDay([game], picks, includePossible: true))[
        SportsChannelPicks.eventKey(game)]!;
  }

  SportsGame game() {
    final now = DateTime.now();
    return SportsGame(
        id: 'nhl-utah-montreal',
        league: sportsLeagueById('nhl')!,
        start: now.subtract(const Duration(minutes: 20)),
        state: GameState.live,
        statusText: '2nd',
        home: const SportsTeam(
            id: 'mtl',
            name: 'Montreal Canadiens',
            shortName: 'Canadiens',
            abbreviation: 'MTL'),
        away: const SportsTeam(
            id: 'uta',
            name: 'Utah Mammoth',
            shortName: 'Mammoth',
            abbreviation: 'UTA'));
  }

  EpgProgram programme(String channelId, String title) => EpgProgram(
      channelId: channelId,
      title: title,
      start: DateTime.now().subtract(const Duration(minutes: 25)),
      stop: DateTime.now().add(const Duration(minutes: 95)));

  test('a compact NHL title beats the league network channel', () async {
    guide.programmes = [
      programme('h01', '7pm UTA @ MTL'),
      programme('h02', '7pm BOS @ TOR'),
      programme('nhl', 'NHL Hockey'),
    ];
    final result = await match(game(), [
      _channel('h01', 'H01', group: 'Sports'),
      _channel('h02', 'H02', group: 'Sports'),
      _channel('nhl', 'NHL Network', group: 'Sports'),
    ]);
    expect(result.first.channel.rawId, 'h01');
    expect(result.first.reason, MatchReason.guide);
    expect(result.first.isConfident, isTrue);
    expect(result.map((m) => m.channel.rawId), isNot(contains('h02')));
  });

  // A league network channel carries the league's name in its own name, so
  // generic league evidence (name + group) used to outrank the guide match for
  // the actual game and every NHL card defaulted to "NHL Network".
  for (final group in ['NHL', 'Hockey', 'Sports']) {
    test('a league network loses to the game channel in group $group',
        () async {
      guide.programmes = [
        programme('h01', '7pm UTA @ MTL'),
        programme('h02', '7pm BOS @ TOR'),
        programme('nhl', 'NHL Hockey'),
      ];
      final result = await match(game(), [
        _channel('h01', 'H01', group: group),
        _channel('h02', 'H02', group: group),
        _channel('nhl', 'NHL Network', group: group),
      ]);
      expect(result.first.channel.rawId, 'h01');
      expect(result.first.reason, MatchReason.guide);
      final network = result.where((m) => m.channel.rawId == 'nhl').firstOrNull;
      if (network != null) {
        expect(result.indexOf(network), greaterThan(0));
      }
    });
  }

  test('a league network is never confident coverage for a game', () async {
    final result = await match(game(), [
      _channel('h01', 'H01', group: 'Hockey'),
      _channel('nhl', 'NHL Network', group: 'Hockey'),
    ]);
    final network = result.where((m) => m.channel.rawId == 'nhl').firstOrNull;
    expect(network, isNotNull);
    expect(network!.reason, MatchReason.league);
    expect(network.isConfident, isFalse);
  });

  test('a title naming another matchup never matches', () async {
    guide.programmes = [programme('left', '7pm BOS @ TOR')];
    final result =
        await match(game(), [_channel('left', 'General Sports')]);
    expect(result, isEmpty);
  });
}
