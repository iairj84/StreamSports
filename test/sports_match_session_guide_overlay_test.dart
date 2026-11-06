import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/services/sports_channel_matcher.dart';
import 'package:nox_iptv/services/sports_guide_overlay.dart';
import 'package:nox_iptv/services/sports_match_inputs.dart';
import 'package:nox_iptv/services/sports_match_session.dart';

class _NoPicks implements SportsMatchPicks {
  const _NoPicks();
  @override
  String? channelIdFor(SportsGame game) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final league = sportsLeagueById('eng.1')!;
  final now = DateTime.now();

  SportsGame fixture() => SportsGame(
      id: 'espn-1',
      league: league,
      start: now.add(const Duration(hours: 1)),
      end: now.add(const Duration(hours: 3)),
      state: GameState.pre,
      statusText: 'Scheduled',
      home: const SportsTeam(
          id: 'h',
          name: 'Arsenal',
          shortName: 'Arsenal',
          abbreviation: 'ARS',
          score: '0'),
      away: const SportsTeam(
          id: 'a',
          name: 'Chelsea',
          shortName: 'Chelsea',
          abbreviation: 'CHE',
          score: '0'));

  Channel channel(String epg) => Channel(
      id: 'playlist::$epg',
      rawId: epg,
      playlistId: 'playlist',
      name: 'ESPN',
      group: 'Sports',
      url: 'http://localhost/stream',
      epgIdOverride: epg);

  setUp(() => SportsGuideOverlay.instance.clear());
  tearDown(() => SportsGuideOverlay.instance.clear());

  test('a completed confident match retitles its channel in the guide', () {
    final game = fixture();
    final session = SportsMatchSession();
    session.updateInputs([game], const _NoPicks(), 7, now);
    final key = SportsChannelPicks.eventKey(game);
    expect(session.identities, contains(key));

    final changed = session.apply(
        {
          key: [ChannelMatch(channel('espn.us'), MatchReason.name, 900)]
        },
        session.identities,
        7,
        now,
        complete: true);

    expect(changed, isTrue);
    final rows = SportsGuideOverlay.instance.programmesFor('espn.us');
    expect(rows, isNotNull);
    expect(rows!.single.title, 'Arsenal vs Chelsea');
  });

  test('possible coverage and manual picks are never published', () {
    final game = fixture();
    final session = SportsMatchSession();
    session.updateInputs([game], const _NoPicks(), 7, now);
    final key = SportsChannelPicks.eventKey(game);

    session.apply(
        {
          key: [
            ChannelMatch(channel('possible.us'), MatchReason.league, 300)
          ]
        },
        session.identities,
        7,
        now,
        complete: true);
    expect(SportsGuideOverlay.instance.programmesFor('possible.us'), isNull);

    session.apply(
        {
          key: [ChannelMatch(channel('picked.us'), MatchReason.pick, 1000)]
        },
        session.identities,
        7,
        now,
        complete: true);
    expect(SportsGuideOverlay.instance.programmesFor('picked.us'), isNull);
  });
}
