import 'package:nox_iptv/models/sports_favorites_filter.dart';
import 'package:nox_iptv/widgets/sports_fixture_row.dart';
import 'package:nox_iptv/widgets/sports_schedule_panel.dart';
import 'package:nox_iptv/services/sports_standings_service.dart';
import 'package:nox_iptv/screens/sports_teams_screen.dart';
import 'package:nox_iptv/screens/sports_league_manager_screen.dart';
import 'package:nox_iptv/widgets/standings_team_tile.dart';
import 'sports_standings_service_test.dart' as standings_fixture;
import 'package:nox_iptv/widgets/sports_header_controls.dart';
import 'dart:io';
import 'package:nox_iptv/widgets/compact_choice_list.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/screens/sports_screen.dart';
import 'package:nox_iptv/widgets/player_controls.dart';
import 'package:nox_iptv/services/app_preferences.dart';
import 'package:nox_iptv/services/catalog_database.dart';
import 'package:nox_iptv/services/epg_service.dart';
import 'package:nox_iptv/services/playback_service.dart';
import 'package:nox_iptv/services/playlist_manager.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/services/sports_service.dart';
import 'package:nox_iptv/services/sports_channel_matcher.dart';
import 'package:nox_iptv/utils/route_observer.dart';
import 'package:nox_iptv/utils/tv_theme.dart';
import 'live_layout_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(SportsChannelMatcher.disposeShared);
  setUp(SportsService.resetForTesting);
  tearDown(SportsService.resetForTesting);
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final cache = await Directory.systemTemp.createTemp('iptv-layout-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => cache.path,
    );
    const fonts = String.fromEnvironment('LAYOUT_FONT_DIR');
    if (fonts.isEmpty) return;
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'Ahem': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf'
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(File('$fonts/${entry.value}')
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
      await loader.load();
    }
  });

  testWidgets(
      'Events retains its own scope while Schedule and Standings share browsing',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'sports_online_extras': false});
    final storage = StorageService();
    await storage.init();
    await storage.setSportsLeagues(['nhl', 'nba']);
    await storage.setSportsChannelFilter('all');
    final prefs = AppPreferences(storage);
    await prefs.init();
    prefs.isTelevision = false;
    final playlist = LayoutPlaylist(storage, CatalogDatabase());
    final playback = LayoutPlayback(storage, playlist);
    final guide = LayoutEpg(storage), scores = LayoutInlineScores();
    var standingsRequests = 0;
    final standings = SportsStandingsService(client: MockClient((_) async {
      standingsRequests++;
      return http.Response(standings_fixture.table(teams: 20), 200);
    }));
    addTearDown(standings.close);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider.value(value: storage),
          ChangeNotifierProvider.value(value: prefs),
          ChangeNotifierProvider<PlaylistManager>.value(value: playlist),
          ChangeNotifierProvider<PlaybackService>.value(value: playback),
          ChangeNotifierProvider<EpgService>.value(value: guide),
        ],
        child: RepaintBoundary(
            child: MaterialApp(
                theme: buildAppTheme(prefs.palette),
                navigatorObservers: [appRouteObserver],
                home: SportsScreen(
                    scores: scores,
                    standings: standings,
                    clock: () => scores.start)))));
    await settleSports(tester);
    Future<void> tapKey(String id) async {
      final item = find.byKey(ValueKey(id));
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      await tester.tap(item);
      await settleSports(tester);
    }

    expect(find.byKey(const ValueKey('sport-picker')), findsNothing);
    expect(find.byKey(const ValueKey('league-picker')), findsNothing);
    expect(find.byKey(const ValueKey('events-favorites-only')), findsNothing);
    final calls = scores.calls;
    await tapKey('leagues-gear');
    expect(find.text('Leagues & teams'), findsOneWidget);
    await captureSports(tester, const Size(390, 844), 'leagues-gear');
    await tapKey('close-leagues');
    expect(scores.calls, calls,
        reason: 'Opening the league list never refetches Events.');
    await tapKey('sports-view-schedule');
    final panel =
        tester.widget<SportsSchedulePanel>(find.byType(SportsSchedulePanel));
    expect(
        panel.overviewLeagues!.map((l) => l.id), containsAll(['nba', 'nhl']));
    expect(panel.overviewLeagues!.map((l) => l.id), isNot(contains('eng.1')),
        reason: 'Schedule offers the shown leagues, never the whole catalogue.');
    await tapKey('schedule-sport');
    await tapKey('basketball');
    expect(panel.browseState.sport, 'basketball');
    await tapKey('schedule-league');
    expect(find.text('Leagues & teams'), findsOneWidget);
    expect(find.byKey(const ValueKey('eng.1')), findsNothing);
    await tapKey('nba');
    expect(panel.browseState.leagueId, 'nba');
    await tapKey('schedule-league');
    await tapKey('__all_sports__');
    expect(panel.browseState.sport, isNull);
    expect(panel.browseState.leagueId, isNull);
    final loaded = scores.calls;
    await tapKey('sports-view-events');
    expect(find.byKey(const ValueKey('sport-picker')), findsNothing);
    expect(scores.calls, loaded,
        reason: 'Schedule browsing never narrows Events.');
    await tapKey('sports-view-standings');
    // Choosing a league in Standings carries through an intermediate tab.
    await tapKey('standings-sport');
    await tapKey('hockey');
    final leagueList = find.descendant(
        of: find.byType(Dialog), matching: find.byType(CompactChoiceList));
    final lastLeague =
        tester.widget<CompactChoiceList>(leagueList).choices.last;
    expect(tester.getRect(find.byKey(ValueKey(lastLeague.id))).bottom,
        lessThanOrEqualTo(tester.getRect(leagueList).bottom),
        reason:
            'A short list fits its last row without unnecessary scrolling.');
    await captureSports(tester, const Size(390, 844), 'standings-league-scope');
    await tapKey('nhl');
    await tapKey('sports-view-schedule');
    var schedule =
        tester.widget<SportsSchedulePanel>(find.byType(SportsSchedulePanel));
    expect(schedule.browseState.leagueId, 'nhl');
    expect(schedule.browseState.sport, 'hockey');
    // A sport-only change also reaches Standings, without opening Events first.
    await tapKey('schedule-sport');
    await tapKey('basketball');
    await tapKey('sports-view-standings');
    expect(
        tester
            .widget<SportsTeamsScreen>(find.byType(SportsTeamsScreen))
            .initialLeague
            ?.id,
        'nba');
    await tapKey('sports-view-events');
    final requestsBefore = standingsRequests;
    // Exploring a non-enabled league never silently enables a feed.
    await tapKey('sports-view-standings');
    await tapKey('standings-favorites-only');
    await tapKey('sports-favorites-all');
    await tapKey('standings-sport');
    await tapKey('soccer');
    await tapKey('eng.1');
    await tapKey('sports-view-schedule');
    schedule =
        tester.widget<SportsSchedulePanel>(find.byType(SportsSchedulePanel));
    expect(schedule.browseState.sport, 'soccer');
    expect(schedule.browseState.leagueId, 'eng.1');
    expect(storage.getSportsLeagues(), ['nhl', 'nba']);
    expect(standingsRequests, requestsBefore + 1);
    // Merely revisiting Standings retains its cached league and requests no data.
    await tapKey('sports-view-standings');
    expect(
        tester
            .widget<SportsTeamsScreen>(find.byType(SportsTeamsScreen))
            .initialLeague
            ?.id,
        'eng.1');
    expect(standingsRequests, requestsBefore + 1);
    final scoreRequestsBeforeManagement = scores.calls;
    await tapKey('standings-league');
    await tapKey('__manage_leagues__');
    expect(find.byType(SportsLeagueManagerScreen), findsOneWidget);
    await captureSports(
        tester, const Size(390, 844), 'favorite-league-manager');
    await tapKey('close-leagues');
    expect(find.byType(SportsTeamsScreen), findsOneWidget);
    expect(standingsRequests, requestsBefore + 1);
    expect(scores.calls, scoreRequestsBeforeManagement,
        reason:
            'Opening and cancelling league management does not reload scores or standings.');
    expect(storage.getSportsEventsSelection(), isEmpty,
        reason: 'Events no longer stores a sport, league or favorites scope.');
    final application =
        tester.widget<MultiProvider>(find.byType(MultiProvider).first);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(application);
    await settleSports(tester);
    expect(find.byKey(const ValueKey('league-picker')), findsNothing);
    expect(find.byKey(const ValueKey('events-favorites-only')), findsNothing,
        reason: 'Events reopens unfiltered; leagues come from the gear.');
    expect(playback.played, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
    SportsChannelMatcher.disposeShared();
    playlist.dispose();
    playback.dispose();
    guide.dispose();
    prefs.dispose();
  });

  testWidgets(
      'Schedule watches the Events selection without another match pass',
      (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setLayoutPreferences({'sports_online_extras': false});
    final storage = StorageService();
    await storage.init();
    await storage.setSportsLeagues(['nhl']);
    await storage.setSportsChannelFilter('all');
    final prefs = AppPreferences(storage);
    await prefs.init();
    prefs.isTelevision = true;
    final playlist = LayoutPlaylist(storage, CatalogDatabase());
    final playback = LayoutPlayback(storage, playlist);
    final guide = LayoutScheduleQueryEpg(storage), scores = LayoutInlineScores();
    final game =
        (await scores.gamesForDay([sportsLeagueById('nhl')!], scores.start))
            .first;
    final channel = playlist.fixtureChannels.first;
    await SportsChannelPicks.load(storage).pickForGame(game, channel.id);
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
            builder: (context, child) => RepaintBoundary(child: child),
            home: SportsScreen(scores: scores, clock: () => scores.start))));
    Future<void> flush() async {
      for (var i = 0; i < 25; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    await flush();
    final event = find.byKey(const ValueKey('card-nhl:poll-0'));
    // The hub shows the picked channel on the match line (Watch once the
    // pick confirms, Possible while its evidence is still being checked).
    // A settled frame does not imply the matching isolate has replied.
    // Wait for the full pass, not just the early pick hint, so Schedule
    // reuses completed coverage instead of starting its own search.
    final pickedChannel = find.descendant(
        of: event, matching: find.textContaining(channel.name));
    for (var i = 0;
        i < 40 &&
            (pickedChannel.evaluate().isEmpty ||
                (tester.widget(event) as dynamic).matching as bool);
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(pickedChannel, findsOneWidget);
    final catalogueLoads = playlist.catalogueLoads, queries = guide.queries;
    await tester.tap(find.byKey(const ValueKey('sports-view-schedule')));
    await flush();
    final row = tester
        .widgetList<SportsFixtureRow>(find.byType(SportsFixtureRow))
        .firstWhere((row) => row.game.id == game.id);
    expect(row.channelName, channel.name);
    final panel =
        tester.widget<SportsSchedulePanel>(find.byType(SportsSchedulePanel));
    expect(panel.channelMatchForGame!(row.game)?.channel.id, channel.id);
    expect(playback.played, isEmpty);
    await tester.tap(find.byKey(const ValueKey('nhl:poll-0')));
    await flush();
    expect(playback.played.map((c) => c.id), [channel.id]);
    expect(find.byType(SportsSchedulePanel), findsOneWidget);
    expect(playlist.catalogueLoads, catalogueLoads);
    expect(guide.queries, queries,
        reason: 'Schedule must use the existing match, including for playback');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
    SportsChannelMatcher.disposeShared();
    playlist.dispose();
    playback.dispose();
    guide.dispose();
    prefs.dispose();
  });

  testWidgets(
      'Events shows the chosen leagues and panels never change the saved league list',
      (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'sports_online_extras': false});
    final storage = StorageService();
    await storage.init();
    await storage.setSportsLeagues(['nhl']);
    await storage.setSportsChannelFilter('all');
    await storage.setSportsFollowedTeams(['eng.1|h1']);
    await storage.setSportsTeamNames({'eng.1|h1': 'Saved club'});
    final prefs = AppPreferences(storage);
    await prefs.init();
    prefs.isTelevision = true;
    final playlist = LayoutPlaylist(storage, CatalogDatabase());
    final playback = LayoutPlayback(storage, playlist);
    final guide = LayoutEpg(storage), scores = LayoutFilterScopeScores();
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
            builder: (context, child) => RepaintBoundary(child: child),
            home: SportsScreen(scores: scores, clock: () => scores.start))));
    Future<void> flush() async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    Future<void> tapKey(String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
      await flush();
    }

    await flush();
    final savedLeagues = storage.getSportsLeagues();
    expect(scores.requestedLeagues.single, contains('nhl'));
    expect(scores.requestedLeagues.single, isNot(contains('nba')),
        reason: 'Events shows exactly the leagues chosen in the league list.');
    expect(find.byKey(const ValueKey('card-nhl:scope-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('card-nhl:scope-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('events-favorites-only')), findsNothing,
        reason: 'Events shows every shown league, with no favorites scope.');
    await captureSports(tester, const Size(960, 540), 'events-all-leagues');
    await tapKey('sports-view-schedule');
    expect(
        tester
            .widget<SportsSchedulePanel>(find.byType(SportsSchedulePanel))
            .browseState
            .onlyFavorites,
        false);
    await tapKey('schedule-favorites-only');
    await tapKey('sports-favorites-favorites');
    await tapKey('sports-view-events');
    expect(find.byKey(const ValueKey('events-favorites-only')), findsNothing,
        reason: 'Events has no favorites scope to inherit from a panel.');
    expect(scores.requestedLeagues.last, isNot(contains('nba')),
        reason: 'A panel scope never widens Events beyond the chosen leagues.');
    expect(storage.getSportsLeagues(), savedLeagues);
    await tapKey('sports-view-standings');
    expect(
        tester
            .widget<SportsTeamsScreen>(find.byType(SportsTeamsScreen))
            .favoritesFilter,
        SportsFavoritesFilter.favorites);
    await tapKey('standings-favorites-only');
    await tapKey('sports-favorites-all');
    await tapKey('sports-view-schedule');
    expect(
        tester
            .widget<SportsSchedulePanel>(find.byType(SportsSchedulePanel))
            .browseState
            .onlyFavorites,
        false,
        reason: 'Standings scope changes reach Schedule but never Events.');
    expect(storage.getSportsLeagues(), savedLeagues);
    expect(playback.played, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
    SportsChannelMatcher.disposeShared();
    playlist.dispose();
    playback.dispose();
    guide.dispose();
    prefs.dispose();
  });

  for (final tv in [true, false]) {
    testWidgets(
        'inline standings retain preview, pause hidden work and restore browsing on ${tv ? "TV" : "phone"}',
        (tester) async {
      tester.view.physicalSize =
          tv ? const Size(960, 540) : const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      setLayoutPreferences({'sports_online_extras': false});
      final storage = StorageService();
      await storage.init();
      await storage.setSportsAddedLeagues(['nhl']);
      await storage.setSportsLeagues(['nhl']);
      await storage.setSportsChannelFilter('all');
      await storage.setSportsBrowseSelection('basketball', 'nba');
      final prefs = AppPreferences(storage);
      await prefs.init();
      prefs.isTelevision = tv;
      final playlist = LayoutPlaylist(storage, CatalogDatabase());
      final playback = LayoutPlayback(storage, playlist);
      playback.currentChannel = playlist.fixtureChannels.first;
      final epg = LayoutEpg(storage);
      final scores = LayoutInlineScores();
      var appNow = scores.start;
      var requests = 0;
      final standings = SportsStandingsService(client: MockClient((_) async {
        requests++;
        return http.Response(standings_fixture.table(teams: 500), 200);
      }));
      await tester.pumpWidget(MultiProvider(
          providers: [
            Provider.value(value: storage),
            ChangeNotifierProvider.value(value: prefs),
            ChangeNotifierProvider<PlaylistManager>.value(value: playlist),
            ChangeNotifierProvider<PlaybackService>.value(value: playback),
            ChangeNotifierProvider<EpgService>.value(value: epg),
          ],
          child: MaterialApp(
              theme: buildAppTheme(prefs.palette),
              navigatorObservers: [appRouteObserver],
              home: SportsScreen(
                  scores: scores, standings: standings, clock: () => appNow))));
      Future<void> flush() async {
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 10));
        }
      }

      await flush();
      expect(requests, 0);
      final player = tester.element(find.byType(VideoPlayerPane));
      final current = playback.currentChannel;
      await tester
          .ensureVisible(find.byKey(const ValueKey('sports-view-schedule')));
      await tester.tap(find.byKey(const ValueKey('sports-view-schedule')));
      await flush();
      expect(find.byType(SportsSchedulePanel), findsOneWidget);
      expect(
          tester
              .widget<SportsSchedulePanel>(find.byType(SportsSchedulePanel))
              .initialLeague
              ?.id,
          'nba',
          reason:
              'Schedule retains the explicit browsing selection independently of Events.');
      tester
          .widget<SportsSchedulePanel>(find.byType(SportsSchedulePanel))
          .onLeagueChanged!(sportsLeagueById('eng.1')!);

      expect(tester.element(find.byType(VideoPlayerPane)), same(player));
      if (!tv) {
        await tester.ensureVisible(
            find.byKey(const ValueKey('schedule-search-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('schedule-search-toggle')));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byKey(const ValueKey('schedule-search')), 'Team');
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pump();
        expect(find.byKey(const ValueKey('schedule-search')).hitTestable(),
            findsOneWidget);
        expect(tester.element(find.byType(VideoPlayerPane)), same(player));
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = FakeViewPadding.zero;
        await tester.pump();
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
      }
      final schedulePolls = scores.calls;
      await tester.pump(const Duration(seconds: 31));
      await flush();
      expect(scores.calls, schedulePolls,
          reason: 'Schedule does not poll hidden Events');
      await Navigator.of(tester.element(find.byType(SportsScreen))).maybePop();
      await flush();
      expect(find.byType(SportsSchedulePanel), findsNothing);
      await tester
          .ensureVisible(find.byKey(const ValueKey('sports-view-standings')));
      await tester.tap(find.byKey(const ValueKey('sports-view-standings')));
      await flush();
      expect(find.byKey(const ValueKey('sports-inline-standings')),
          findsOneWidget);
      expect(
          tester
              .widget<SportsTeamsScreen>(find.byType(SportsTeamsScreen))
              .initialLeague
              ?.id,
          'eng.1');
      expect(storage.getSportsBrowseSelection(), ['soccer', 'eng.1']);
      await tester.tap(find.byKey(const ValueKey('standings-favorites-only')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sports-favorites-all')));
      await flush();

      expect(tester.element(find.byType(VideoPlayerPane)), same(player));
      expect(find.byKey(const PageStorageKey('sports-events')), findsNothing);
      expect(find.byType(StandingsTeamTile).evaluate().length, lessThan(25));
      expect(requests, 1);
      if (tv) {
        expect(
            tester
                .getTopLeft(find.byKey(const ValueKey('standings-league')))
                .dy,
            lessThan(tester
                .getTopLeft(find.byKey(const ValueKey('sports-preview-column')))
                .dy),
            reason: 'Standings selectors share the main Sports toolbar');
        final previewBounds =
            tester.getRect(find.byKey(const ValueKey('sports-preview-column')));
        final sportBounds =
            tester.getRect(find.byKey(const ValueKey('standings-sport')));
        expect(sportBounds.left, closeTo(previewBounds.right + 12, .1),
            reason: 'Primary selectors start at the results column');
      }
      final polls = scores.calls;
      await tester.pump(const Duration(seconds: 31));
      await flush();
      expect(scores.calls, polls, reason: 'Hidden events do not poll');
      if (tv) {
        final tab = tester.widget<TextButton>(
            find.byKey(const ValueKey('sports-view-standings')));
        tab.focusNode!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus?.debugLabel,
            'sports-standings-search');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(
            tester
                .widget<SportsFilterButton>(
                    find.byKey(const ValueKey('standings-league')))
                .focusNode!
                .hasFocus,
            isTrue);
      }
      if (tv) {
        tester
            .widget<TextField>(find.byKey(const ValueKey('standings-search')))
            .focusNode!
            .requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
      }
      await tester.enterText(
          find.byKey(const ValueKey('standings-search')), 'Team 1');
      await tester.pump();
      if (!tv) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pump();
        expect(find.byKey(const ValueKey('standings-search')).hitTestable(),
            findsOneWidget);
        expect(tester.element(find.byType(VideoPlayerPane)), same(player));
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = FakeViewPadding.zero;
        await tester.pump();
      }
      final list = tester.widget<ListView>(find.descendant(
          of: find.byType(SportsTeamsScreen), matching: find.byType(ListView)));
      list.controller!.jumpTo(300);
      await tester.pump();
      final beforeReturnPolls = scores.calls;
      // The shared toolbar retains its horizontal offset across tabs.
      await tester
          .ensureVisible(find.byKey(const ValueKey('sports-view-events')));
      await tester.tap(find.byKey(const ValueKey('sports-view-events')));
      await flush();
      expect(find.byType(SportsTeamsScreen), findsNothing);
      expect(scores.calls, beforeReturnPolls,
          reason: 'Other tabs do not invalidate the retained Events scope.');
      expect(tester.element(find.byType(VideoPlayerPane)), same(player));
      await tester.tap(find.byKey(const ValueKey('sports-view-standings')));
      await flush();
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('standings-search')))
              .controller!
              .text,
          'Team 1');
      final restored = tester.widget<ListView>(find.descendant(
          of: find.byType(SportsTeamsScreen), matching: find.byType(ListView)));
      expect(restored.controller!.offset, closeTo(300, .1));
      expect(requests, 1, reason: 'Standings reuse the shared cache');
      final sameScopeCalls = scores.calls;
      await tester
          .ensureVisible(find.byKey(const ValueKey('sports-view-events')));
      await tester.tap(find.byKey(const ValueKey('sports-view-events')));
      await flush();
      expect(scores.calls, sameScopeCalls,
          reason:
              'Quick returns with unchanged scope reuse the score snapshot');
      await tester.tap(find.byKey(const ValueKey('sports-view-standings')));
      await flush();
      await tester.tap(find.byTooltip('Sports options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leagues & teams'));
      await tester.pumpAndSettle();
      expect(find.byType(SportsLeagueManagerScreen), findsOneWidget);
      expect(tester.element(find.byType(VideoPlayerPane)), same(player));
      await Navigator.of(tester.element(find.byType(SportsLeagueManagerScreen)))
          .maybePop();
      await tester.pumpAndSettle();
      expect(find.byType(SportsLeagueManagerScreen), findsNothing);
      await Navigator.of(tester.element(find.byType(SportsScreen))).maybePop();
      await flush();
      expect(find.byType(SportsTeamsScreen), findsNothing,
          reason: 'Back returns to Events');
      await tester.tap(find.byTooltip('Sports options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leagues & teams'));
      await tester.pumpAndSettle();
      final overlayPolls = scores.calls;
      await tester.pump(const Duration(seconds: 31));
      await flush();
      expect(scores.calls, overlayPolls,
          reason: 'Event polling also pauses beneath management overlays');
      expect(tester.element(find.byType(VideoPlayerPane)), same(player));
      await tester.tap(find.byKey(const ValueKey('close-leagues')));
      await flush();
      expect(find.byType(SportsLeagueManagerScreen), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sports-view-standings')));
      await flush();
      appNow = appNow.add(const Duration(seconds: 31));
      final beforeStaleReturn = scores.calls;
      await tester.tap(find.byKey(const ValueKey('sports-view-events')));
      await flush();
      expect(scores.calls, beforeStaleReturn + 1,
          reason: 'Returning after the poll interval refreshes scores');
      expect(playback.currentChannel, same(current));
      expect(playback.played, isEmpty,
          reason: 'View changes never restart playback');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 11));
      standings.close();
      SportsChannelMatcher.disposeShared();
      playback.dispose();
      playlist.dispose();
      epg.dispose();
      prefs.dispose();
    });
  }
}
