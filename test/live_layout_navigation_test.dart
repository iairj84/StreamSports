import 'package:nox_iptv/utils/constants.dart';
import 'package:nox_iptv/screens/settings/settings_menu_screen.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/screens/tv_home_screen.dart';
import 'package:nox_iptv/screens/library_screen.dart';
import 'package:nox_iptv/utils/top_level_tab_route.dart';
import 'package:nox_iptv/screens/sports_screen.dart';
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
      'top-level library switches preserve menu geometry and return Live TV focus without animation',
      (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setLayoutPreferences({});
    final storage = StorageService();
    await storage.init();
    final prefs = AppPreferences(storage);
    await prefs.init();
    prefs.isTelevision = true;
    final db = CatalogDatabase();
    final playlist = LayoutPlaylist(storage, db);
    final playback = LayoutPlayback(storage, playlist);
    final epg = LayoutEpg(storage);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider.value(value: storage),
          Provider<CatalogDatabase>.value(value: db),
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
    const ids = ['live', 'sports', 'movies', 'series', 'settings'];
    Finder menu(String id) => find.byKey(ValueKey('main-nav-$id'));
    final bounds = {for (final id in ids) id: tester.getRect(menu(id))};
    final icons = {
      for (final id in ids)
        id: tester
            .widget<Icon>(
                find.descendant(of: menu(id), matching: find.byType(Icon)))
            .icon
    };
    final releasing = Completer<void>();
    playback.currentChannel = playlist.fixtureChannels.first;
    playback.stopGate = releasing;
    addTearDown(() {
      if (!releasing.isCompleted) releasing.complete();
    });
    await tester.tap(menu('movies'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget,
        reason: 'Library navigation must not wait for native player release');
    expect(releasing.isCompleted, isFalse);
    releasing.complete();
    await tester.pump();
    expect(playback.pendingResumeChannel, playlist.fixtureChannels.first);
    final route = ModalRoute.of(tester.element(find.byType(LibraryScreen)))!;
    expect(route, isA<TopLevelTabRoute<String>>());
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    for (final id in ids) {
      expect(tester.getRect(menu(id)), bounds[id],
          reason: '$id must stay anchored');
      expect(
          tester
              .widget<Icon>(
                  find.descendant(of: menu(id), matching: find.byType(Icon)))
              .icon,
          icons[id]);
    }
    await tester.tap(menu('series'));
    await tester.pumpAndSettle();
    for (final id in ids) {
      expect(tester.getRect(menu(id)), bounds[id]);
    }
    await tester.tap(menu('settings'));
    await tester.pump();
    expect(find.byType(SettingsMenuScreen), findsOneWidget,
        reason:
            'A library-to-settings switch needs no intermediate Live frame');
    Navigator.of(tester.element(find.byType(SettingsMenuScreen)))
        .pop(SettingsAction.movies);
    await tester.pump();
    expect(find.byType(LibraryScreen), findsOneWidget,
        reason: 'Settings can open library UI in the same next frame');
    await tester.tap(menu('live'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(LibraryScreen), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-tab-TV');
    for (final id in ids) {
      expect(tester.getRect(menu(id)), bounds[id]);
    }
    expect(playback.played, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    playback.dispose();
    playlist.dispose();
    epg.dispose();
    prefs.dispose();
  });

  testWidgets('covering Live preserves its content widgets and data updates',
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
          40,
          (i) => Channel(
              id: 'demo::$i',
              rawId: '$i',
              playlistId: 'demo',
              name: 'Channel $i',
              group: 'Category $i',
              url: 'https://example.test/$i')));
    final playback = LayoutPlayback(storage, playlist);
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
    final rail =
        find.byKey(const ValueKey('live-categories-rail'), skipOffstage: false);
    var original = tester.widget(rail);
    final homeContext = tester.element(find.byType(TvHomeScreen));
    final nav = Navigator.of(homeContext);
    for (var i = 0; i < 3; i++) {
      unawaited(nav.push(TopLevelTabRoute<void>(
          builder: (_) => const Scaffold(body: Text('Overlay')))));
      await tester.pumpAndSettle();
      expect(tester.widget(rail), same(original),
          reason: 'Route visibility alone must not rebuild the Live columns');
      nav.pop();
      await tester.pumpAndSettle();
      expect(tester.widget(rail), same(original));
      expect(
          FocusManager.instance.primaryFocus?.ancestors
              .any((n) => n.debugLabel == 'tv-tabs'),
          isTrue);
    }
    // Dialog visibility still guards background navigation, without rebuilding
    // the catalogue. Real provider changes must continue to reach Live.
    unawaited(showDialog<void>(
        context: homeContext,
        builder: (_) => const AlertDialog(content: Text('Dialog'))));
    await tester.pumpAndSettle();
    expect(tester.widget(rail), same(original));
    playlist.notifyListeners();
    await tester.pumpAndSettle();
    expect(tester.widget(rail), isNot(same(original)),
        reason: 'Live remains visible and updates behind a dialog');
    original = tester.widget(rail);
    nav.pop();
    await tester.pumpAndSettle();
    unawaited(nav.push(TopLevelTabRoute<void>(
        builder: (_) => const Scaffold(body: Text('Another page')))));
    await tester.pumpAndSettle();
    playlist.fixtureChannels.add(Channel(
        id: 'new',
        rawId: 'new',
        playlistId: 'demo',
        name: 'New channel',
        group: 'New category',
        url: 'https://example.test/new'));
    playlist.notifyListeners();
    await tester.pumpAndSettle();
    expect(tester.widget(rail), same(original),
        reason: 'Covered Live must defer catalogue layout until returning');
    playlist.notifyListeners();
    await tester.pumpAndSettle();
    nav.pop();
    await tester.pumpAndSettle();
    expect(tester.widget(rail), isNot(same(original)));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    playback.dispose();
    playlist.dispose();
    epg.dispose();
    prefs.dispose();
  });

  for (final entry in ['Favorites', 'History']) {
    testWidgets('TV category navigation after $entry has no scroll animation',
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
            24,
            (i) => Channel(
                id: 'demo::$i',
                rawId: '$i',
                playlistId: 'demo',
                name: 'Channel $i',
                group: 'Category $i',
                url: 'https://example.test/$i')));
      final playback = LayoutPlayback(storage, playlist);
      playback.history.addAll(playlist.fixtureChannels.take(2));
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
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      if (entry == 'History') {
        // Pinned rows: Favorites, Live Sports, History, All channels.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump();
      final lists = find.descendant(
          of: find.byKey(const ValueKey('live-categories-rail')),
          matching: find.byType(Scrollable));
      final rail = tester.state<ScrollableState>(lists.first).position;
      final loads = playlist.catalogueLoads;
      // Picking a category drills into its content: the cursor starts on the
      // first channel's programme and arrows navigate the timeline. The
      // categories rail stays put (TV hides it once content has focus), so
      // the no-animation assertion covers every scrollable instead of it.
      void expectNoScrollAnimation() {
        final states = <ScrollableState>[];
        void collect(Element e) {
          if (e is StatefulElement && e.state is ScrollableState) {
            states.add(e.state as ScrollableState);
          }
          e.visitChildren(collect);
        }
        collect(tester.element(find.byType(MaterialApp)));
        expect(states, isNotEmpty);
        for (final state in states) {
          expect(state.position.isScrollingNotifier.value, isFalse);
        }
      }
      var previous = FocusManager.instance.primaryFocus;
      for (var i = 0; i < 18; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        final focus = FocusManager.instance.primaryFocus!;
        expect(focus, isNot(same(previous)));
        previous = focus;
        expectNoScrollAnimation();
        // Content navigation keeps the cursor on screen.
        expect(focus.rect.top, greaterThanOrEqualTo(0));
        expect(focus.rect.left, greaterThanOrEqualTo(0));
        expect(focus.rect.bottom, lessThanOrEqualTo(540));
        expect(focus.rect.right, lessThanOrEqualTo(960));
      }
      expect(rail.pixels, 0,
          reason: 'Content navigation leaves the categories rail alone');
      expect(playlist.catalogueLoads, loads);
      expect(playback.played, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      playback.dispose();
      playlist.dispose();
      epg.dispose();
      prefs.dispose();
    });
  }

  for (final fullVideo in [false, true]) {
    testWidgets(
        'Live column drills retain guide, focus and scroll fullVideo=$fullVideo',
        (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      setLayoutPreferences({});
      final storage = StorageService();
      await storage.init();
      final prefs = AppPreferences(storage);
      await prefs.init();
      prefs.isTelevision = true;
      prefs.setGuideFullVideo(fullVideo);
      final playlist = LayoutPlaylist(storage, CatalogDatabase());
      playlist.fixtureChannels.addAll(List.generate(
          60,
          (i) => Channel(
              id: 'demo::extra$i',
              rawId: 'extra$i',
              playlistId: 'demo',
              name: 'Extra $i',
              group: 'Australian TV',
              url: 'https://example.test/$i')));
      final playback = LayoutPlayback(storage, playlist);
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
      final time = find.byKey(const ValueKey('guide-time-scroll'));
      final guideWidget = tester.widget<SingleChildScrollView>(time);
      final horizontal = guideWidget.controller!;
      final vertical = tester
          .widget<ListView>(
              find.byKey(const ValueKey('guide-programme-scroll')))
          .controller!;
      final loads = playlist.catalogueLoads;
      double rail(String key) =>
          tester.getSize(find.byKey(ValueKey(key))).width;
      Future<void> key(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
      }

      Future<void> back() async {
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(rail('live-navigation-rail'), 132);
      expect(rail('live-categories-rail'), 208);
      await key(LogicalKeyboardKey.arrowRight);
      final categoryFocus = FocusManager.instance.primaryFocus;
      expect(rail('live-navigation-rail'), 0);
      expect(rail('live-categories-rail'), 208);
      await key(LogicalKeyboardKey.arrowRight);
      expect(rail('live-categories-rail'), 0);
      expect(horizontal.position.viewportDimension, greaterThan(700));
      // The newly exposed right edge must contain programme cells even though
      // the guide itself has not rebuilt. This catches stale viewport culling.
      final viewport = tester.getRect(time);
      final cells = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_ProgramBlock');
      expect(
          cells.evaluate().any((e) {
            final rect = tester.getRect(find.byWidget(e.widget));
            return rect.left < viewport.right - 4 &&
                rect.right >= viewport.right - 4 &&
                rect.top >= viewport.top &&
                rect.top < viewport.bottom;
          }),
          isTrue);
      for (var i = 0; i < 18; i++) {
        await key(LogicalKeyboardKey.arrowDown);
      }
      await key(LogicalKeyboardKey.arrowRight);
      expect(vertical.offset, greaterThan(0));
      expect(
          FocusManager.instance.primaryFocus?.ancestors
              .any((n) => n.debugLabel == 'timeline-grid'),
          isTrue);
      // A guide scrolled away from the live slot returns to "now" on the first
      // Back, and only the next Back leaves for the category column. Capture
      // the state it settles on: that is what leaving and re-entering the
      // column has to restore.
      await back();
      final guideFocus = FocusManager.instance.primaryFocus;
      final x = horizontal.offset;
      final y = vertical.offset;
      expect(
          guideFocus?.ancestors.any((n) => n.debugLabel == 'timeline-grid'),
          isTrue,
          reason: 'Back from a scrolled guide returns to now first');
      for (var i = 0; i < 4; i++) {
        await back();
        expect(FocusManager.instance.primaryFocus, same(categoryFocus));
        expect(rail('live-categories-rail'), 208);
        await back();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-tab-TV');
        expect(rail('live-navigation-rail'), 132);
        expect(vertical.offset, closeTo(y, .1));
        expect(horizontal.offset, closeTo(x, .1));
        await key(LogicalKeyboardKey.arrowRight);
        await key(LogicalKeyboardKey.arrowRight);
        expect(FocusManager.instance.primaryFocus, same(guideFocus));
        expect(vertical.offset, closeTo(y, .1));
        expect(horizontal.offset, closeTo(x, .1));
      }
      expect(tester.widget<SingleChildScrollView>(time), same(guideWidget),
          reason: 'Column geometry must not recreate the guide subtree');
      expect(playlist.catalogueLoads, loads,
          reason: 'Pure focus changes must not restart catalogue preparation');
      // Restoring a mounted programme just left of the viewport must only
      // reveal it horizontally, without top-aligning the selected channel.
      final rowTop = guideFocus!.rect.top;
      final offscreen = cells.evaluate().firstWhere((e) {
        final rect = tester.getRect(find.byWidget(e.widget));
        return rect.right <= tester.getRect(time).left &&
            (rect.top - rowTop).abs() < 5;
      });
      final focusWidget = tester.widget<Focus>(find
          .descendant(
              of: find.byWidget(offscreen.widget),
              matching: find
                  .byWidgetPredicate((w) => w is Focus && w.focusNode != null))
          .first);
      focusWidget.focusNode!.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(vertical.offset, closeTo(y, .1));
      expect(horizontal.offset, lessThan(x));
      // A real catalogue update still reaches the retained guide.
      playlist.fixtureChannels.insert(
          0,
          Channel(
              id: 'demo::new',
              rawId: 'new',
              playlistId: 'demo',
              name: 'New channel',
              group: 'Australian TV',
              url: 'https://example.test/new'));
      playlist.notifyListeners();
      await tester.pumpAndSettle();
      expect(
          tester.widget<SingleChildScrollView>(time), isNot(same(guideWidget)));
      expect(find.text('New channel'), findsWidgets);
      expect(playlist.catalogueLoads, greaterThan(loads));
      expect(playback.played, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      playback.dispose();
      playlist.dispose();
      epg.dispose();
      prefs.dispose();
    });
  }

  for (final palette in AppConstants.cyberpunkPalettes) {
    for (final size in [const Size(390, 844), const Size(960, 540)]) {
      testWidgets('theme guide smoke ${palette.id} ${size.width}',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        setLayoutPreferences({});
        final storage = StorageService();
        await storage.init();
        await storage.setPaletteId(palette.id);
        final prefs = AppPreferences(storage);
        await prefs.init();
        prefs.isTelevision = size.width > 600;
        final playlist = LayoutPlaylist(storage, CatalogDatabase());
        final playback = LayoutPlayback(storage, playlist);
        final epg = LayoutEpg(storage);
        await tester.pumpWidget(MultiProvider(
            providers: [
              Provider<StorageService>.value(value: storage),
              ChangeNotifierProvider.value(value: prefs),
              ChangeNotifierProvider<PlaylistManager>.value(value: playlist),
              ChangeNotifierProvider<PlaybackService>.value(value: playback),
              ChangeNotifierProvider<EpgService>.value(value: epg),
            ],
            child: MaterialApp(
                theme: buildAppTheme(palette),
                navigatorObservers: [appRouteObserver],
                home: const TvHomeScreen())));
        await tester.pumpAndSettle();
        if (find.byKey(const ValueKey('guide-now')).evaluate().isEmpty) {
          await tester.tap(find.text('Australian TV').first);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const ValueKey('guide-now')));
        await tester.pumpAndSettle();
        expect(find.text('The World Today'), findsWidgets);
        expect(find.text('ABC HD'), findsWidgets);
        expect(playback.played, isEmpty);
        expect(tester.takeException(), isNull);
        await captureSports(tester, size, 'theme-guide-${palette.id}');
        await tester.pumpWidget(const SizedBox());
        playback.dispose();
        playlist.dispose();
        epg.dispose();
        prefs.dispose();
      });
    }
  }

  for (final size in [const Size(390, 844), const Size(1280, 720)]) {
    testWidgets(
        'direct settings navigation preserves playback at ${size.width}',
        (tester) => http.runWithClient(() async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              setLayoutPreferences({'sports_online_extras': false});
              final storage = StorageService();
              await storage.init();
              await storage.setSportsAddedLeagues(['nhl']);
              await storage.setSportsLeagues(['nhl']);
              const themeId = String.fromEnvironment('LAYOUT_THEME');
              if (themeId.isNotEmpty) await storage.setPaletteId(themeId);
              final prefs = AppPreferences(storage);
              await prefs.init();
              prefs.isTelevision = size.width > 600;
              final playlist = LayoutPlaylist(storage, CatalogDatabase());
              final playback = LayoutPlayback(storage, playlist);
              final epg = LayoutEpg(storage);
              await playback.play(playlist.channels.first);
              await tester.pumpWidget(MultiProvider(
                  providers: [
                    Provider.value(value: storage),
                    ChangeNotifierProvider.value(value: prefs),
                    ChangeNotifierProvider<PlaylistManager>.value(
                        value: playlist),
                    ChangeNotifierProvider<PlaybackService>.value(
                        value: playback),
                    ChangeNotifierProvider<EpgService>.value(value: epg),
                  ],
                  child: MaterialApp(
                      theme: buildAppTheme(prefs.palette),
                      navigatorObservers: [appRouteObserver],
                      home: const TvHomeScreen())));
              await tester.pumpAndSettle();
              final channel = playback.currentChannel;
              final count = playback.played.length;
              final settings = size.width < 600
                  ? find.byKey(const ValueKey('bottom-settings'))
                  : find.text('Settings');
              await tester.tap(settings);
              await tester.pumpAndSettle();
              expect(find.byType(SettingsMenuScreen), findsOneWidget);
              expect(find.text('Search'), findsNothing);
              expect(find.text('Refresh playlists'), findsNothing);
              expect(find.text('Playlists & guide'), findsOneWidget);
              expect(playback.currentChannel, channel);
              if (size.width < 600) {
                await tester.tap(find.byKey(const ValueKey('bottom-sports')));
                await settleSports(tester);
                expect(find.byType(SportsScreen), findsOneWidget);
                await tester.tap(find.byKey(const ValueKey('bottom-settings')));
                await settleSports(tester);
                expect(find.byType(SettingsMenuScreen), findsOneWidget);
                await tester.tap(find.byKey(const ValueKey('bottom-live')));
              } else {
                await tester.pageBack();
              }
              await settleSports(tester);
              expect(find.byType(SettingsMenuScreen), findsNothing);
              expect(find.byType(SportsScreen), findsNothing);
              expect(playback.currentChannel, channel);
              expect(playback.played.length, count);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
              SportsChannelMatcher.disposeShared();
              playback.dispose();
              playlist.dispose();
              epg.dispose();
              prefs.dispose();
            },
                () => MockClient(
                    (_) async => http.Response('{"events":[]}', 200))));
  }

  testWidgets(
      'mobile landscape uses compact columns and guide rows without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setLayoutPreferences({'sports_online_extras': false});
    final storage = StorageService();
    await storage.init();
    final prefs = AppPreferences(storage);
    await prefs.init();
    prefs.isTelevision = false;
    final playlist = LayoutPlaylist(storage, CatalogDatabase());
    final playback = LayoutPlayback(storage, playlist);
    final epg = LayoutEpg(storage);
    final capture = GlobalKey();
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
            home: RepaintBoundary(key: capture, child: const TvHomeScreen()))));
    await tester.pump(const Duration(milliseconds: 300));
    final labels = find.byKey(const ValueKey('guide-channel-scroll'));
    expect(tester.widget<ListView>(labels).itemExtent, 36);
    expect(
        tester.getSize(find.byKey(const ValueKey('guide-search'))).height, 24);
    expect(tester.getTopLeft(labels).dx, lessThan(365));
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_LAYOUT')) {
      await tester.runAsync(() async {
        final image = await (capture.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/iptv-guide-landscape.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    playlist.fixtureChannels.add(Channel(
        id: 'demo::other',
        rawId: 'other',
        playlistId: 'demo',
        name: 'Other category channel',
        group: 'Other category',
        url: 'https://example.test/other'));
    playlist.notifyListeners();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('all-live-channels')));
    await settleSports(tester);
    expect(tester.widget<ListView>(labels).childrenDelegate.estimatedChildCount,
        10);
    await tester.tap(find.byKey(const ValueKey('live-categories-rail')));
    await settleSports(tester);
    await tester.tap(find.text('Australian TV'));
    await settleSports(tester);
    expect(tester.widget<ListView>(labels).childrenDelegate.estimatedChildCount,
        9);
    expect(tester.getTopLeft(labels).dx, lessThan(110));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    SportsChannelMatcher.disposeShared();
    await tester.pump(const Duration(seconds: 5));
    playback.dispose();
    playlist.dispose();
    epg.dispose();
    prefs.dispose();
  });

  testWidgets(
      'returning to the categories rail from a sports guide keeps the Sports row focused',
      (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setLayoutPreferences({});
    final storage = StorageService();
    await storage.init();
    final prefs = AppPreferences(storage);
    await prefs.init();
    prefs.isTelevision = true;
    final playlist = LayoutRailPlaylist(storage, CatalogDatabase());
    playlist.fixtureChannels.clear();
    playlist.fixtureChannels.addAll([
      Channel(
          id: 'demo::fox',
          rawId: 'fox',
          playlistId: 'demo',
          name: 'Fox',
          group: 'USA',
          url: 'https://example.test/fox'),
      Channel(
          id: 'demo::espn',
          rawId: 'espn',
          playlistId: 'demo',
          name: 'ESPN',
          group: 'Sports',
          url: 'https://example.test/espn'),
    ]);
    final playback = LayoutPlayback(storage, playlist);
    final epg = LayoutEpg(storage);
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
    // Fox (USA) is playing while the user browses.
    playback.currentChannel = playlist.fixtureChannels.first;
    await tester.pump();

    Future<void> key(LogicalKeyboardKey k) async {
      await tester.sendKeyEvent(k);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
    }

    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
    }

    // The row label lives below the row's focus node, so locate the label
    // in the categories rail and test whether focus overlaps it.
    bool focusWithin(String label) {
      final node = FocusManager.instance.primaryFocus;
      final frame = node?.rect;
      if (node == null || frame == null) return false;
      final hits = find.descendant(
        of: find.byKey(const ValueKey('live-categories-rail')),
        matching: find.text(label, findRichText: true),
      );
      for (final e in hits.evaluate()) {
        if (frame.overlaps(tester.getRect(find.byWidget(e.widget)))) {
          return true;
        }
      }
      return false;
    }

    // Into the categories rail, then down to the Sports row.
    await key(LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 10 && !focusWithin('Sports'); i++) {
      await key(LogicalKeyboardKey.arrowDown);
    }
    expect(focusWithin('Sports'), isTrue,
        reason: 'test setup must reach the Sports category row');
    // Pick Sports: the guide switches to sports channels.
    await key(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    // Walk back out of the guide to the rail (a first Back may only
    // return a scrolled guide to now).
    for (var i = 0; i < 4; i++) {
      await back();
      final n = FocusManager.instance.primaryFocus;
      final inGrid = (n?.ancestors ?? const <FocusNode>[])
          .any((a) => a.debugLabel == 'timeline-grid');
      if (!inGrid) break;
    }
    // The cursor must be back on the browsed Sports row, not reset to the
    // top of the rail (nor the playing channel's USA row).
    expect(focusWithin('Sports'), isTrue);
    expect(focusWithin('USA'), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
    playback.dispose();
    playlist.dispose();
    epg.dispose();
    prefs.dispose();
  });
}
