import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/services/live_sports_channels.dart';
import 'package:nox_iptv/services/sports_channel_matcher.dart';

void main() {
  final now = DateTime(2026, 11, 20, 19);
  final league = sportsLeagueById('nhl')!;

  SportsGame game(String id, String size, DateTime start,
          {String? homeScore,
          String? awayScore,
          String status = 'Live'}) =>
      SportsGame(
          id: id,
          league: league,
          start: start,
          state: GameState.live,
          statusText: status,
          home: SportsTeam(
              id: 'home-$size',
              name: 'Home $size',
              shortName: 'Home $size',
              abbreviation: 'H',
              score: homeScore),
          away: SportsTeam(
              id: 'away-$size',
              name: 'Away $size',
              shortName: 'Away $size',
              abbreviation: 'A',
              score: awayScore));

  Channel channel(String id) => Channel(
      id: id,
      rawId: id,
      playlistId: 'test',
      name: 'Feed $id',
      group: 'Sports',
      url: 'https://example.invalid/never-play');

  test('followed teams lead, then kick-off order', () {
    final early = game('early', 'A', now);
    final late = game('late', 'B', now.add(const Duration(hours: 1)));
    final rows = LiveSportsChannels.rowsFor(
      [
        (
          game: early,
          matches: [ChannelMatch(channel('one'), MatchReason.guide, 500)]
        ),
        (
          game: late,
          matches: [ChannelMatch(channel('two'), MatchReason.guide, 500)]
        ),
      ],
      involves: (g) => g.id == 'late',
    );
    expect(rows.map((c) => c.id), ['two', 'one']);
  });

  test('one row per channel when two games share a feed', () {
    final first = game('first', 'A', now);
    final second = game('second', 'B', now);
    final feed = channel('feed');
    final rows = LiveSportsChannels.rowsFor(
      [
        (game: first, matches: [ChannelMatch(feed, MatchReason.guide, 500)]),
        (game: second, matches: [ChannelMatch(feed, MatchReason.guide, 500)]),
      ],
      involves: (_) => false,
    );
    expect(rows, hasLength(1));
    expect(rows.single.id, 'feed');
  });

  test('the rank order decides which channel represents a game', () {
    final target = game('target', 'A', now);
    final guide = channel('guide');
    final picked = channel('picked');
    final rows = LiveSportsChannels.rowsFor(
      [
        (
          game: target,
          matches: [
            ChannelMatch(picked, MatchReason.pick, 1000),
            ChannelMatch(guide, MatchReason.guide, 500),
          ]
        ),
      ],
      involves: (_) => false,
    );
    expect(rows.single.id, 'picked');
  });

  test('the Sunday lead channel heads the rows and is never duplicated', () {
    final redZone = channel('redzone');
    final rows = LiveSportsChannels.rowsFor(
      [
        (
          game: game('game', 'A', now),
          matches: [ChannelMatch(redZone, MatchReason.pick, 1000)]
        ),
      ],
      involves: (_) => true,
      lead: redZone,
    );
    expect(rows.map((c) => c.id), ['redzone']);
  });

  test('the label reads the leading side and both scores', () {
    final scored = game('scored', 'A', now, homeScore: '88', awayScore: '84');
    expect(
        LiveSportsChannels.scoreLabelFor(scored,
            hideScores: false, hideMyTeams: false, followed: false),
        // Away at home: the model's first side is the away team here.
        'A 84–88');
  });

  test('hidden scores fall back to the provider clock', () {
    final scored = game('scored', 'A', now,
        homeScore: '88', awayScore: '84', status: 'Q3 4:12');
    expect(
        LiveSportsChannels.scoreLabelFor(scored,
            hideScores: true, hideMyTeams: false, followed: false),
        'Q3 4:12');
    expect(
        LiveSportsChannels.scoreLabelFor(scored,
            hideScores: false, hideMyTeams: true, followed: true),
        'Q3 4:12');
    expect(
        LiveSportsChannels.scoreLabelFor(scored,
            hideScores: false, hideMyTeams: true, followed: false),
        'A 84–88');
  });

  test('an unscored event shows its clock instead of an empty score', () {
    final race = game('race', 'A', now, status: 'Lap 40/70');
    expect(
        LiveSportsChannels.scoreLabelFor(race,
            hideScores: false, hideMyTeams: false, followed: false),
        'Lap 40/70');
  });
}
