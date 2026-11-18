import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/screens/sports_league_manager_screen.dart';
import 'package:nox_iptv/services/app_preferences.dart';
import 'package:nox_iptv/services/sports_follows.dart';
import 'package:nox_iptv/services/sports_service.dart';
import 'package:nox_iptv/services/sports_standings_service.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/utils/tv_theme.dart';
import 'package:nox_iptv/widgets/compact_choice_list.dart';

class _Standings extends SportsStandingsService {
  int loads = 0;

  @override
  Future<LeagueStandings> load(SportsLeague league,
      {bool refresh = false, bool rememberSelection = true}) async {
    loads++;
    return const LeagueStandings(tables: [
      StandingTable('Teams', [
        StandingTeam(
            SportsTeam(
                id: 'nyy',
                name: 'New York Yankees',
                shortName: 'Yankees',
                abbreviation: 'NYY'),
            <String, String>{},
            1),
        StandingTeam(
            SportsTeam(
                id: 'bos',
                name: 'Boston Red Sox',
                shortName: 'Red Sox',
                abbreviation: 'BOS'),
            <String, String>{},
            2),
      ])
    ], season: '2026');
  }
}

Future<void> open(
  WidgetTester tester,
  StorageService storage,
  AppPreferences prefs, {
  SportsStandingsService? standings,
  SportsFollows? follows,
}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<StorageService>.value(value: storage),
      ChangeNotifierProvider<AppPreferences>.value(value: prefs),
    ],
    child: MaterialApp(
        theme: buildAppTheme(prefs.palette),
        home: Scaffold(
            body: SportsLeagueManagerScreen(
                embedded: true, standings: standings, follows: follows))),
  ));
  await tester.pumpAndSettle();
}

/// Rows are lazily built, so a sport may be off screen until scrolled to.
Future<void> tapRow(WidgetTester tester, String id) async {
  final row = find.byKey(ValueKey(id));
  await tester.scrollUntilVisible(row, 200,
      scrollable: find
          .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
          .first);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

List<String> ids(WidgetTester tester) => tester
    .widget<CompactChoiceList>(find.byType(CompactChoiceList))
    .choices
    .map((c) => c.id)
    .toList();

Future<(StorageService, AppPreferences)> harness({
  List<String> shown = const ['nfl'],
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();
  await storage.setSportsLeagues(shown);
  // Guide channels are automatic, not part of the sport tree's selection.
  await storage.setHiddenGuideLeagues(
      kAutomaticSportsLeagues.map((l) => l.id).toList());
  final prefs = AppPreferences(storage);
  await prefs.init();
  addTearDown(prefs.dispose);
  return (storage, prefs);
}

void main() {
  testWidgets('sports are listed US-first and open in place', (tester) async {
    final (storage, prefs) = await harness();
    await open(tester, storage, prefs);

    final before = ids(tester);
    expect(
        before.where((id) => id.startsWith('sport:')).take(5), [
      'sport:football',
      'sport:basketball',
      'sport:baseball',
      'sport:hockey',
      'sport:soccer',
    ], reason: 'A US viewer reaches for these sports first.');
    expect(before.where((id) => id.startsWith('sport:')), hasLength(greaterThan(5)));
    expect(before, contains('nfl'),
        reason: 'A sport you already show starts open.');
    expect(before, isNot(contains('mlb')),
        reason: 'Closed sports cost one row, not their whole catalogue.');

    await tapRow(tester, 'sport:baseball');
    expect(ids(tester), contains('mlb'));
    expect(ids(tester), contains('nfl'),
        reason: 'Opening another sport does not close the first.');

    await tapRow(tester, 'sport:baseball');
    expect(ids(tester), isNot(contains('mlb')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a league in a closed sport is one search away', (tester) async {
    final (storage, prefs) = await harness();
    await open(tester, storage, prefs);
    expect(ids(tester), isNot(contains('nba')));

    await tester.enterText(
        find.byKey(const ValueKey('league-manager-search')), 'NBA');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nba')), findsOneWidget,
        reason: 'Search crosses every sport, open or closed.');

    await tester.tap(find.byKey(const ValueKey('nba')));
    await tester.pumpAndSettle();
    expect(savedSportsLeagues(storage).map((l) => l.id), containsAll(['nfl', 'nba']));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Teams tab unfollows a team and offers undo', (tester) async {
    final (storage, prefs) = await harness();
    final follows = SportsFollows.load(storage);
    await follows.follow('mlb', 'nyy', name: 'New York Yankees');
    await open(tester, storage, prefs, follows: follows);

    await tester.tap(find.text('Teams'));
    await tester.pumpAndSettle();
    expect(find.text('New York Yankees'), findsOneWidget);

    await tester.tap(find.text('New York Yankees'));
    await tester.pumpAndSettle();
    expect(follows.isFollowed('mlb', 'nyy'), isFalse);
    expect(find.text('Removed New York Yankees'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(follows.isFollowed('mlb', 'nyy'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add team follows a team straight from its league table',
      (tester) async {
    final (storage, prefs) = await harness();
    final standings = _Standings();
    await open(tester, storage, prefs, standings: standings);

    await tester.tap(find.text('Teams'));
    await tester.pumpAndSettle();
    expect(find.text('No teams followed yet'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-team')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-team-sport-baseball')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-team-league-mlb')));
    await tester.pumpAndSettle();

    expect(standings.loads, 1);
    await tester.tap(find.byKey(const ValueKey('nyy')));
    await tester.pumpAndSettle();
    expect(storage.getSportsFollowedTeams(), contains('mlb|nyy'));

    await tester.tap(find.byKey(const ValueKey('close-team-picker')));
    await tester.pumpAndSettle();
    expect(find.text('New York Yankees'), findsOneWidget,
        reason: 'The followed list reflects the picker immediately.');
    expect(tester.takeException(), isNull);
  });
}
