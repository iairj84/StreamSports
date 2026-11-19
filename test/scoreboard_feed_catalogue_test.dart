import 'package:flutter_test/flutter_test.dart';

import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/services/scoreboard_feeds.dart';

/// The scoreboard pipeline reads one catalogue for its capability answer, the
/// request it builds, its cache key, its expiry rule and its parser. These
/// tests keep that catalogue honest: a new league is one entry, and an entry
/// that is incomplete, duplicated or mislabelled fails here rather than in the
/// field.
void main() {
  final day = DateTime(2026, 3, 14);
  final league = sportsLeagueById('racing.f1')!;

  test('each feed is filed under the source it serves', () {
    for (final entry in kScoreboardFeeds.entries) {
      expect(entry.value.source, entry.key);
      if (entry.value.calendarOnly) {
        expect(entry.value.parse, isNull, reason: entry.key);
        expect(entry.value.uri, isNull, reason: entry.key);
      } else {
        expect(entry.value.parse, isNotNull, reason: entry.key);
        expect(entry.value.uri, isNotNull, reason: entry.key);
      }
    }
  });

  test('no two requested feeds share an address for the same day', () {
    final seen = <String, String>{};
    for (final entry in kScoreboardFeeds.entries) {
      final uri = entry.value.uri?.call(day, league);
      if (uri == null) continue;
      final address = '${uri.host}${uri.path}';
      expect(seen[address], isNull,
          reason: '${entry.key} and ${seen[address]} both request $address');
      seen[address] = entry.key;
    }
  });

  test('every league the catalogue scores can be scored', () {
    for (final l in [...kSportsLeagues, ...kSportsLeagueBank]) {
      if (!kScoreboardFeeds.containsKey(l.source)) continue;
      final feed = scoreboardFeedFor(l);
      expect(feed.source, l.source);
      expect(supportsSportsScoreboard(l), !feed.calendarOnly, reason: l.id);
      expect(supportsSportsSchedule(l), isTrue, reason: l.id);
    }
  });

  test('an unknown source is unsupported but still parses as ESPN', () {
    // A league saved by a newer build: it must keep showing as unsupported
    // instead of requesting a path this build cannot score.
    const future = SportsLeague(
      id: 'future.league',
      espnPath: 'future/league',
      name: 'Future League',
      shortName: 'Future',
      logoUrl: '',
      source: 'Future Feed',
    );
    expect(supportsSportsScoreboard(future), isFalse);
    expect(supportsSportsSchedule(future), isFalse);
    expect(scoreboardFeedFor(future).source, 'ESPN');
    expect(scoreboardFeedFor(future).parse, isNotNull);
  });

  test('ESPN answers for the leagues that name no provider', () {
    final espn = scoreboardFeedFor(league);
    expect(espn.source, 'ESPN');
    expect(supportsSportsScoreboard(league), isTrue);
    expect(espn.schedule, FeedSchedule.monthly);
    final uri = espn.uri!(day, league);
    expect(uri.host, 'site.api.espn.com');
    expect(uri.queryParameters['dates'], '20260314');
  });

  test('a calendar-only feed supplies fixtures but never scores', () {
    final race = sportsLeagueById('racing.motogp')!;
    expect(race.source, 'RaceTV Guide');
    final feed = scoreboardFeedFor(race);
    expect(feed.calendarOnly, isTrue);
    expect(supportsSportsScoreboard(race), isFalse);
    expect(supportsSportsSchedule(race), isTrue);
    expect(feed.schedule, FeedSchedule.motorsport);
  });

  group('cache identity and expiry', () {
    test('a daily feed is cached and judged by the day', () {
      expect(FeedWindow.day.cacheKey(day), '20260314');
      expect(FeedWindow.day.anchor(day, DateTime(2026, 3, 14)), day);
    });

    test('a monthly feed shares one reply per month, stale at month end', () {
      // K League and NPB publish a month at a time.
      expect(FeedWindow.month.cacheKey(day), '202603');
      expect(FeedWindow.month.anchor(day, DateTime(2026, 3, 14)),
          DateTime(2026, 3, 31));
      expect(FeedWindow.month.anchor(DateTime(2026, 2, 3), DateTime(2026, 2, 3)),
          DateTime(2026, 2, 28));
    });

    test('a season feed keys on its season and is judged by today', () {
      final today = DateTime(2026, 3, 14);
      expect(FeedWindow.season.cacheKey(day), '2025',
          reason: 'the ABL season starts mid-year');
      expect(FeedWindow.season.anchor(day, today), today);
    });

    test('a current-season feed replaces one shared reply', () {
      final today = DateTime(2026, 3, 14);
      expect(FeedWindow.currentSeason.cacheKey(day), 'current-season');
      expect(FeedWindow.currentSeason.anchor(day, today), today);
    });
  });

  test('each league asks for its own request shape', () {
    // One representative assertion per provider: URL, body and decoding are
    // the parts that silently break when a publisher changes its site.
    final kLeague = kScoreboardFeeds['K League']!;
    expect(kLeague.uri!(day, sportsLeagueById('kor.1')!).path,
        '/getScheduleList.do');
    expect(kLeague.postBody!(day, sportsLeagueById('kor.1')!),
        containsPair('leagueId', '1'));

    final kbo = kScoreboardFeeds['KBO']!;
    expect(kbo.uri!(day, league).queryParameters['searchDate'], '2026-03-14');

    final abl = kScoreboardFeeds['ABL']!;
    expect(abl.uri!(day, league).queryParameters['season'], '2025');

    final npb = kScoreboardFeeds['NPB']!;
    expect(npb.uri!(day, league).path, '/games/2026/schedule_03_detail.html');
    expect(npb.utf8Body, isTrue);

    final bleague = kScoreboardFeeds['B.League']!;
    expect(bleague.uri!(day, league).queryParameters['day'], '14');

    // The regional publishers answer with pages this app reads defensively.
    for (final source in ['NPB', 'KBO', 'ABL', 'B.League']) {
      expect(kScoreboardFeeds[source]!.boundedResponse, isTrue, reason: source);
    }
    // K League and EASL answer with bounded JSON; they keep the default read.
    for (final source in ['K League', 'EASL']) {
      expect(kScoreboardFeeds[source]!.boundedResponse, isFalse,
          reason: source);
    }
  });
}
