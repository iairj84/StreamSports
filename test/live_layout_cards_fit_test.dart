import 'package:nox_iptv/widgets/sports_channel_picker.dart';
import 'dart:async';
import 'dart:convert';
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
import 'package:nox_iptv/screens/tv_home_screen.dart';
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
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1280, 720)
  ]) {
    testWidgets('guide sports survive scores and refresh at ${size.width}',
        (tester) async {
      await http.runWithClient(() async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        setLayoutPreferences({'sports_online_extras': true});
        final storage = StorageService();
        await storage.init();
        await storage.setSportsLeagues(['nhl']);
        const themeId = String.fromEnvironment('LAYOUT_THEME');
        if (themeId.isNotEmpty) await storage.setPaletteId(themeId);
        final prefs = AppPreferences(storage);
        await prefs.init();
        prefs.isTelevision = size.width > 1000;
        final playlist = LayoutPlaylist(storage, CatalogDatabase());
        final playback = LayoutPlayback(storage, playlist);
        final epg = LayoutEpg(storage);
        final now = DateTime.now();
        epg.replays = [
          EpgProgram(
              channelId: 'Fox Sports',
              title: 'World Poker Tour',
              description:
                  'The final table. The world’s finest poker players compete.',
              start: now.subtract(const Duration(minutes: 20)),
              stop: now.add(const Duration(hours: 1)))
        ];
        final pending = Completer<http.Response>();
        var requests = 0;
        var failing = true;
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
                    scores: SportsService.withClient(MockClient((_) {
                      requests++;
                      return failing
                          ? pending.future
                          : Future.value(http.Response('{"events":[]}', 200));
                    }))))));
        for (var i = 0; i < 40; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(find.text('World Poker Tour'), findsWidgets,
            reason: 'Guide coverage appears before scores finish');
        expect(find.text('On air'), findsOneWidget);
        pending.complete(http.Response('Access denied by event source', 403));
        await settleSports(tester);
        expect(find.text('World Poker Tour'), findsWidgets);
        expect(find.text('Pick a channel'), findsNothing);
        final callsBeforeDetails = requests;
        expect(find.byKey(const ValueKey('sports-feed-info')), findsOneWidget);
        if (prefs.isTelevision) {
          tester
              .widget<IconButton>(find.byKey(const ValueKey('sports-refresh')))
              .focusNode!
              .requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pump();
          expect(
              tester
                  .widget<IconButton>(
                      find.byKey(const ValueKey('sports-feed-info')))
                  .focusNode!
                  .hasFocus,
              isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.byKey(const ValueKey('sports-feed-info')));
        }
        await tester.pumpAndSettle();
        expect(find.text('Event feed details'), findsOneWidget);
        await tester.tap(find.byType(ExpansionTile).first);
        await tester.pumpAndSettle();
        expect(find.text('Access denied by event source'), findsOneWidget);
        expect(requests, callsBeforeDetails,
            reason: 'Diagnostics must not fetch again');
        await tester.tap(find.byTooltip('Close feed details'));
        await tester.pumpAndSettle();
        failing = false;
        await tester.tap(find.byKey(const ValueKey('sports-refresh')));
        // Scoreboard JSON parses on background isolates (real async): give
        // the refresh's downloads room to finish instead of asserting while
        // the load is still parked in `compute`.
        for (var i = 0;
            i < 60 &&
                find
                    .byKey(const ValueKey('sports-feed-info'))
                    .evaluate()
                    .isNotEmpty;
            i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await settleSports(tester);
        expect(find.text('World Poker Tour'), findsWidgets);
        expect(find.text('On air'), findsOneWidget);
        expect(requests, greaterThan(callsBeforeDetails));
        expect(find.byKey(const ValueKey('sports-feed-info')), findsNothing);
        await captureSports(tester, size, 'guide-sports');
        epg.replays = [
          for (final entry in [
            (
              'Fox Sports',
              'NBA: Boston Celtics v New York Knicks (Replay)',
              'Full game replay from 21 October 2026.'
            ),
            (
              'Seven',
              'World Poker Tour Highlights',
              'Highlights from the final table.'
            ),
            (
              'Nine',
              'Tennis: Alcaraz v Sinner (Replay)',
              'Full match replay from 20 October 2026.'
            ),
          ])
            EpgProgram(
                channelId: entry.$1,
                title: entry.$2,
                description: entry.$3,
                start: now.subtract(const Duration(minutes: 20)),
                stop: now.add(const Duration(hours: 1)))
        ];
        epg.notifyListeners();
        final videoBefore =
            tester.getRect(find.byKey(const ValueKey('sports-channel-box')));
        for (final tab in ['replays']) {
          await tester.ensureVisible(find.byKey(ValueKey('sports-view-$tab')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('sports-view-$tab')));
          await settleSports(tester);
          final video =
              tester.getRect(find.byKey(const ValueKey('sports-channel-box')));
          final browsing =
              tester.getRect(find.byKey(const ValueKey('replays-scroll')));
          expect(video, videoBefore);
          if (size.width > size.height) {
            expect(browsing.left, greaterThan(video.right));
            expect(browsing.top, closeTo(video.top, .1));
            expect(browsing.height, greaterThan(size.height * .75));
            final footer = tester
                .getRect(find.byKey(const ValueKey('sports-preview-footer')));
            expect(footer.bottom, closeTo(size.height, .1));
            expect(video.width, greaterThan((size.width - 40) * .36));
          } else {
            expect(browsing.top, greaterThan(video.bottom));
          }
          await captureSports(tester, size, 'sports-$tab');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        SportsChannelMatcher.disposeShared();
        await tester.pump(const Duration(seconds: 31));
        playback.dispose();
        playlist.dispose();
        epg.dispose();
        prefs.dispose();
      }, () => MockClient((_) async => http.Response('{"events":[]}', 200)));
    });
  }
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(960, 540),
    const Size(1280, 720)
  ]) {
    testWidgets('tennis tournament cards fit ${size.width}', (tester) async {
      await http.runWithClient(() async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        setLayoutPreferences({'sports_online_extras': false});
        final storage = StorageService();
        await storage.init();
        await storage.setSportsAddedLeagues(['tennis.atp']);
        await storage.setSportsLeagues(['tennis.atp']);
        await storage.setSportsChannelFilter('all');
        const themeId = String.fromEnvironment('LAYOUT_THEME');
        if (themeId.isNotEmpty) await storage.setPaletteId(themeId);
        final prefs = AppPreferences(storage);
        await prefs.init();
        prefs.isTelevision = size.width >= 960;
        final playlist = LayoutPlaylist(storage, CatalogDatabase());
        playlist.fixtureChannels.add(Channel(
            id: 'demo::tennis',
            rawId: 'tennis',
            playlistId: 'demo',
            name: 'Bu vs Ruud - ATP European Open',
            group: 'Tennis',
            url: 'https://example.invalid/never-opened'));
        final otherTennis = Channel(
            id: 'demo::other-tennis',
            rawId: 'other-tennis',
            playlistId: 'demo',
            name: 'ATP Tennis - another match',
            group: 'Tennis',
            url: 'https://example.invalid/never-opened');
        playlist.fixtureChannels.add(otherTennis);
        final playback = LayoutPlayback(storage, playlist);
        final epg = LayoutEpg(storage);
        epg.replays.add(EpgProgram(
            channelId: 'tennis',
            title: 'ATP Tennis: European Open',
            description: 'Live from Brussels, Court 2.',
            start: DateTime.now().subtract(const Duration(minutes: 20)),
            stop: DateTime.now().add(const Duration(hours: 3))));
        await tester.pumpWidget(MultiProvider(
            providers: [
              Provider.value(value: storage),
              ChangeNotifierProvider.value(value: prefs),
              ChangeNotifierProvider<PlaylistManager>.value(value: playlist),
              ChangeNotifierProvider<PlaybackService>.value(value: playback),
              ChangeNotifierProvider<EpgService>.value(value: epg),
            ],
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildAppTheme(prefs.palette),
                navigatorObservers: [appRouteObserver],
                home: const TvHomeScreen())));
        await settleSports(tester);
        await tester.tap(find.byIcon(Icons.sports));
        for (var i = 0;
            i < 30 &&
                find
                    .byKey(const ValueKey('tennis-tournament-tennis-demo'))
                    .evaluate()
                    .isEmpty;
            i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await settleSports(tester);
        expect(find.byKey(const ValueKey('tennis-tournament-tennis-demo')),
            findsOneWidget);
        expect(find.text('BNP Paribas Fortis European Open'), findsWidgets);
        expect(find.text('ATP · ROUND 2'), findsOneWidget);
        final eventCard = find.descendant(
            of: find.byKey(const ValueKey('card-tennis.atp:tennis-demo')),
            matching: find.byType(InkWell));
        tester.widget<InkWell>(eventCard).focusNode!.requestFocus();
        await settleSports(tester);
        final video =
            tester.getRect(find.byKey(const ValueKey('sports-channel-box')));
        final activity =
            tester.getRect(find.byKey(const ValueKey('sports-status-slot')));
        final summary =
            tester.getRect(find.byKey(const ValueKey('sports-preview-title')));
        if (size.width < 600) {
          expect(activity.left, greaterThan(summary.right));
          expect(activity.top, greaterThanOrEqualTo(video.bottom));
          expect(video.height, closeTo((size.width - 24) * 9 / 16, .1));
        } else {
          expect(summary.left, closeTo(video.left, .1));
          expect(summary.top, greaterThan(video.bottom));
          expect(activity.top, greaterThan(summary.bottom));
          expect(activity.right, lessThanOrEqualTo(video.right + .1));
          expect(activity.bottom, closeTo(size.height - 4, .1));
          expect(video.width, greaterThan((size.width - 40) * .36));
          final card = tester.getRect(
              find.byKey(const ValueKey('card-tennis.atp:tennis-demo')));
          expect(card.left, greaterThan(video.right));
          expect(card.top, lessThan(video.bottom));
        }
        expect(tester.takeException(), isNull);
        await captureSports(tester, size, 'tennis');
        if (size.width == 390) {
          // Another tennis stream may appear among broad alternatives, but
          // must not displace this event's recommendation or get its badge.
          await playback.play(otherTennis);
          await settleSports(tester);
          await tester.longPress(
              find.byKey(const ValueKey('card-tennis.atp:tennis-demo')));
          await settleSports(tester);
          final initialPicker =
              tester.widget<SportsChannelList>(find.byType(SportsChannelList));
          final options = initialPicker.rows;
          expect(options.any((row) => row.channel.id == otherTennis.id), true);
          expect(options.first.channel.id, isNot(otherTennis.id));
          expect(initialPicker.playingId, isNull);
          expect(find.textContaining('Playing'), findsNothing);
          final chosenId = options.first.channel.id;
          await tester.tap(find.byKey(ValueKey('game-channel:$chosenId')));
          await settleSports(tester);
          expect(playback.currentChannel?.id, chosenId);
          final saved = jsonDecode(storage.getSportsChannelPicks()!) as Map;
          expect(saved['events']['tennis.atp:tennis-demo']['c'], chosenId,
              reason:
                  'explicitly choosing even the first suggestion is remembered');
          await tester.longPress(
              find.byKey(const ValueKey('card-tennis.atp:tennis-demo')));
          await settleSports(tester);
          final reopened =
              tester.widget<SportsChannelList>(find.byType(SportsChannelList));
          expect(reopened.rows.first.channel.id, chosenId);
          expect(reopened.playingId, chosenId);
          expect(reopened.selectedId, chosenId);
          await captureSports(tester, size, 'sports-playing-channel');
          await tester.binding.handlePopRoute();
          await settleSports(tester);
          expect(tester.takeException(), isNull);
        }

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
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(960, 540)
  ]) {
    testWidgets(
        'sports header keeps its controls readable at ${size.width}',
        (tester) => http.runWithClient(() async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              setLayoutPreferences({'sports_online_extras': false});
              final storage = StorageService();
              await storage.init();
              await storage.setSportsAddedLeagues(['eng.1', 'uefa.champions']);
              await storage.setSportsLeagues(['eng.1', 'uefa.champions']);
              await storage.setSportsChannelFilter('possible');
              final prefs = AppPreferences(storage);
              await prefs.init();
              prefs.isTelevision = size.width >= 960;
              final playlist = LayoutPlaylist(storage, CatalogDatabase());
              final playback = LayoutPlayback(storage, playlist);
              final epg = LayoutEpg(storage);
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
                      home: SportsScreen(
                          scores: LayoutRowScores(
                              counts: {'eng.1': 1, 'uefa.champions': 1})))));
              await settleSports(tester);
              if (size.width < 600) {
                for (final view in [
                  'events',
                  'standings',
                  'schedule',
                  'replays'
                ]) {
                  final tab = find.byKey(ValueKey('sports-view-$view'));
                  expect(tab.hitTestable(), findsOneWidget);
                  final rect = tester.getRect(tab);
                  expect(rect.left, greaterThanOrEqualTo(0));
                  expect(rect.right, lessThanOrEqualTo(size.width));
                }
              }
              final gear = find.byKey(const ValueKey('leagues-gear'));
              expect(gear.hitTestable(), findsOneWidget);
              expect(tester.getSize(gear).width, greaterThanOrEqualTo(28));
              await captureSports(tester, size, 'balanced-events');
              expect(find.byType(Dialog), findsNothing);
              final day = find.byKey(const ValueKey('sports-day'));
              final actions =
                  find.byKey(const ValueKey('sports-toolbar-actions'));
              final overflow = find.byTooltip('Sports options');
              expect(day.hitTestable(), findsOneWidget);
              expect(
                  find.descendant(of: actions, matching: day), findsOneWidget);
              final dayRect = tester.getRect(day);
              final moreRect = tester.getRect(overflow);
              expect(dayRect.right, closeTo(moreRect.left, .1));
              expect(dayRect.center.dy, closeTo(moreRect.center.dy, .1));
              if (!prefs.isTelevision) {
                expect(
                    find.byKey(const ValueKey('event-filters')).hitTestable(),
                    findsOneWidget);
                expect(
                    tester
                        .getSize(find.byKey(const ValueKey('event-filters')))
                        .width,
                    greaterThanOrEqualTo(32));
              }
              await captureSports(tester, size, 'balanced-events');
              expect(tester.takeException(), isNull);
              await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 50)));
              await tester.pump(const Duration(milliseconds: 500));
              await tester.pumpWidget(const SizedBox());
              // Logo-cache SQLite work must finish outside the fake frame clock.
              await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 50)));
              await tester.pump(const Duration(seconds: 11));
              await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 50)));
              await tester.pump();
              SportsChannelMatcher.disposeShared();
              playback.dispose();
              playlist.dispose();
              epg.dispose();
              prefs.dispose();
            },
                () => MockClient(
                    (_) async => http.Response('{"events":[]}', 200))));
  }
}
