import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/sports.dart';

/// The Scores tray kept rendering the same game twice: an id-keyed dedupe only
/// collapses copies that agree on the provider's event id, and the two views of
/// one scoreboard do not always agree.
void main() {
  const collegeFootball = SportsLeague(
      id: 'college-football',
      espnPath: 'football/college-football',
      name: 'College Football',
      shortName: 'NCAAF',
      logoUrl: '');
  const top25 = SportsLeague(
      id: 'college-football.top25',
      espnPath: 'football/college-football',
      name: 'Top 25 Football',
      shortName: 'CFB Top 25',
      logoUrl: '',
      rankedOnly: true);
  const georgia = SportsTeam(
      id: '61',
      name: 'Georgia Bulldogs',
      shortName: 'Georgia',
      abbreviation: 'UGA');
  const alabama = SportsTeam(
      id: '333',
      name: 'Alabama Crimson Tide',
      shortName: 'Alabama',
      abbreviation: 'ALA');

  final kickoff = DateTime.utc(2026, 11, 7, 21);

  SportsGame game({
    required String id,
    required SportsLeague league,
    DateTime? start,
    SportsTeam home = georgia,
    SportsTeam away = alabama,
  }) =>
      SportsGame(
          id: id,
          league: league,
          start: start ?? kickoff,
          state: GameState.post,
          statusText: 'Final',
          home: home,
          away: away);

  test('one scoreboard row from two feeds is one card', () {
    final cards = dedupeSportsEvents([
      game(id: '401628', league: collegeFootball),
      game(id: '401628', league: top25),
    ]);

    expect(cards, hasLength(1));
    expect(cards.single.league.rankedOnly, isFalse,
        reason: 'the conference label wins over the poll view');
  });

  test('the same fixture under two event ids is still one card', () {
    final cards = dedupeSportsEvents([
      game(id: '401628', league: collegeFootball),
      game(id: '401629', league: top25),
    ]);

    expect(cards, hasLength(1));
  });

  test('the two sides identify the fixture in either order', () {
    final cards = dedupeSportsEvents([
      game(id: '401628', league: collegeFootball),
      game(id: '401700', league: top25, home: alabama, away: georgia),
    ]);

    expect(cards, hasLength(1));
  });

  test('a doubleheader is two cards', () {
    final cards = dedupeSportsEvents([
      game(id: '401628', league: collegeFootball),
      game(
          id: '401628',
          league: collegeFootball,
          start: kickoff.add(const Duration(hours: 3))),
    ]);

    expect(cards, hasLength(2));
  });

  test('other fixtures at the same time are untouched', () {
    const ohioState = SportsTeam(
        id: '194',
        name: 'Ohio State Buckeyes',
        shortName: 'Ohio State',
        abbreviation: 'OSU');
    const michigan = SportsTeam(
        id: '130',
        name: 'Michigan Wolverines',
        shortName: 'Michigan',
        abbreviation: 'MICH');
    final cards = dedupeSportsEvents([
      game(id: '401628', league: collegeFootball),
      game(id: '401629', league: collegeFootball, home: ohioState, away: michigan),
    ]);

    expect(cards, hasLength(2));
  });

  test('rows without two named sides fall back to the event id', () {
    const placeholder = SportsTeam(
        id: '', name: 'Italian Grand Prix', shortName: 'Monza', abbreviation: '');
    const racing = SportsLeague(
        id: 'racing.f1',
        espnPath: 'racing/f1',
        name: 'Formula 1',
        shortName: 'F1',
        logoUrl: '',
        kind: SportsKind.racing);

    final cards = dedupeSportsEvents([
      game(id: 'race', league: racing, home: placeholder, away: placeholder),
      game(id: 'quali', league: racing, home: placeholder, away: placeholder),
    ]);

    expect(cards, hasLength(2),
        reason: 'sessions of one race weekend are separate cards');
  });

  test('the RedZone card survives alongside the games', () {
    final cards = dedupeSportsEvents([
      nflRedZoneGame(kickoff),
      game(id: '401628', league: collegeFootball),
    ]);

    expect(cards, hasLength(2));
  });
}
