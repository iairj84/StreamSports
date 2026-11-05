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
    return (await matcher.matchDay([game], picks))[
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

  test('a hockey feed grouped as Hockey resolves its compact NHL title',
      () async {
    guide.programmes = [
      programme('h01', '7pm UTA @ MTL'),
      programme('h02', '7pm BOS @ TOR'),
    ];
    final result = await match(game(), [
      _channel('h01', 'H01'),
      _channel('h02', 'H02'),
      _channel('center', 'NHL Center Ice'),
    ]);
    expect(result.first.channel.rawId, 'h01');
    expect(result.first.reason, MatchReason.guide);
    expect(result.first.isConfident, isTrue);
    expect(result.map((m) => m.channel.rawId), isNot(contains('h02')));
  });

  test('two bare codes outside the sport stay ambiguous', () async {
    guide.programmes = [
      EpgProgram(
          channelId: 'general',
          title: '7pm UTA @ MTL',
          start: DateTime.now().subtract(const Duration(minutes: 25)),
          stop: DateTime.now().add(const Duration(minutes: 95))),
    ];
    final result = await match(
        game(), [_channel('general', 'General Sports', group: 'Sports')]);
    expect(result, isEmpty);
  });
}
