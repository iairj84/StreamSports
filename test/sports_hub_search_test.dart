import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/models/epg_program.dart';
import 'package:nox_iptv/services/sports_channel_matcher.dart';
import 'package:nox_iptv/services/sports_match_inputs.dart';

/// The hub picker must reach later listings, not just now/next: a typed team
/// usually plays tonight. The main guide search finds those streams, so the
/// picker has to as well.
class _Guide implements SportsMatchGuide {
  _Guide(this.rows);
  final List<EpgProgram> rows;
  final current = <String, EpgProgram>{};
  final next = <String, EpgProgram>{};
  final List<List<String>> termQueries = [];
  @override
  int get changeRevision => 1;
  @override
  DateTime? get lastUpdated => null;
  @override
  EpgProgram? getCurrentProgram(String channelId) => current[channelId];
  @override
  EpgProgram? getNextProgram(String channelId) => next[channelId];
  @override
  Future<List<EpgProgram>> findProgrammesByTitle(
          DateTime from, DateTime to, List<String> terms,
          {List<String>? channelIds}) async =>
      rows
          .where((p) =>
              p.stop.isAfter(from) &&
              p.start.isBefore(to) &&
              terms.any((t) => p.title.toLowerCase().contains(t.toLowerCase())))
          .toList();
  @override
  Future<List<EpgProgram>> findSportsProgrammesForChannels(
          List<String> ids, DateTime from, DateTime to) async =>
      const [];
}

Channel _channel(String id, String name) => Channel(
      id: 'test::$id',
      rawId: id,
      playlistId: 'test',
      name: name,
      group: 'Sports',
      url: 'https://example.invalid/$id',
    );

EpgProgram _programme(String channelId, String title,
    {required Duration fromNow, required Duration length}) {
  final start = DateTime.now().add(fromNow);
  return EpgProgram(
      channelId: channelId,
      title: title,
      start: start,
      stop: start.add(length));
}

void main() {
  test('typed teams reach tonight listings, not just now and next', () async {
    final guide = _Guide([
      _programme('espn', 'Temple Owls vs UAB Blazers',
          fromNow: const Duration(hours: 4), length: const Duration(hours: 3)),
      _programme('espn2', 'Temple vs Army Black Knights',
          fromNow: const Duration(days: 3), length: const Duration(hours: 3)),
    ]);
    final matcher = SportsChannelMatcher(guide);
    await matcher.prepare([
      _channel('espn', 'US: ESPN HD'),
      _channel('espn2', 'US: ESPN 2 HD'),
    ]);
    final results = await matcher.searchWithGuide('temple');
    expect(results.map((r) => r.channel.rawId), ['espn']);
    expect(results.single.programmeSearchHit, isTrue);
    expect(results.single.programme?.title, contains('Temple Owls'));
    // The shared opponent term reaches the same listing.
    final uab = await matcher.searchWithGuide('uab');
    expect(uab.map((r) => r.channel.rawId), ['espn']);
    // A listing past the day window stays out of reach.
    expect(results.any((r) => r.programme?.title.contains('Army') == true),
        isFalse);
  });

  test('short prefixes keep the now/next-only behavior', () async {
    final guide = _Guide([
      _programme('espn', 'Temple Owls vs UAB Blazers',
          fromNow: const Duration(hours: 4), length: const Duration(hours: 3)),
    ]);
    final matcher = SportsChannelMatcher(guide);
    await matcher.prepare([_channel('espn', 'US: ESPN HD')]);
    expect(await matcher.searchWithGuide('te'), isEmpty);
  });
}
