import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/models/epg_program.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/services/epg_service.dart';
import 'package:nox_iptv/services/sports_channel_matcher.dart';
import 'package:nox_iptv/services/sports_match_inputs.dart';
import 'package:nox_iptv/services/storage_service.dart';

/// Memory-constrained devices (typical TV boxes) skip the second discovery
/// isolate: its duplicate channel index is what tips a long first-open into
/// memory pressure, which kills the worker and restarts the whole job from
/// zero. Matching must still complete through the main worker's own
/// progressive discovery.
class _Guide extends EpgService {
  _Guide(super.storage);
  final rows = <String, EpgProgram>{};
  @override
  EpgProgram? getCurrentProgram(String id) => rows[normalizeEpgId(id)];
  @override
  EpgProgram? getNextProgram(String id) => null;
  @override
  Future<List<EpgProgram>> findProgrammesByTitle(
          DateTime from, DateTime to, List<String> terms,
          {List<String>? channelIds}) async =>
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

Channel _channel(String id, String name) => Channel(
    id: 'p::$id',
    rawId: id,
    playlistId: 'p',
    name: name,
    group: 'TV',
    url: 'https://example.invalid/$id',
    epgIdOverride: id);

final _start = DateTime.utc(2026, 10, 10, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('low-memory devices match a large catalogue without the discovery isolate',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final guide = _Guide(storage);
    addTearDown(guide.dispose);
    SportsChannelMatcher.lowMemoryDevice = true;
    addTearDown(() => SportsChannelMatcher.lowMemoryDevice = false);
    final worker =
        SportsChannelMatcher.background(guide, clock: () => _start);
    addTearDown(worker.dispose);
    final channels =
        List.generate(5000, (i) => _channel('$i', 'Sports TV $i'));
    channels.add(_channel('tennis', 'Yunchaokete Bu vs Casper Ruud'));
    await worker.prepare(channels);
    await worker.primeGuide();
    // Must not throw or hang waiting for a discovery worker that never runs.
    await worker.discoverGuideEvents().timeout(const Duration(seconds: 60));
    final game = SportsGame(
        id: 'match',
        league: sportsLeagueById('tennis.atp')!,
        start: _start,
        state: GameState.live,
        statusText: 'Live',
        home: const SportsTeam(
            id: 'home',
            name: 'Yunchaokete Bu',
            shortName: 'Yunchaokete Bu',
            abbreviation: ''),
        away: const SportsTeam(
            id: 'away',
            name: 'Casper Ruud',
            shortName: 'Casper Ruud',
            abbreviation: ''));
    final matches = await worker
        .matchDay([game], _Picks(),
            includeGuide: true, onGuideEvents: (_) {})
        .timeout(const Duration(seconds: 120));
    expect(
        matches.values
            .expand((rows) => rows)
            .any((m) => m.channel.id == 'p::tennis'),
        isTrue);
  });
}
