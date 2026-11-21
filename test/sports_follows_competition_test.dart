import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/services/sports_follows.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A team followed from one college view must count in every other view of the
/// same competition: "ACC Football" and "College Football" are one scoreboard,
/// and the same game arrives labelled with whichever the viewer shows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SportsFollows> followsFor(List<String> keys) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setSportsFollowedTeams(keys);
    return SportsFollows.load(storage);
  }

  SportsGame game(SportsLeague league, SportsTeam home, SportsTeam away) =>
      SportsGame(
          id: '${league.id}:${home.id}',
          league: league,
          start: DateTime.utc(2026, 11, 21, 20),
          state: GameState.pre,
          statusText: '8:00 PM',
          home: home,
          away: away);

  const clemson = SportsTeam(
      id: '228',
      name: 'Clemson Tigers',
      shortName: 'Clemson',
      abbreviation: 'CLEM');
  const oregon = SportsTeam(
      id: '2483',
      name: 'Oregon Ducks',
      shortName: 'Oregon',
      abbreviation: 'ORE');
  const miami = SportsTeam(
      id: '2390',
      name: 'Miami Hurricanes',
      shortName: 'Miami',
      abbreviation: 'MIA');

  SportsLeague league(String id) => sportsLeagueById(id)!;

  test('a team followed in the full list counts in a conference view',
      () async {
    final follows = await followsFor(['college-football|228']);

    expect(follows.involves(game(league('college-football'), clemson, miami)),
        isTrue);
    expect(
        follows.involves(game(league('college-football.acc'), clemson, miami)),
        isTrue,
        reason: 'the ACC view publishes the same Clemson game');
  });

  test('a team followed in a conference view counts in the full list',
      () async {
    final follows = await followsFor(['college-football.bigten|2483']);

    expect(
        follows
            .involves(game(league('college-football.bigten'), oregon, miami)),
        isTrue);
    expect(follows.involves(game(league('college-football'), oregon, miami)),
        isTrue,
        reason: 'the full College Football list publishes the same game');
  });

  test('the other side of a followed game is not followed', () async {
    final follows = await followsFor(['college-football|228']);

    expect(follows.involves(game(league('college-football'), miami, oregon)),
        isFalse);
  });

  test('a poll view belongs to the same competition', () async {
    final follows = await followsFor(['college-football|228']);

    expect(
        follows
            .involves(game(league('college-football.top25'), clemson, miami)),
        isTrue);
  });

  test('the same team id in another competition stays unfollowed', () async {
    final follows = await followsFor(['college-football|228']);

    expect(follows.involves(game(league('nfl'), clemson, miami)), isFalse,
        reason: 'team ids repeat across sports');
  });

  test('two followed teams in different conferences both count', () async {
    final follows = await followsFor(
        ['college-football.acc|228', 'college-football.bigten|2483']);
    final games = [
      game(league('college-football'), clemson, miami),
      game(league('college-football'), oregon, miami),
    ];

    expect(games.where(follows.involves), hasLength(2));
  });
}
