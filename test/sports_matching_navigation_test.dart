import 'package:video_player_hdr/video_player_hdr.dart';
import 'player_polish_test.dart' as player_fixture;
import 'package:nox_iptv/widgets/main_navigation_rail.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/models/epg_program.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/screens/tv_home_screen.dart';
import 'package:nox_iptv/screens/sports_screen.dart';
import 'package:nox_iptv/services/app_preferences.dart';
import 'package:nox_iptv/services/catalog_database.dart';
import 'package:nox_iptv/services/epg_service.dart';
import 'package:nox_iptv/services/playback_service.dart';
import 'package:nox_iptv/services/playlist_manager.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/services/sports_supplement_service.dart';
import 'package:nox_iptv/services/sports_service.dart';
import 'package:nox_iptv/services/sports_channel_matcher.dart';
import 'package:nox_iptv/services/sports_browse_cache.dart';
import 'package:nox_iptv/utils/sports_calendar.dart';
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

  for (final overlay in [false, true]) {
    testWidgets('cold Sports results preserve user focus: overlay=$overlay',
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
      final guide = LayoutEpg(storage), scores = LayoutHeldScores();
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
              home: SportsScreen(scores: scores, clock: () => scores.start))));
      await tester.pump();
      final tab = tester
          .widget<TextButton>(find.byKey(const ValueKey('sports-view-events')))
          .focusNode!;
      expect(tab.hasFocus, isTrue,
          reason: 'Events receives entry focus before the first scores arrive');
      if (overlay) {
        await tester.tap(find.byKey(const ValueKey('leagues-gear')));
        await tester.pumpAndSettle();
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      final chosen = FocusManager.instance.primaryFocus;
      expect(chosen, isNotNull);
      await scores.firstBatch();
      scores.done.complete(scores.batch);
      await settleSports(tester);
      expect(FocusManager.instance.primaryFocus, same(chosen),
          reason: 'Late scores must not redirect the next remote activation');
      if (overlay) {
        expect(find.text('Leagues & teams'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('close-leagues')));
        await tester.pumpAndSettle();
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(
            tester
                .widget<TextButton>(
                    find.byKey(const ValueKey('sports-view-schedule')))
                .focusNode!
                .hasFocus,
            isTrue);
      }
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
  }

  for (final playing in [false, true]) {
    testWidgets(
        'Sports handoff preserves Live guide, categories and video: playing=$playing',
        (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      setLayoutPreferences({});
      final storage = StorageService();
      await storage.init();
      await storage.setLiveCategoryFolders(false);
      final prefs = AppPreferences(storage);
      await prefs.init();
      prefs.isTelevision = true;
      final playlist = LayoutRailPlaylist(storage, CatalogDatabase());
      playlist.fixtureChannels
        ..clear()
        ..addAll(List.generate(
            1000,
            (i) => Channel(
                id: 'demo::$i',
                rawId: '$i',
                playlistId: 'demo',
                name: 'Channel $i',
                group: 'Category $i',
                url: 'https://example.test/$i')));
      final playback = LayoutPlayback(storage, playlist);
      if (playing) {
        playback.currentChannel = playlist.fixtureChannels.first;
        playback.controller = player_fixture.Controller();
      }
      final epg = LayoutDrillEpg(storage);
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
              home: const TvHomeScreen())));
      await tester.pumpAndSettle();
      final rail = find.byKey(const ValueKey('live-categories-rail'),
          skipOffstage: false);
      expect(
          find
              .byWidgetPredicate((w) => w.runtimeType.toString() == '_GroupRow')
              .evaluate()
              .length,
          lessThan(40),
          reason: 'Large catalogues only mount nearby categories.');
      final surface =
          playing ? tester.state(find.byType(VideoPlayerHdr)) : null;
      void checkSurface() {
        if (playing) {
          expect(tester.state(find.byType(VideoPlayerHdr)), same(surface),
              reason:
                  'Moving between Live and Sports must retain the native view');
        }
      }

      var original = tester.widget(rail);
      final homeContext = tester.element(find.byType(TvHomeScreen));
      final nav = Navigator.of(homeContext);
      for (var i = 0; i < 3; i++) {
        tester
            .widget<MainNavigationRail>(find.byType(MainNavigationRail))
            .onSelect('sports');
        await tester.pump();
        expect(tester.widget(rail), same(original),
            reason: 'Only the preview needs to change owners.');
        checkSurface();
        nav.pop('live');
        await tester.pumpAndSettle();
        expect(tester.widget(rail), same(original),
            reason: 'Returning must not rebuild unchanged Live columns.');
        checkSurface();
      }
      final all = find.byKey(const ValueKey('all-live-channels'));
      for (final destination in <String?>['live', null]) {
        await tester.tap(all);
        await tester.pumpAndSettle();
        tester
            .widget<MainNavigationRail>(find.byType(MainNavigationRail))
            .focusNodes['live']!
            .requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(
            tester
                .getSize(find.byKey(const ValueKey('live-navigation-rail')))
                .width,
            0);
        expect(tester.getSize(rail).width, 0,
            reason:
                'Start with the menu and categories collapsed into the guide.');
        final categoryList =
            find.descendant(of: rail, matching: find.byType(CustomScrollView));
        final originalCategories = tester.widget(categoryList);
        tester
            .widget<MainNavigationRail>(find.byType(MainNavigationRail))
            .onSelect('sports');
        await tester.pump();
        nav.pop(destination);
        await tester.pumpAndSettle();
        expect(tester.widget(categoryList), same(originalCategories),
            reason:
                'Reopening the columns must preserve the category widgets.');
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-tab-TV');
        expect(
            tester
                .getSize(find.byKey(const ValueKey('live-navigation-rail')))
                .width,
            greaterThan(0));
        expect(tester.getSize(rail).width, greaterThan(0));
        expect(all.hitTestable(), findsOneWidget,
            reason: 'Both Back and Live TV return with categories accessible.');
      }
      await tester.tap(all);
      await tester.pumpAndSettle();
      original = tester.widget(rail);
      for (var i = 0; i < 4; i++) {
        await tester.tap(all);
        await tester.pumpAndSettle();
        expect(tester.widget(rail), same(original),
            reason:
                'Reselecting the same category preserves catalogue widgets.');
      }
      expect(playback.played, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 11));
      SportsChannelMatcher.disposeShared();
      playlist.dispose();
      playback.dispose();
      epg.dispose();
      prefs.dispose();
    });
  }

  testWidgets(
      'guide warms before scores and matches the first batch while other feeds wait',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setLayoutPreferences({'sports_online_extras': false});
    final storage = StorageService();
    await storage.init();
    await storage.setSportsAddedLeagues(['nhl']);
    await storage.setSportsLeagues(['nhl']);
    await storage.setSportsChannelFilter('all');
    final prefs = AppPreferences(storage);
    await prefs.init();
    prefs.isTelevision = false;
    final playlist = LayoutPlaylist(storage, CatalogDatabase());
    final playback = LayoutPlayback(storage, playlist);
    final epg = LayoutWarmGuide(storage);
    final scores = LayoutHeldScores();
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
            home: SportsScreen(scores: scores))));
    Future<void> flush() async {
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    await flush();
    expect(scores.done.isCompleted, false);
    expect(epg.reads, greaterThan(0),
        reason: 'guide cache loads before the first score feed');
    expect(epg.requests, isEmpty, reason: 'no speculative programme queries');
    final reads = epg.reads;
    await scores.firstBatch();
    await flush();
    expect(scores.done.isCompleted, false);
    expect(epg.requests, hasLength(1),
        reason: 'event guide search overlaps remaining score feeds');
    expect(epg.reads, reads,
        reason: 'the event search reuses the prepared guide');
    epg.requests.single.complete([]);
    await flush();
    expect(find.textContaining('Channels: checked'), findsNothing,
        reason: 'the score feed is still visibly loading');
    expect(find.byKey(const ValueKey('card-nhl:poll-0')), findsOneWidget);
    scores.done.complete(scores.batch);
    await flush();
    expect(epg.requests, hasLength(1),
        reason: 'finishing scores does not repeat matching');
    expect(find.textContaining('Channels: checked'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    SportsChannelMatcher.disposeShared();
    playback.dispose();
    playlist.dispose();
    epg.dispose();
    prefs.dispose();
  });

  testWidgets(
      'guide events appear while known live fixture SQL is still pending',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setLayoutPreferences({'sports_online_extras': false});
    final storage = StorageService();
    await storage.init();
    await storage.setSportsAddedLeagues(['nhl']);
    await storage.setSportsLeagues(['nhl', 'guide.badminton']);
    await storage.setSportsChannelFilter('matched');
    final prefs = AppPreferences(storage);
    await prefs.init();
    prefs.isTelevision = false;
    final playlist = LayoutPlaylist(storage, CatalogDatabase());
    final playback = LayoutPlayback(storage, playlist);
    final epg = LayoutSlowGuide(storage);
    final scores = LayoutRowScores(counts: {'nhl': 1});
    epg.replays = [
      EpgProgram(
          channelId: playlist.fixtureChannels.first.epgId,
          title: 'Live Badminton World Tour',
          isLive: true,
          start: DateTime.now().subtract(const Duration(minutes: 10)),
          stop: DateTime.now().add(const Duration(hours: 2)))
    ];
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
            builder: (context, child) => RepaintBoundary(child: child),
            home: SportsScreen(scores: scores, clock: () => scores.start))));
    Future<void> flush() async {
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    for (var i = 0; i < 15 && epg.requests.isEmpty; i++) {
      await flush();
    }
    expect(epg.requests, hasLength(1));
    expect(find.textContaining('Live Badminton World Tour'), findsWidgets,
        reason:
            'Exact guide bindings must pass With channel before fixture SQL finishes');
    epg.requests.single.complete([]);
    await flush();
    expect(find.textContaining('Live Badminton World Tour'), findsWidgets,
        reason: 'Guide events remain present after the fixture query finishes');
    expect(find.textContaining('Channels: checked'), findsOneWidget);
    final scope = '${sportsCalendarDay(scores.start, 0).toIso8601String()}:'
        '${savedSportsLeagues(storage).map((l) => l.id).join(',')}';
    // The browse key carries the preferred playlist and versions guide
    // evidence without lastUpdated: a no-change refresh must not invalidate
    // coverage.
    final snapshot = SportsBrowseCache.shared.read((
      storage,
      storage.getSportsPreferredPlaylistId(),
      playlist,
      epg,
      scores,
      SportsSupplementService.instance,
      SportsChannelMatcher.shared(epg),
      false,
      storage.getActiveViewerId(),
      sportsCalendarDay(scores.start, 0),
      playlist.liveRevision,
      (epg.changeRevision, epg.currentGuideRevision),
    ), scores.start);
    expect(snapshot, isNotNull);
    final identities = snapshot!.restoreSession().identities;
    expect(identities.length, greaterThan(1),
        reason: 'The saved pass includes the newly discovered guide fixture');
    expect(
        snapshot.signature,
        (
          scope,
          playlist.liveRevision,
          epg.changeRevision,
          epg.currentGuideRevision,
          identities,
        ),
        reason:
            'Queued work compares the completed inputs, not the initial ones');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    SportsChannelMatcher.disposeShared();
    playback.dispose();
    playlist.dispose();
    epg.dispose();
    prefs.dispose();
  });

  testWidgets(
      'failed live query exposes guide-only coverage while a queued retry waits',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setLayoutPreferences({'sports_online_extras': false});
    final storage = StorageService();
    await storage.init();
    await storage.setSportsAddedLeagues(['nhl']);
    await storage.setSportsLeagues(['nhl', 'guide.badminton']);
    await storage.setSportsChannelFilter('all');
    final prefs = AppPreferences(storage);
    await prefs.init();
    prefs.isTelevision = false;
    final playlist = LayoutPlaylist(storage, CatalogDatabase());
    final playback = LayoutPlayback(storage, playlist);
    final epg = LayoutSlowGuide(storage);
    final scores = LayoutRowScores(counts: {'nhl': 1});
    epg.replays = [
      EpgProgram(
          channelId: playlist.fixtureChannels.first.epgId,
          title: 'Live Badminton World Tour',
          isLive: true,
          start: DateTime.now().subtract(const Duration(minutes: 10)),
          stop: DateTime.now().add(const Duration(hours: 2)))
    ];
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
            home: SportsScreen(scores: scores))));
    Future<void> flush() async {
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    for (var i = 0; i < 15 && epg.requests.isEmpty; i++) {
      await flush();
    }
    expect(epg.requests, hasLength(1));
    expect(find.textContaining('Live Badminton World Tour'), findsWidgets,
        reason: 'Guide discovery overlaps the pending fixture query');
    epg.requests.single.completeError(StateError('Guide query unavailable'));
    await flush();
    expect(find.textContaining('Live Badminton World Tour'), findsWidgets,
        reason: 'Guide events remain present after the fixture query finishes');
    expect(epg.requests, hasLength(2),
        reason:
            'the queued live retry is still blocked; discovery did not need it');
    expect(epg.requests.last.isCompleted, isFalse);
    epg.requests.last.complete([]);
    await flush();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    SportsChannelMatcher.disposeShared();
    playback.dispose();
    playlist.dispose();
    epg.dispose();
    prefs.dispose();
  });

  for (final leave in [false, true]) {
    testWidgets(
        'new live arrivals precede remaining later batches; leave=$leave',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      setLayoutPreferences({'sports_online_extras': false});
      final storage = StorageService();
      await storage.init();
      await storage.setSportsAddedLeagues(['nhl']);
      await storage.setSportsLeagues(['nhl']);
      await storage.setSportsChannelFilter('all');
      final prefs = AppPreferences(storage);
      await prefs.init();
      prefs.isTelevision = true;
      final playlist = LayoutPlaylist(storage, CatalogDatabase());
      final playback = LayoutPlayback(storage, playlist);
      final epg = LayoutPriorityGuide(storage);
      final scores = LayoutHeldScores();
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
              home: SportsScreen(scores: scores))));
      Future<void> flush() async {
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 10));
        }
      }

      await flush();
      final now = DateTime.now();
      SportsGame fixture(String id, {int hour = 0}) => SportsGame(
          id: id,
          league: sportsLeagueById('nhl')!,
          start: now.add(Duration(hours: hour)),
          state: hour == 0 ? GameState.live : GameState.pre,
          statusText: '',
          home: SportsTeam(
              // Distinct fixtures need distinct team ids: same sport, start
              // and pair now dedupes conference and poll views of one game.
              id: 'home-$id',
              name: id == 'urgent' ? 'Zebrafish United' : 'Boston Bruins',
              shortName: id == 'urgent' ? 'Zebrafish' : 'Bruins',
              abbreviation: ''),
          away: const SportsTeam(
              id: 'away',
              name: 'Toronto Maple Leafs',
              shortName: 'Maple Leafs',
              abbreviation: ''));
      final initial = [
        fixture('first'),
        for (var i = 0; i < 60; i++) fixture('later$i', hour: 4 + (i ~/ 24) * 8)
      ];
      scores.batch = initial;
      scores.publish!(initial);
      await flush();
      expect(epg.held, true);
      final latest = [...initial, fixture('urgent')];
      scores.batch = latest;
      scores.publish!(latest);
      await tester.pump();
      if (leave) await tester.pumpWidget(const SizedBox());
      epg.laterGate.complete();
      scores.done.complete(latest);
      await flush();
      if (leave) {
        expect(epg.order, ['later']);
      } else {
        expect(epg.order, contains('urgent'));
        expect(epg.order.indexOf('urgent'),
            lessThan(epg.order.lastIndexOf('later')));
        expect(find.byKey(const ValueKey('card-nhl:urgent')), findsOneWidget);
        expect(find.textContaining('Channels: checked'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      SportsChannelMatcher.disposeShared();
      playback.dispose();
      playlist.dispose();
      epg.dispose();
      prefs.dispose();
    });
  }

  testWidgets(
      'possible events appear before matching, then unmatched cards leave safely on TV',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setLayoutPreferences({'sports_online_extras': false});
    final storage = StorageService();
    await storage.init();
    await storage.setSportsAddedLeagues(['nhl']);
    await storage.setSportsLeagues(['nhl']);
    await storage.setSportsChannelFilter('possible');
    final prefs = AppPreferences(storage);
    await prefs.init();
    prefs.isTelevision = true;
    final playlist = LayoutPlaylist(storage, CatalogDatabase());
    playlist.fixtureChannels
      ..clear()
      ..add(Channel(
          id: 'weather',
          rawId: 'weather',
          playlistId: 'demo',
          name: 'Weather',
          group: 'News',
          epgIdOverride: 'weather',
          url: 'https://example.invalid/never-play'));
    final playback = LayoutPlayback(storage, playlist);
    final epg = LayoutWarmGuide(storage);
    final scores = LayoutHeldScores();
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
            home: SportsScreen(scores: scores))));
    Future<void> flush() async {
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    await flush();
    expect(scores.done.isCompleted, false);
    expect(epg.reads, greaterThan(0),
        reason: 'guide cache loads before the first score feed');
    expect(epg.requests, isEmpty, reason: 'no speculative programme queries');
    final reads = epg.reads;
    await scores.firstBatch();
    await flush();
    expect(scores.done.isCompleted, false);
    expect(epg.requests, hasLength(1),
        reason: 'event guide search overlaps remaining score feeds');
    expect(epg.reads, reads,
        reason: 'the event search reuses the prepared guide');
    final card = find.byKey(const ValueKey('card-nhl:poll-0'));
    expect(card, findsOneWidget,
        reason: 'Scores are usable before guide search finishes');
    expect(find.text('Waiting for guide'), findsWidgets);
    final dynamic cardWidget = tester.widget(card);
    (cardWidget.focusNode as FocusNode).requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'sports-card-nhl:poll-0');
    epg.requests.single.complete([]);
    await flush();
    expect(find.textContaining('Channels: checked'), findsNothing,
        reason: 'the score feed is still visibly loading');
    expect(card, findsNothing,
        reason: 'A completed empty result removes the pending card');
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        startsWith('sports-chip-'));
    scores.done.complete(scores.batch);
    await flush();
    expect(epg.requests, hasLength(1),
        reason: 'finishing scores does not repeat matching');
    expect(find.textContaining('Channels: checked'), findsOneWidget);
    expect(card, findsNothing,
        reason: 'Finishing scores must not resurrect unmatched cards');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    SportsChannelMatcher.disposeShared();
    playback.dispose();
    playlist.dispose();
    epg.dispose();
    prefs.dispose();
  });

  for (final television in [false, true]) {
    testWidgets(
        'Possible filter renders a current-guide match before SQL finishes; TV=$television',
        (tester) async {
      tester.view.physicalSize =
          television ? const Size(1280, 720) : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      setLayoutPreferences({'sports_online_extras': false});
      final storage = StorageService();
      await storage.init();
      await storage.setSportsAddedLeagues(['nhl']);
      await storage.setSportsLeagues(['nhl']);
      await storage.setSportsChannelFilter('possible');
      final prefs = AppPreferences(storage);
      await prefs.init();
      prefs.isTelevision = television;
      final playlist = LayoutPlaylist(storage, CatalogDatabase());
      final playback = LayoutPlayback(storage, playlist);
      final scores = LayoutRowScores(counts: {'nhl': 1}, namedTeams: true);
      final epg = LayoutSlowGuide(storage);
      final programme = EpgProgram(
          channelId: playlist.fixtureChannels.first.epgId,
          title: 'NHL: Boston Bruins vs Toronto Maple Leafs',
          start: scores.start.subtract(const Duration(minutes: 10)),
          stop: scores.start.add(const Duration(hours: 2)));
      epg.replays = [programme];
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
              home: SportsScreen(scores: scores, clock: () => scores.start))));
      final card = find.byKey(const ValueKey('card-nhl:row-0'));
      ChannelMatch? match() => card.evaluate().isEmpty
          ? null
          : (tester.widget(card) as dynamic).match as ChannelMatch?;
      for (var i = 0; i < 250 && match() == null; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(epg.requests, hasLength(1));
      expect(epg.requests.single.isCompleted, isFalse);
      expect(match()?.channel, same(playlist.fixtureChannels.first));
      expect(match()?.isConfident, isFalse);
      expect(find.textContaining('Possible · ABC HD'), findsOneWidget);
      final focus = (tester.widget(card) as dynamic).focusNode as FocusNode;
      focus.requestFocus();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(focus));
      for (final request in epg.requests) {
        request.complete([programme]);
      }
      for (var i = 0; i < 100 && match()?.isConfident != true; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(match()?.isConfident, isTrue);
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      SportsChannelMatcher.disposeShared();
      playback.dispose();
      playlist.dispose();
      epg.dispose();
      prefs.dispose();
    });
  }

  testWidgets(
      'new live fixtures keep early confidence provisional until rechecked',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setLayoutPreferences({'sports_online_extras': false});
    final storage = StorageService();
    await storage.init();
    await storage.setSportsAddedLeagues(['nhl']);
    await storage.setSportsLeagues(['nhl']);
    await storage.setSportsChannelFilter('possible');
    final prefs = AppPreferences(storage);
    await prefs.init();
    prefs.isTelevision = true;
    final playlist = LayoutPlaylist(storage, CatalogDatabase());
    final playback = LayoutPlayback(storage, playlist);
    final scores = LayoutHeldScores();
    final epg = LayoutSlowGuide(storage);
    final fixtures = LayoutRowScores(counts: {'nhl': 1}, namedTeams: true);
    final first =
        (await fixtures.gamesForDay([sportsLeagueById('nhl')!], fixtures.start))
            .single;
    final late = SportsGame(
        id: 'late',
        league: first.league,
        start: first.start,
        state: GameState.live,
        statusText: 'Live',
        home: const SportsTeam(
            id: 'phl',
            name: 'Philadelphia Flyers',
            shortName: 'Flyers',
            abbreviation: 'PHI'),
        away: const SportsTeam(
            id: 'pit',
            name: 'Pittsburgh Penguins',
            shortName: 'Penguins',
            abbreviation: 'PIT'));
    final programme = EpgProgram(
        channelId: playlist.fixtureChannels.first.epgId,
        title: 'NHL: Boston Bruins vs Toronto Maple Leafs',
        start: first.start.subtract(const Duration(minutes: 10)),
        stop: first.start.add(const Duration(hours: 2)));
    epg.replays = [programme];
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
            home: SportsScreen(scores: scores, clock: () => first.start))));
    Future<void> flushUntil(bool Function() ready) async {
      for (var i = 0; i < 250 && !ready(); i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(ready(), isTrue);
    }

    await flushUntil(() => scores.publish != null);
    scores.batch = [first];
    scores.publish!(scores.batch);
    final card = find.byKey(const ValueKey('card-nhl:row-0'));
    ChannelMatch? match() => card.evaluate().isEmpty
        ? null
        : (tester.widget(card) as dynamic).match as ChannelMatch?;
    await flushUntil(() => epg.requests.isNotEmpty && match() != null);
    scores.batch = [first, late];
    scores.publish!(scores.batch);
    await tester.pump();
    epg.requests.first.complete([programme]);
    await flushUntil(() => epg.requests.length == 2);
    expect(epg.requests.last.isCompleted, isFalse);
    expect(match()?.channel, same(playlist.fixtureChannels.first));
    expect(match()?.isConfident, isFalse,
        reason: 'The previous cohort cannot confirm a newly contested feed');
    epg.requests.last.complete([programme]);
    scores.done.complete(scores.batch);
    await flushUntil(() => match()?.isConfident == true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    SportsChannelMatcher.disposeShared();
    playback.dispose();
    playlist.dispose();
    epg.dispose();
    prefs.dispose();
  });

  testWidgets(
      'slow channel checks survive score polls and publish completed events',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setLayoutPreferences({'sports_online_extras': false});
    final storage = StorageService();
    await storage.init();
    await storage.setSportsAddedLeagues(['nhl']);
    await storage.setSportsLeagues(['nhl']);
    await storage.setSportsChannelFilter('all');
    final prefs = AppPreferences(storage);
    await prefs.init();
    prefs.isTelevision = false;
    final playlist = LayoutPlaylist(storage, CatalogDatabase());
    final playback = LayoutPlayback(storage, playlist);
    final epg = LayoutSlowGuide(storage);
    final scores = LayoutPollingScores();
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
            home: SportsScreen(scores: scores))));
    Future<void> flush() async {
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    // 216 live games keep the matcher in its channel-index stage for a
    // while; the running search appears once the isolate reaches the guide.
    for (var i = 0; i < 15 && epg.requests.isEmpty; i++) {
      await flush();
    }
    expect(epg.requests, hasLength(1));
    await tester.pump(const Duration(seconds: 31));
    await flush();
    expect(scores.calls, 2);
    expect(epg.requests, hasLength(1),
        reason: 'poll must share the running search');
    epg.requests.first.complete([]);
    await flush();
    expect(epg.requests, hasLength(2));
    expect(
        find.byWidgetPredicate((w) =>
            w is Tooltip &&
            (w.message?.contains(
                    '216 of 217 events have completed channel checks') ??
                false)),
        findsOneWidget,
        reason:
            'completed work remains visible while the newly added event is checked');
    epg.requests.last.complete([]);
    await flush();
    expect(find.textContaining('Channels: checked'), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    await flush();
    expect(epg.requests, hasLength(2),
        reason: 'score-only updates reuse channel results');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    SportsChannelMatcher.disposeShared();
    playback.dispose();
    playlist.dispose();
    epg.dispose();
    prefs.dispose();
  });

  testWidgets(
      'nonempty supplemental events settle without an enrichment/rematch loop',
      (tester) async {
    await http.runWithClient(() async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      setLayoutPreferences({'sports_online_extras': true});
      final storage = StorageService();
      await storage.init();
      await storage.setSportsAddedLeagues(['tennis.atp']);
      await storage.setSportsLeagues(['tennis.atp']);
      await storage.setSportsChannelFilter('all');
      final prefs = AppPreferences(storage);
      await prefs.init();
      prefs.isTelevision = false;
      final playlist = LayoutPlaylist(storage, CatalogDatabase());
      final playback = LayoutPlayback(storage, playlist);
      final epg = LayoutEpg(storage);
      final supplement = LayoutSupplement();
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
                  supplement: supplement,
                  scores: SportsService.withClient(
                      MockClient((_) async => layoutTennisFixture()))))));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(supplement.loads, greaterThan(0));
      expect(supplement.warms, lessThanOrEqualTo(2));
      final warmCount = supplement.warms;
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(supplement.warms, warmCount);
      expect(find.byKey(const ValueKey('tennis-tournament-extra-demo')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      SportsChannelMatcher.disposeShared();
      await tester.pump(const Duration(seconds: 31));
      playback.dispose();
      playlist.dispose();
      epg.dispose();
      prefs.dispose();
    }, () => MockClient((_) async => layoutTennisFixture()));
  });
}
