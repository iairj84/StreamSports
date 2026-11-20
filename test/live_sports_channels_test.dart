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
          String status = 'Live',
          SportsLeague? competition,
          SportsSituation? situation,
          SportsEventInfo? event}) =>
      SportsGame(
          id: id,
          league: competition ?? league,
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
              score: awayScore),
          situation: situation,
          event: event);

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

  test('the status line carries the score, the clock and who has the ball', () {
    final live = game('nfl', 'A', now,
        homeScore: '17',
        awayScore: '14',
        status: 'Q3 4:12',
        situation: const SportsSituation(text: '2nd & 7 at NE 32'));
    expect(
        LiveSportsChannels.gameStatusLine(live,
            hideScores: false, hideMyTeams: false, followed: false),
        'A 14\u201317 \u00b7 Q3 4:12 \u00b7 2nd & 7 at NE 32');
  });

  test('a hidden score leaves the clock without the ball', () {
    final live = game('nfl', 'A', now,
        homeScore: '17',
        awayScore: '14',
        status: 'Q3 4:12',
        situation: const SportsSituation(text: '2nd & 7 at NE 32'));
    expect(
        LiveSportsChannels.gameStatusLine(live,
            hideScores: true, hideMyTeams: false, followed: false),
        'Q3 4:12');
    expect(
        LiveSportsChannels.gameStatusLine(live,
            hideScores: false, hideMyTeams: true, followed: true),
        'Q3 4:12');
  });

  test('a game without a score yet keeps its status once', () {
    final live = game('nfl', 'A', now,
        status: 'Q3 4:12',
        situation: const SportsSituation(text: '2nd & 7 at NE 32'));
    expect(
        LiveSportsChannels.gameStatusLine(live,
            hideScores: false, hideMyTeams: false, followed: false),
        'Q3 4:12 \u00b7 2nd & 7 at NE 32');
  });

  test('a field event shows its leader where a team game shows possession',
      () {
    final open = game('rsm', 'A', now,
        status: 'Round 3',
        competition: sportsLeagueById('golf.pga'),
        event: const SportsEventInfo(
            title: 'RSM Classic',
            leaders: [
              SportsEventEntry(position: '1', name: 'S. Scheffler', value: '-12')
            ]));
    expect(
        LiveSportsChannels.gameStatusLine(open,
            hideScores: false, hideMyTeams: false, followed: false),
        'Round 3 \u00b7 Leader \u00b7 S. Scheffler \u00b7 -12');
  });

  test('an unscored event shows its clock instead of an empty score', () {
    final race = game('race', 'A', now, status: 'Lap 40/70');
    expect(
        LiveSportsChannels.scoreLabelFor(race,
            hideScores: false, hideMyTeams: false, followed: false),
        'Lap 40/70');
  });

  test('the guide cell spells both sides out, the leader strong', () {
    final scored = game('scored', 'A', now, homeScore: '52', awayScore: '31');
    expect(
        LiveSportsChannels.guideLines(scored,
            hideScores: false, hideMyTeams: false, followed: false),
        [
          [
            (text: 'Away A 31', strong: false),
            (text: ' / ', strong: false),
            (text: 'Home A 52', strong: true),
          ],
          [(text: 'Live', strong: false)],
        ]);
  });

  test('a tie leaves neither side strong', () {
    final level = game('level', 'A', now, homeScore: '31', awayScore: '31');
    expect(
        LiveSportsChannels.guideLines(level,
            hideScores: false, hideMyTeams: false, followed: false).first,
        [
          (text: 'Away A 31', strong: false),
          (text: ' / ', strong: false),
          (text: 'Home A 31', strong: false),
        ]);
  });

  test('a hidden score leaves the cell its status alone', () {
    final scored = game('scored', 'A', now,
        homeScore: '52', awayScore: '31', status: 'Q3 4:12');
    expect(
        LiveSportsChannels.guideLines(scored,
            hideScores: true, hideMyTeams: false, followed: false),
        [
          [(text: 'Q3 4:12', strong: false)]
        ]);
  });

  test('a cell without a score yet keeps the clock and who has the ball', () {
    final live = game('nfl', 'A', now,
        status: 'Q3 4:12',
        situation: const SportsSituation(text: '2nd & 7 at NE 32'));
    expect(
        LiveSportsChannels.guideLines(live,
            hideScores: false, hideMyTeams: false, followed: false),
        [
          [(text: 'Q3 4:12 \u00b7 2nd & 7 at NE 32', strong: false)]
        ]);
  });

  test('a field event fills the cell with its leader', () {
    final open = game('rsm', 'A', now,
        status: 'Round 3',
        competition: sportsLeagueById('golf.pga'),
        event: const SportsEventInfo(
            title: 'RSM Classic',
            leaders: [
              SportsEventEntry(position: '1', name: 'S. Scheffler', value: '-12')
            ]));
    expect(
        LiveSportsChannels.guideLines(open,
            hideScores: false, hideMyTeams: false, followed: false),
        [
          [(text: 'Round 3 \u00b7 Leader \u00b7 S. Scheffler \u00b7 -12', strong: false)]
        ]);
  });
}
