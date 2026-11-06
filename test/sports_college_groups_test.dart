import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/sports.dart';

void main() {
  test('college conferences are optional leagues bound to an ESPN group', () {
    final conferences =
        kCollegeGroupLeagues.where((l) => l.espnGroup != null).toList();
    expect(conferences, isNotEmpty);
    expect(conferences.map((l) => l.id).toSet().length, conferences.length,
        reason: 'Every conference needs its own id to be selectable.');
    for (final league in conferences) {
      expect(league.espnPath,
          anyOf('football/college-football', 'basketball/mens-college-basketball'),
          reason: '${league.id} must stay on a college scoreboard.');
      expect(league.enabledByDefault, isFalse,
          reason: '${league.id} is an extra feed, never startup traffic.');
      expect(league.hasStandings, isFalse,
          reason: '${league.id} reuses the parent league for standings.');
      expect(league.region, 'Conference');
    }
  });

  test('poll views keep only ranked games and name their sport', () {
    final polls = kCollegeGroupLeagues.where((l) => l.rankedOnly).toList();
    expect(polls.map((l) => l.id).toSet(),
        {'college-football.top25', 'basketball.mens-college-basketball.top25'});
    for (final league in polls) {
      expect(league.espnGroup, isNull,
          reason: '${league.id} reads the whole division scoreboard.');
      expect(league.region, 'Top 25');
      expect(league.enabledByDefault, isFalse);
    }
  });

  test('college picks resolve like any other league and stay off by default',
      () {
    for (final league in kCollegeGroupLeagues) {
      expect(sportsLeagueById(league.id), same(league));
      expect(kDefaultSportsLeagueIds, isNot(contains(league.id)));
    }
    expect(sportsLeagueById('college-football.sec')?.espnGroup, '8');
    expect(sportsLeagueById('basketball.sec')?.espnGroup, '23');
  });
}
