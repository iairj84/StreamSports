import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/screens/sports_league_manager_screen.dart';
import 'package:nox_iptv/services/app_preferences.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(StorageService storage, AppPreferences prefs) => MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storage),
        ChangeNotifierProvider<AppPreferences>.value(value: prefs),
      ],
      child: const MaterialApp(
          home: Scaffold(body: SportsLeagueManagerScreen(embedded: true))),
    );

Future<void> openManager(WidgetTester tester, StorageService storage) async {
  tester.view.physicalSize = const Size(960, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final prefs = AppPreferences(storage);
  await prefs.init();
  await tester.pumpWidget(app(storage, prefs));
  await tester.pumpAndSettle();
}

Future<void> tapLeague(WidgetTester tester, String name) async {
  final row = find.text(name).first;
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

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

  test('a pick declares the full list it narrows', () {
    expect(sportsLeagueById('college-football.sec')?.parentLeagueId,
        'college-football');
    expect(sportsLeagueById('college-football.top25')?.parentLeagueId,
        'college-football');
    expect(sportsLeagueById('basketball.sec')?.parentLeagueId,
        'basketball.mens-college-basketball');
    expect(sportsLeagueById('college-football')?.parentLeagueId, isNull);
    expect(sportsLeagueById('basketball.mens-college-basketball')
        ?.parentLeagueId, isNull);
    expect(sportsLeagueById('nfl')?.parentLeagueId, isNull,
        reason: 'Ordinary leagues are their own full list.');
  });

  testWidgets('picking a conference replaces college football', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setSportsLeagues(['college-football', 'nfl']);
    await openManager(tester, storage);

    await tapLeague(tester, 'SEC Football');
    expect(storage.getSportsLeagues(), contains('college-football.sec'));
    expect(storage.getSportsLeagues(), isNot(contains('college-football')),
        reason: 'A conference narrows the full list instead of stacking on it.');
    expect(storage.getSportsLeagues(), contains('nfl'),
        reason: 'Other sports are untouched.');
    expect(find.text('Included in College Football'), findsNothing);
  });

  testWidgets('showing college football again covers the conference',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setSportsLeagues(['college-football.sec']);
    await openManager(tester, storage);

    await tapLeague(tester, 'College Football');
    expect(storage.getSportsLeagues(), contains('college-football'));
    expect(storage.getSportsLeagues(), isNot(contains('college-football.sec')),
        reason: 'The full list already includes every conference.');
  });
}
