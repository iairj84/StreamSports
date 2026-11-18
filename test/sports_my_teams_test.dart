import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nox_iptv/models/epg_program.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/models/sports_progress.dart';
import 'package:nox_iptv/screens/sports_screen.dart';
import 'package:nox_iptv/services/app_preferences.dart';
import 'package:nox_iptv/services/catalog_database.dart';
import 'package:nox_iptv/services/epg_service.dart';
import 'package:nox_iptv/services/playback_service.dart';
import 'package:nox_iptv/services/playlist_manager.dart';
import 'package:nox_iptv/services/sports_channel_matcher.dart';
import 'package:nox_iptv/services/sports_service.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/utils/route_observer.dart';
import 'package:nox_iptv/utils/tv_theme.dart';
import 'package:nox_iptv/widgets/player_scores_panel.dart';

class _Scores extends SportsService {
  _Scores(this.start)
      : super.withClient(MockClient((_) async => http.Response('{}', 200)));
  final DateTime start;

  SportsGame game(String id, String homeId, String homeName,
      {GameState state = GameState.pre}) {
    final league = sportsLeagueById('nhl')!;
    return SportsGame(
      id: id,
      league: league,
      start: start.add(const Duration(hours: 2)),
      state: state,
      statusText: state == GameState.live ? 'Live' : 'Scheduled',
      home: SportsTeam(
          id: homeId,
          name: homeName,
          shortName: homeName,
          abbreviation: homeName.substring(0, 3).toUpperCase(),
          record: '10-2-0',
          score: '3'),
      away: const SportsTeam(
          id: 'visitors',
          name: 'Visitors',
          shortName: 'Visitors',
          abbreviation: 'VIS',
          record: '8-4-0',
          score: '1'),
    );
  }

  @override
  Future<List<SportsGame>> gamesForDay(List<SportsLeague> leagues, DateTime day,
      {void Function(List<SportsGame>)? onProgress,
      bool forceRefresh = false,
      void Function(SportsWorkProgress)? onStatus}) async {
    if (leagues.isEmpty) return const [];
    return [
      game('followed-game', 'bos', 'Boston', state: GameState.live),
      game('other-game', 'nyr', 'Rangers', state: GameState.live),
    ];
  }

  @override
  Future<DateTime?> nextGameStart(SportsLeague league, DateTime from) async =>
      null;

  @override
  Future<List<SportsGame>> gamesForDayWhileActive(
          List<SportsLeague> leagues, DateTime day,
          {required bool Function() shouldContinue,
          bool forceRefresh = false,
          void Function(List<SportsGame>)? onProgress,
          void Function(SportsWorkProgress)? onStatus}) =>
      gamesForDay(leagues, day,
          forceRefresh: forceRefresh,
          onProgress: onProgress,
          onStatus: onStatus);
}

class _Playlist extends PlaylistManager {
  _Playlist(super.storage, super.db);
  @override
  Future<void> ensureLiveChannelsLoaded() async {}
}

class _Playback extends PlaybackService {
  _Playback(super.storage, super.playlist);
}

class _Epg extends EpgService {
  _Epg(super.storage);
  @override
  Future<List<EpgProgram>> findSportsProgrammesForChannels(
          List<String> ids, DateTime from, DateTime to) async =>
      const [];
  @override
  Future<Map<String, List<EpgProgram>>> sportsGuideSlice(
          Iterable<String> channelIds) async =>
      const {};
  @override
  Iterable<EpgProgram> cachedCurrentProgrammes(DateTime now) => const [];
  @override
  Future<List<EpgProgram>> findProgrammesByTitle(
          DateTime from, DateTime to, List<String> terms,
          {List<String>? channelIds}) async =>
      const [];
  @override
  List<EpgProgram> getPrograms(String channelId) => const [];
  @override
  EpgProgram? getCurrentProgram(String channelId) => null;
  @override
  EpgProgram? getNextProgram(String channelId) => null;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 16));
    if (!tester.binding.hasScheduledFrame) break;
  }
  await tester.pumpAndSettle();
}

Future<(StorageService, AppPreferences, _Playlist, _Playback, _Epg)>
    _harness() async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();
  await storage.setSportsLeagues(['nhl']);
  await storage.setSportsChannelFilter('all');
  await storage.setSportsOnlineExtras(false);
  final prefs = AppPreferences(storage);
  await prefs.init();
  prefs.isTelevision = true;
  addTearDown(prefs.dispose);
  final playlist = _Playlist(storage, CatalogDatabase());
  return (
    storage,
    prefs,
    playlist,
    _Playback(storage, playlist),
    _Epg(storage)
  );
}

Finder myTeamsHeading() => find.byKey(const ValueKey('my-teams-heading'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  tearDown(SportsChannelMatcher.disposeShared);
  setUp(SportsService.resetForTesting);
  tearDown(SportsService.resetForTesting);

  testWidgets('events opens with a my teams row above the sport rows',
      (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (storage, prefs, playlist, playback, guide) = await _harness();
    await storage.setSportsFollowedTeams(['nhl|bos']);
    final start = DateTime(2026, 11, 18, 12);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider.value(value: storage),
          ChangeNotifierProvider.value(value: prefs),
          ChangeNotifierProvider<PlaylistManager>.value(value: playlist),
          ChangeNotifierProvider<PlaybackService>.value(value: playback),
          ChangeNotifierProvider<EpgService>.value(value: guide),
        ],
        child: MaterialApp(
            theme: buildAppTheme(prefs.palette),
            navigatorObservers: [appRouteObserver],
            home: SportsScreen(scores: _Scores(start), clock: () => start))));
    await settle(tester);

    expect(myTeamsHeading(), findsOneWidget);
    final sportHeading = find.byKey(const ValueKey('sport-heading:hockey'));
    await tester.scrollUntilVisible(
      sportHeading,
      200,
      scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('sports-events')),
          matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.vertical)),
    );
    await tester.pumpAndSettle();
    final myTeamsDy = tester.getTopLeft(myTeamsHeading()).dy;
    final sportDy = tester.getTopLeft(sportHeading).dy;
    expect(myTeamsDy, lessThan(sportDy),
        reason: 'My Teams sits above the sport rows.');
    // The followed game appears in both rows under its own card identity;
    // the unfollowed game never enters My Teams.
    expect(find.byKey(const ValueKey('card-my-teams:nhl:followed-game')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('card-nhl:followed-game')), findsOneWidget);
    expect(find.byKey(const ValueKey('card-nhl:other-game')), findsOneWidget);
    expect(find.byKey(const ValueKey('card-my-teams:nhl:other-game')),
        findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    SportsChannelMatcher.disposeShared();
    playback.dispose();
    playlist.dispose();
    guide.dispose();
    // Past the matcher worker's idle leash (20 minutes) so its release
    // timer cannot outlive the tree.
    await tester.pump(const Duration(minutes: 21));
  });

  testWidgets('no followed teams means no my teams row', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (storage, prefs, playlist, playback, guide) = await _harness();
    final start = DateTime(2026, 11, 18, 12);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider.value(value: storage),
          ChangeNotifierProvider.value(value: prefs),
          ChangeNotifierProvider<PlaylistManager>.value(value: playlist),
          ChangeNotifierProvider<PlaybackService>.value(value: playback),
          ChangeNotifierProvider<EpgService>.value(value: guide),
        ],
        child: MaterialApp(
            theme: buildAppTheme(prefs.palette),
            navigatorObservers: [appRouteObserver],
            home: SportsScreen(scores: _Scores(start), clock: () => start))));
    await settle(tester);

    expect(myTeamsHeading(), findsNothing);
    expect(find.byKey(const ValueKey('sport-heading:hockey')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    SportsChannelMatcher.disposeShared();
    playback.dispose();
    playlist.dispose();
    guide.dispose();
    // Past the matcher worker's idle leash (20 minutes) so its release
    // timer cannot outlive the tree.
    await tester.pump(const Duration(minutes: 21));
  });

  testWidgets('scores panel cycles through a my teams scope', (tester) async {
    final (storage, _, playlist, _, _) = await _harness();
    await storage.setSportsFollowedTeams(['nhl|bos']);
    final start = DateTime(2026, 11, 18, 12);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider.value(value: storage),
          ChangeNotifierProvider<PlaylistManager>.value(value: playlist),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: PlayerScoresPanel(
                    scores: _Scores(start), onClose: () {}, onPlay: (_) {})))));
    await settle(tester);

    expect(find.text('My Teams'), findsOneWidget);
    expect(find.text('BOS'), findsWidgets);
    expect(find.text('RAN'), findsWidgets);
    // The row opens on Live; two steps down (All, then My Teams) leaves only
    // the followed game on screen.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('BOS'), findsOneWidget);
    expect(find.text('RAN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scores panel reopens on the remembered my teams scope',
      (tester) async {
    final (storage, _, playlist, _, _) = await _harness();
    await storage.setSportsFollowedTeams(['nhl|bos']);
    await storage.setSportsScoresScope('my-teams');
    final start = DateTime(2026, 11, 18, 12);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider.value(value: storage),
          ChangeNotifierProvider<PlaylistManager>.value(value: playlist),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: PlayerScoresPanel(
                    scores: _Scores(start), onClose: () {}, onPlay: (_) {})))));
    await settle(tester);

    // Remembered My Teams wins over the Live-first default.
    expect(find.text('BOS'), findsOneWidget);
    expect(find.text('RAN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scores panel hides only my teams scores when toggled',
      (tester) async {
    final (storage, _, playlist, _, _) = await _harness();
    await storage.setSportsFollowedTeams(['nhl|bos']);
    await storage.setSportsHideMyTeamsScores(true);
    final start = DateTime(2026, 11, 18, 12);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider.value(value: storage),
          ChangeNotifierProvider<PlaylistManager>.value(value: playlist),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: PlayerScoresPanel(
                    scores: _Scores(start), onClose: () {}, onPlay: (_) {})))));
    await settle(tester);

    // Down to All so both games are on screen: the followed game shows
    // records, the other game still shows its score.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('10-2-0'), findsOneWidget);
    expect(find.text('3'), findsOneWidget,
        reason: 'Only the unfollowed game keeps its score.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('scores panel hides the my teams scope without follows',
      (tester) async {
    final (storage, _, playlist, _, _) = await _harness();
    final start = DateTime(2026, 11, 18, 12);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider.value(value: storage),
          ChangeNotifierProvider<PlaylistManager>.value(value: playlist),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: PlayerScoresPanel(
                    scores: _Scores(start), onClose: () {}, onPlay: (_) {})))));
    await settle(tester);

    expect(find.text('My Teams'), findsNothing);
    expect(find.text('All'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
