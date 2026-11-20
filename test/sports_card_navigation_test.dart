import 'package:nox_iptv/widgets/sports_channel_picker.dart';
import 'package:nox_iptv/widgets/sports_activity_status.dart';
import 'package:nox_iptv/widgets/channel_now_label.dart';
import 'dart:async';
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
      'multiview Sports selection returns a channel without preview playback',
      (tester) => http.runWithClient(() async {
            tester.view.physicalSize = const Size(1280, 720);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            setLayoutPreferences({'sports_online_extras': false});
            final storage = StorageService();
            await storage.init();
            await storage.setSportsAddedLeagues(['nhl']);
            await storage.setSportsLeagues(['nhl']);
            await storage.setSportsChannelFilter('all');
            const themeId = String.fromEnvironment('LAYOUT_THEME');
            if (themeId.isNotEmpty) await storage.setPaletteId(themeId);
            final prefs = AppPreferences(storage);
            await prefs.init();
            prefs.isTelevision = true;
            final playlist = LayoutPlaylist(storage, CatalogDatabase());
            final playback = LayoutPlayback(storage, playlist);
            final epg = LayoutEpg(storage);
            final scores = LayoutPollingScores();
            Channel? selected;
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
                        scores: scores,
                        selectionTitle: 'Sports · screen 2',
                        onChooseChannel: (c) async {
                          selected = c;
                        }))));
            await settleSports(tester);
            expect(find.text('Sports · screen 2'), findsOneWidget);
            expect(find.byType(PlayerControls), findsNothing);
            tester
                .widget<IconButton>(
                    find.byKey(const ValueKey('sports-day')))
                .focusNode!
                .requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pump();
            await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
            await tester.pump(const Duration(milliseconds: 700));
            await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
            await settleSports(tester);
            expect(find.byType(SportsChannelPickerDialog), findsOneWidget);
            final dialog = tester.widget<SportsChannelPickerDialog>(
                find.byType(SportsChannelPickerDialog));
            expect(dialog.allowMultiview, false);
            await tester.tap(find.text('Find another channel'));
            await settleSports(tester);
            final search = find.byKey(const ValueKey('sports-channel-search'));
            tester.widget<TextField>(search).focusNode!.requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.select);
            await tester.pump();
            await tester.enterText(search, 'Fox');
            await tester.pump(const Duration(milliseconds: 250));
            await settleSports(tester);
            final chosenRow = tester
                .widget<SportsChannelRow>(find.byType(SportsChannelRow).first);
            await tester.tap(find.byKey(
                ValueKey('game-channel:${chosenRow.result.channel.id}')));
            await settleSports(tester);
            expect(selected, isNotNull);
            expect(playback.played, isEmpty);
            expect(playback.currentChannel, isNull);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await settleSports(tester);
            playback.dispose();
            playlist.dispose();
            epg.dispose();
            prefs.dispose();
            // Past the matcher worker's idle leash (20 minutes) so its release
            // timer cannot outlive the tree.
            await tester.pump(const Duration(minutes: 21));
          }, () => MockClient((_) async => http.Response('{}', 200))));

  testWidgets(
      'pending Sports fullscreen cannot open over a newer route',
      (tester) => http.runWithClient(() async {
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
            playlist.fixtureChannels.add(Channel(
                id: 'demo::fixture',
                rawId: 'fixture',
                playlistId: 'demo',
                name: 'NHL: Boston Bruins vs Toronto Maple Leafs',
                group: 'Sports',
                url: 'https://example.test/live'));
            final playback = LayoutPlayback(storage, playlist)
              ..openGate = Completer<void>();
            final epg = LayoutEpg(storage)..withoutGuide.add('fixture');
            final navigator = GlobalKey<NavigatorState>();
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
                    navigatorKey: navigator,
                    theme: buildAppTheme(prefs.palette),
                    navigatorObservers: [appRouteObserver],
                    home: SportsScreen(
                        scores: LayoutRowScores(
                            counts: {'nhl': 1}, namedTeams: true)))));
            await settleSports(tester);
            final card = find.byKey(const ValueKey('card-nhl:row-0'));
            // A settled frame does not imply the matching isolate has replied.
            // The hub shows a confident match as a Watch line.
            final matchedChannel = find.descendant(
                of: card,
                matching: find.text(
                    'Watch · NHL: Boston Bruins vs Toronto Maple Leafs'));
            for (var i = 0; i < 200 && matchedChannel.evaluate().isEmpty; i++) {
              await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 10)));
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(matchedChannel, findsOneWidget);
            await tester.tap(card);
            await tester.pump();
            expect(playback.played, hasLength(1));
            // Repeated OK while the stream is opening must not stack fullscreen routes.
            await tester.tap(card);
            await tester.pump();
            await tester.tap(card);
            await tester.pump();
            unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Text('New destination')))));
            await tester.pumpAndSettle();
            playback.openGate!.complete();
            await tester.pumpAndSettle();
            expect(find.text('New destination'), findsOneWidget);
            navigator.currentState!.pop();
            await tester.pumpAndSettle();
            expect(find.byType(SportsScreen), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            SportsChannelMatcher.disposeShared();
            playback.dispose();
            playlist.dispose();
            epg.dispose();
            prefs.dispose();
            await tester.pump(const Duration(minutes: 2));
          }, () => MockClient((_) async => http.Response('{}', 200))));

  testWidgets(
      'TV sports remote reaches refresh and isolates card focus rebuilds',
      (tester) => http.runWithClient(() async {
            tester.view.physicalSize = const Size(1280, 720);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            setLayoutPreferences({'sports_online_extras': false});
            final storage = StorageService();
            await storage.init();
            await storage.setSportsAddedLeagues(['nhl']);
            await storage.setSportsLeagues(['nhl']);
            await storage.setSportsChannelFilter('all');
            const themeId = String.fromEnvironment('LAYOUT_THEME');
            if (themeId.isNotEmpty) await storage.setPaletteId(themeId);
            final prefs = AppPreferences(storage);
            await prefs.init();
            prefs.isTelevision = true;
            final playlist = LayoutPlaylist(storage, CatalogDatabase());
            final playback = LayoutPlayback(storage, playlist);
            final epg = LayoutEpg(storage);
            final scores = LayoutPollingScores();
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
                    home: SportsScreen(scores: scores))));
            await settleSports(tester);
            await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
            await tester.pump();
            expect(FocusManager.instance.primaryFocus?.debugLabel,
                'sports-chip-refresh');
            final calls = scores.calls;
            await tester.sendKeyEvent(LogicalKeyboardKey.select);
            await settleSports(tester);
            expect(scores.calls, calls + 1);
            // Returning to the toolbar is explicit, including during refresh.
            tester
                .widget<IconButton>(
                    find.byKey(const ValueKey('sports-day')))
                .focusNode!
                .requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pump();
            expect(FocusManager.instance.primaryFocus?.debugLabel,
                startsWith('sports-card-'));
            var screenBuilds = 0;
            final previous = debugOnRebuildDirtyWidget;
            debugOnRebuildDirtyWidget = (element, builtOnce) {
              if (element.widget is SportsScreen) screenBuilds++;
              previous?.call(element, builtOnce);
            };
            addTearDown(() => debugOnRebuildDirtyWidget = previous);
            for (var i = 0; i < 4; i++) {
              await tester.sendKeyEvent(i.isEven
                  ? LogicalKeyboardKey.arrowRight
                  : LogicalKeyboardKey.arrowLeft);
              await tester.pump();
            }
            expect(screenBuilds, 0,
                reason: 'Remote focus only updates preview and two cards');
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
            await tester.pump();
            expect(FocusManager.instance.primaryFocus?.debugLabel,
                'sports-chip-sport:hockey');
            await tester.sendKeyEvent(LogicalKeyboardKey.select);
            await settleSports(tester);
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pump();
            expect(FocusManager.instance.primaryFocus?.debugLabel,
                startsWith('sports-card-'));
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
            await tester.pump();
            expect(FocusManager.instance.primaryFocus?.debugLabel,
                'sports-chip-liveall');
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pump();
            expect(FocusManager.instance.primaryFocus?.debugLabel,
                startsWith('sports-card-'));
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

  testWidgets(
      'TV keeps the focused card visible through streamed sports and removals',
      (tester) => http.runWithClient(() async {
            tester.view.physicalSize = const Size(960, 540);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            setLayoutPreferences({'sports_online_extras': false});
            final storage = StorageService();
            await storage.init();
            final ids = [
              'nba',
              'eng.1',
              'nhl',
              'mma.ufc',
              'guide.poker',
              'rugby.180659',
              'tennis.atp'
            ];
            await storage.setSportsAddedLeagues(ids);
            await storage.setSportsLeagues(ids);
            await storage.setSportsChannelFilter('all');
            final prefs = AppPreferences(storage);
            await prefs.init();
            prefs.isTelevision = true;
            final playlist = LayoutPlaylist(storage, CatalogDatabase());
            final playback = LayoutPlayback(storage, playlist);
            final epg = LayoutSlowGuide(storage);
            final scores = LayoutHeldScores();
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
                    home: SportsScreen(scores: scores))));
            Future<void> flush() async {
              for (var i = 0; i < 20; i++) {
                await tester.runAsync(() =>
                    Future<void>.delayed(const Duration(milliseconds: 5)));
                await tester.pump(const Duration(milliseconds: 16));
              }
            }

            await flush();
            final fixtures = await LayoutRowScores(
                    counts: {for (final id in ids) id: id == 'nhl' ? 40 : 2})
                .gamesForDay(ids.map((id) => sportsLeagueById(id)!).toList(),
                    DateTime.now());
            final first = fixtures
                .where((g) => g.league.id != 'nba' && g.league.id != 'eng.1')
                .toList();
            scores.publish!(first);
            await flush();
            final dynamic card =
                tester.widget(find.byKey(const ValueKey('card-nhl:row-0')));
            (card.focusNode as FocusNode).requestFocus();
            await tester.pump();
            for (var i = 0; i < 8; i++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            }
            await flush();
            expect(FocusManager.instance.primaryFocus?.debugLabel,
                'sports-card-nhl:row-8');
            final anchor = find.byKey(const ValueKey('card-nhl:row-8'));
            final position = tester.getTopLeft(anchor);
            scores.publish!(fixtures);
            await flush();
            expect(FocusManager.instance.primaryFocus?.debugLabel,
                'sports-card-nhl:row-8');
            expect(tester.getTopLeft(anchor), position,
                reason:
                    'Incoming sports above the browsed row must not move its focused card');
            expect(
                tester
                    .widgetList<ListView>(find.byWidgetPredicate((w) =>
                        w is ListView && w.scrollDirection == Axis.horizontal))
                    .length,
                lessThan(ids.length),
                reason: 'Offscreen rows are not rebuilt as scores arrive');
            scores.publish!(fixtures
                .where((g) =>
                    g.league.id != 'nhl' || int.parse(g.id.substring(4)) >= 9)
                .toList());
            await flush();
            expect(FocusManager.instance.primaryFocus?.debugLabel,
                'sports-card-nhl:row-9');
            final viewport = tester
                .getRect(find.byKey(const PageStorageKey('sports-events')));
            final rect = FocusManager.instance.primaryFocus!.rect;
            expect(rect.top, greaterThanOrEqualTo(viewport.top - 1));
            expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 1));
            expect(rect.left, greaterThanOrEqualTo(viewport.left - 1));
            expect(rect.right, lessThanOrEqualTo(viewport.right + 1));
            // A toolbar action while a lazy target is pending must cancel that target.
            for (var i = 0; i < 10; i++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
            await flush();
            expect(FocusManager.instance.primaryFocus?.debugLabel,
                'sports-chip-refresh');
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            scores.done.complete(fixtures);
            for (final request in epg.requests) {
              if (!request.isCompleted) request.complete([]);
            }
            SportsChannelMatcher.disposeShared();
            playback.dispose();
            playlist.dispose();
            epg.dispose();
            prefs.dispose();
            await tester.pump();
          },
              () => MockClient(
                  (_) async => http.Response('{"events":[]}', 200))));

  testWidgets(
      'TV sports navigates uneven rows, lazy cards and every toolbar control',
      (tester) => http.runWithClient(() async {
            tester.view.physicalSize = const Size(960, 540);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            setLayoutPreferences({'sports_online_extras': false});
            final storage = StorageService();
            await storage.init();
            await storage.setSportsAddedLeagues(
                ['eng.1', 'mma.ufc', 'guide.poker', 'nba', 'nhl']);
            await storage.setSportsLeagues(
                ['eng.1', 'mma.ufc', 'guide.poker', 'nba', 'nhl']);
            await storage.setSportsChannelFilter('all');
            const themeId = String.fromEnvironment('LAYOUT_THEME');
            if (themeId.isNotEmpty) await storage.setPaletteId(themeId);
            final prefs = AppPreferences(storage);
            await prefs.init();
            prefs.isTelevision = true;
            final playlist = LayoutPlaylist(storage, CatalogDatabase());
            final playback = LayoutPlayback(storage, playlist);
            final epg = LayoutEpg(storage);
            final scores = LayoutRowScores(upcoming: {
              'nba',
              'nhl'
            }, counts: {
              'eng.1': 1,
              'mma.ufc': 1,
              'guide.poker': 3,
              'nba': 1,
              'nhl': 20
            });
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
                    home: SportsScreen(scores: scores))));
            await settleSports(tester);
            String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
            Future<void> press(LogicalKeyboardKey key) async {
              await tester.sendKeyEvent(key);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 20));
              final focus = FocusManager.instance.primaryFocus;
              if (focus?.debugLabel?.startsWith('sports-card-') ?? false) {
                final viewport = tester
                    .getRect(find.byKey(const PageStorageKey('sports-events')));
                expect(focus!.rect.top, greaterThanOrEqualTo(viewport.top - 1),
                    reason: 'Focused card is visible above');
                expect(
                    focus.rect.bottom, lessThanOrEqualTo(viewport.bottom + 1),
                    reason: 'Focused card is visible below');
                expect(focus.rect.left, greaterThanOrEqualTo(viewport.left - 1),
                    reason: 'Focused card is visible on left');
                expect(focus.rect.right, lessThanOrEqualTo(viewport.right + 1),
                    reason: 'Focused card is visible on right');
              }
            }

            final toolbar = [
              'view-events',
              'view-standings',
              'view-schedule',
              'view-replays',
              'leagues-gear',
              'event-filters',
              'day',
              'options'
            ];
            for (var i = 0; i < 5; i++) {
              await press(LogicalKeyboardKey.arrowLeft);
            }
            expect(focused(), 'sports-chip-view-events');
            for (final id in toolbar.skip(1)) {
              await press(LogicalKeyboardKey.arrowRight);
              expect(focused(), 'sports-chip-$id');
            }
            await press(LogicalKeyboardKey.arrowRight);
            expect(focused(), 'sports-chip-options',
                reason: 'No wrap into content');
            for (final id in toolbar.reversed.skip(1)) {
              await press(LogicalKeyboardKey.arrowLeft);
              expect(focused(), 'sports-chip-$id');
            }
            final sportBounds =
                tester.getRect(find.byKey(const ValueKey('leagues-gear')));
            expect(
                find.descendant(
                    of: find.byKey(const ValueKey('sports-toolbar-actions')),
                    matching: find.byKey(const ValueKey('leagues-gear'))),
                findsOneWidget,
                reason: 'The league gear rides with the other header icons');

            for (final key in ['sports-day']) {
              final bounds = tester.getRect(find.byKey(ValueKey(key)));
              expect(bounds.center.dy, closeTo(sportBounds.center.dy, 1));
              expect(bounds.right, lessThanOrEqualTo(940));
            }
            expect(find.byKey(const ValueKey('sports-event-filters')),
                findsNothing);
            tester.view.physicalSize = const Size(640, 540);
            await tester.pump();
            for (final id in toolbar.skip(1)) {
              await press(LogicalKeyboardKey.arrowRight);
              expect(focused(), 'sports-chip-$id',
                  reason: 'Clipped toolbar remains traversable');
            }
            for (final id in toolbar.reversed.skip(1)) {
              await press(LogicalKeyboardKey.arrowLeft);
              expect(focused(), 'sports-chip-$id');
            }
            tester.view.physicalSize = const Size(960, 540);
            await tester.pump();

            final rows = tester.widgetList<ListView>(find.byWidgetPredicate(
                (w) => w is ListView && w.scrollDirection == Axis.horizontal));
            expect(rows.length, lessThan(5),
                reason: 'Offscreen sports stay lazy');
            final firstKeys = [
              for (final id in [
                'nba',
                'eng.1',
                'nhl',
                'mma.ufc',
                'guide.poker'
              ])
                '$id:row-0'
            ];
            await press(LogicalKeyboardKey.arrowDown);
            expect(focused(), 'sports-card-${firstKeys.first}');
            for (final key in firstKeys.skip(1)) {
              await press(LogicalKeyboardKey.arrowDown);
              expect(focused(), 'sports-card-$key',
                  reason: 'Exactly one sport per Down');
            }
            await press(LogicalKeyboardKey.arrowDown);
            expect(focused(), 'sports-card-${firstKeys.last}');
            for (final key in firstKeys.reversed.skip(1)) {
              await press(LogicalKeyboardKey.arrowUp);
              expect(focused(), 'sports-card-$key');
            }
            await press(LogicalKeyboardKey.arrowUp);
            expect(focused(), 'sports-chip-view-events');
            // Enter poker's third card, then cross a one-card row in each direction.
            final pokerRow =
                firstKeys.indexWhere((k) => k.startsWith('guide.poker:'));
            for (var i = 0; i <= pokerRow; i++) {
              await press(LogicalKeyboardKey.arrowDown);
            }
            await press(LogicalKeyboardKey.arrowRight);
            await press(LogicalKeyboardKey.arrowRight);
            expect(focused(), 'sports-card-guide.poker:row-2');
            await press(LogicalKeyboardKey.arrowUp);
            expect(focused(), 'sports-card-${firstKeys[pokerRow - 1]}');
            await press(LogicalKeyboardKey.arrowDown);
            expect(focused(), 'sports-card-guide.poker:row-0');
            // Sport headings are reachable without being compulsory stops.
            await press(LogicalKeyboardKey.arrowLeft);
            expect(focused(), 'sports-chip-sport:poker');
            for (final sport in ['mma', 'hockey', 'soccer', 'basketball']) {
              await press(LogicalKeyboardKey.arrowUp);
              expect(focused(), 'sports-chip-sport:$sport');
            }
            // Burst through headings whose outer rows have not been built yet.
            for (var i = 0; i < 4; i++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            }
            for (var i = 0; i < 4; i++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(focused(), 'sports-chip-sport:poker');
            await press(LogicalKeyboardKey.arrowLeft);
            expect(focused(), 'sports-chip-refresh');
            await press(LogicalKeyboardKey.arrowRight);
            expect(focused(), 'sports-card-guide.poker:row-0');
            await press(LogicalKeyboardKey.contextMenu);
            expect(focused(), 'sports-chip-refresh');
            await press(LogicalKeyboardKey.arrowUp);
            expect(focused(), 'sports-chip-view-events');
            await press(LogicalKeyboardKey.arrowDown);
            expect(focused(), 'sports-card-guide.poker:row-0',
                reason: 'Resume browsing');
            // A long horizontal row must build and focus offscreen neighbours.
            final longRow = firstKeys.indexWhere((k) => k.startsWith('nhl:'));
            for (var i = pokerRow; i > longRow; i--) {
              await press(LogicalKeyboardKey.arrowUp);
            }
            // Remote events can accumulate while loading occupies a frame.
            // Preserve all intended steps through currently unbuilt cards.
            for (var i = 0; i < 8; i++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            }
            for (var i = 0; i < 4; i++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(focused(), 'sports-card-nhl:row-8',
                reason:
                    'Buffered arrows must not be swallowed by lazy mounting');
            for (var i = 0; i < 8; i++) {
              await press(LogicalKeyboardKey.arrowLeft);
            }
            for (var i = 1; i < 15; i++) {
              await press(LogicalKeyboardKey.arrowRight);
              expect(focused(),
                  'sports-card-${firstKeys[longRow].replaceFirst('row-0', 'row-$i')}');
            }
            await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
            await tester.pump();
            for (var i = 12; i >= 8; i--) {
              await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 20));
              expect(focused(),
                  'sports-card-${firstKeys[longRow].replaceFirst('row-0', 'row-$i')}');
            }
            await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
            await press(LogicalKeyboardKey.arrowUp);
            expect(focused(), 'sports-card-${firstKeys[longRow - 1]}');
            // Remember an Events-only filter, then replace its widget by
            // switching views. A detached node still has a context in Flutter.
            await press(LogicalKeyboardKey.contextMenu);
            await press(LogicalKeyboardKey.arrowUp);
            // Four view tabs precede the leagues gear on the toolbar.
            for (var i = 0; i < 4; i++) {
              await press(LogicalKeyboardKey.arrowRight);
            }
            expect(focused(), 'sports-chip-leagues-gear');
            await press(LogicalKeyboardKey.arrowDown);
            await press(LogicalKeyboardKey.contextMenu);
            await press(LogicalKeyboardKey.arrowUp);
            await press(LogicalKeyboardKey.arrowLeft);
            expect(focused(), 'sports-chip-view-replays');
            await press(LogicalKeyboardKey.select);
            await settleSports(tester);
            await press(LogicalKeyboardKey.contextMenu);
            expect(focused(), 'replays-refresh');
            await press(LogicalKeyboardKey.arrowUp);
            expect(focused(), 'sports-chip-view-replays',
                reason: 'Do not focus the detached Events filter');
            await press(LogicalKeyboardKey.arrowRight);
            await press(LogicalKeyboardKey.select);
            await settleSports(tester);
            // The control after the view tabs is the replay sport picker.
            // Choosing All sports closes it without changing the view.
            expect(find.text('Replay sport'), findsOneWidget);
            await tester.tap(find.descendant(
                of: find.byType(Dialog), matching: find.text('All sports')));
            await settleSports(tester);
            await press(LogicalKeyboardKey.contextMenu);
            expect(focused(), 'replays-refresh');
            await press(LogicalKeyboardKey.arrowUp);
            expect(focused(), 'sports-chip-view-replays');
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

  for (final initialFailure in [true, false]) {
    testWidgets(
        'unexpected scores failure retains events and permits retry, initial=$initialFailure',
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
      final epg = LayoutEpg(storage);
      final scores = LayoutRecoveringScores();
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
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 10));
        }
      }

      final refresh = find.byKey(const ValueKey('sports-refresh'));
      await scores.firstBatch();
      await flush();
      if (!initialFailure) {
        scores.done.complete(scores.batch);
        await flush();
        await tester.tap(refresh);
        await tester.pump();
      }
      expect(tester.widget<IconButton>(refresh).onPressed, isNotNull,
          reason: 'A busy refresh stays focusable on TV');
      final pendingCalls = scores.retries.length;
      await tester.tap(refresh);
      await tester.pump();
      expect(scores.retries.length, pendingCalls,
          reason: 'Activating a busy refresh does not start another request');
      (initialFailure ? scores.done : scores.retries.last)
          .completeError(StateError('simulated unexpected feed failure'));
      await flush();
      expect(find.byKey(const ValueKey('card-nhl:poll-0')), findsOneWidget);
      expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.tap(refresh);
      await tester.pump();
      scores.retries.last.complete(scores.batch);
      await flush();
      expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
      expect(find.textContaining('Channels: checked'), findsOneWidget);
      expect(find.byKey(const ValueKey('card-nhl:poll-0')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      SportsChannelMatcher.disposeShared();
      playback.dispose();
      playlist.dispose();
      epg.dispose();
      prefs.dispose();
    });
  }

  testWidgets('live hub card shows possession and down and distance',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setLayoutPreferences({'sports_online_extras': false});
    final storage = StorageService();
    await storage.init();
    await storage.setSportsAddedLeagues(['nfl']);
    await storage.setSportsLeagues(['nfl']);
    await storage.setSportsChannelFilter('all');
    final prefs = AppPreferences(storage);
    await prefs.init();
    prefs.isTelevision = true;
    final playlist = LayoutPlaylist(storage, CatalogDatabase());
    final playback = LayoutPlayback(storage, playlist);
    final epg = LayoutEpg(storage);
    final scores = LayoutPossessionScores();
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
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.textContaining('2nd & 7 at NE 32'), findsWidgets);
    expect(find.byIcon(Icons.circle), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    SportsChannelMatcher.disposeShared();
    playback.dispose();
    playlist.dispose();
    epg.dispose();
    prefs.dispose();
  });

  testWidgets(
      'late sport rows slot alphabetically without losing focused event',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setLayoutPreferences({'sports_online_extras': false});
    final storage = StorageService();
    await storage.init();
    await storage.setSportsAddedLeagues(['nhl', 'nba', 'tennis.atp']);
    await storage.setSportsLeagues(['nhl', 'nba', 'tennis.atp']);
    await storage.setSportsChannelFilter('all');
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
    final now = DateTime.now();
    SportsGame event(String league, {bool soon = false}) => SportsGame(
        id: league,
        league: sportsLeagueById(league)!,
        start: now.add(Duration(minutes: soon ? 15 : 0)),
        state: soon ? GameState.pre : GameState.live,
        statusText: soon ? 'Soon' : 'Live',
        home: const SportsTeam(
            id: 'a', name: 'Alpha', shortName: 'Alpha', abbreviation: 'A'),
        away: const SportsTeam(
            id: 'b', name: 'Beta', shortName: 'Beta', abbreviation: 'B'));
    final tennis = event('tennis.atp');
    scores.batch = [tennis];
    scores.publish!(scores.batch);
    await flush();
    final card = find.byKey(const ValueKey('card-tennis.atp:tennis.atp'));
    expect(card, findsOneWidget);
    final dynamic widget = tester.widget(card);
    (widget.focusNode as FocusNode).requestFocus();
    await tester.pump();
    scores.batch = [tennis, event('nhl'), event('nba', soon: true)];
    scores.publish!(scores.batch);
    await flush();
    final basketball = find.byKey(const ValueKey('sport-heading:basketball'));
    final hockey = find.byKey(const ValueKey('sport-heading:hockey'));
    final tennisHeading = find.byKey(const ValueKey('sport-heading:tennis'));
    expect(tester.getTopLeft(basketball).dy,
        lessThan(tester.getTopLeft(hockey).dy));
    expect(tester.getTopLeft(hockey).dy,
        lessThan(tester.getTopLeft(tennisHeading).dy));
    expect((widget.focusNode as FocusNode).hasFocus, true);
    epg.requests.first.complete([]);
    scores.done.complete(scores.batch);
    await flush();
    expect(tester.getTopLeft(basketball).dy,
        lessThan(tester.getTopLeft(tennisHeading).dy));
    expect((widget.focusNode as FocusNode).hasFocus, true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    SportsChannelMatcher.disposeShared();
    playback.dispose();
    playlist.dispose();
    epg.dispose();
    prefs.dispose();
  });

  testWidgets('recycled sport rows restore only their own horizontal offset',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    setLayoutPreferences({'sports_online_extras': false});
    final storage = StorageService();
    await storage.init();
    final leagues = <String, SportsLeague>{};
    for (final league in [...kSportsLeagues, ...kSportsLeagueBank]) {
      leagues.putIfAbsent(league.espnPath.split('/').first, () => league);
    }
    final selected = leagues.values.map((l) => l.id).toList();
    await storage.setSportsAddedLeagues(selected);
    await storage.setSportsLeagues(selected);
    await storage.setSportsChannelFilter('all');
    final prefs = AppPreferences(storage);
    await prefs.init();
    prefs.isTelevision = false;
    final playlist = LayoutPlaylist(storage, CatalogDatabase());
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
            home: SportsScreen(scores: LayoutRowScores()))));
    await settleSports(tester);
    final rows = find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal);
    expect(rows.evaluate().length, greaterThanOrEqualTo(2));
    final first = tester.widget<ListView>(rows.at(0)).controller!;
    final second = tester.widget<ListView>(rows.at(1)).controller!;
    final outer = tester
        .widget<CustomScrollView>(
            find.byKey(const PageStorageKey('sports-events')))
        .controller!;
    expect(first.offset, 0);
    second.jumpTo(400);
    await tester.pump();
    for (var trip = 0; trip < 3; trip++) {
      outer.jumpTo(outer.position.maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(first.hasClients, false,
          reason: 'The actual phone list must recycle its offscreen rows');
      expect(second.hasClients, false);
      // Rebuild the first rows while the page is still partly scrolled.
      outer.jumpTo(200);
      await tester.pump();
      expect(first.offset, 0, reason: 'Untouched row must remain at the start');
      expect(second.offset, 400,
          reason: 'Each row must restore its own position, not another row');
      outer.jumpTo(0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(first.offset, 0, reason: 'No delayed horizontal correction');
      expect(second.offset, 400);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    SportsChannelMatcher.disposeShared();
    playback.dispose();
    playlist.dispose();
    epg.dispose();
    prefs.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final tv in [false, true]) {
    testWidgets(
        'reopening Sports and multiview selection reuses completed matches ${tv ? "TV" : "phone"}',
        (tester) async {
      tester.view.physicalSize =
          tv ? const Size(1280, 720) : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      setLayoutPreferences({'sports_online_extras': false});
      final storage = StorageService();
      await storage.init();
      await storage.setSportsLeagues(['nhl']);
      await storage.setSportsChannelFilter('matched');
      final prefs = AppPreferences(storage);
      await prefs.init();
      prefs.isTelevision = tv;
      final playlist = LayoutPlaylist(storage, CatalogDatabase());
      final playback = LayoutPlayback(storage, playlist);
      // Only the explicitly supplied guide rows are evidence for these feeds.
      final epg = LayoutSlowGuide(storage)
        ..withoutGuide.addAll([for (var i = 0; i < 24; i++) 'feed-$i']);
      final scores = LayoutReopenScores();
      final now = DateTime.now();
      playlist.fixtureChannels
        ..clear()
        ..addAll([
          for (var i = 0; i < 24; i++)
            Channel(
                id: 'feed-$i',
                rawId: 'feed-$i',
                playlistId: 'demo',
                name: 'Event feed $i',
                group: 'Sports',
                url: 'https://example.invalid')
        ]);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MultiProvider(
          providers: [
            Provider.value(value: storage),
            ChangeNotifierProvider.value(value: prefs),
            ChangeNotifierProvider<PlaylistManager>.value(value: playlist),
            ChangeNotifierProvider<PlaybackService>.value(value: playback),
            ChangeNotifierProvider<EpgService>.value(value: epg),
          ],
          child: MaterialApp(
              navigatorKey: nav,
              theme: buildAppTheme(prefs.palette),
              navigatorObservers: [appRouteObserver],
              home: const Scaffold())));
      void open({bool picker = false}) {
        unawaited(nav.currentState!.push(PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, __, ___) => SportsScreen(
                scores: scores,
                clock: () => now,
                onChooseChannel: picker ? (_) async {} : null,
                selectionTitle: picker ? 'Sports · screen 2' : null))));
      }

      Future<void> flush() async {
        for (var i = 0; i < 25; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 10));
        }
      }

      final card = find.byKey(const ValueKey('card-nhl:browse-0'));
      open();
      await flush();
      expect(epg.requests, hasLength(1));
      epg.requests.first.complete(scores.rows());
      await flush();
      expect(card, findsOneWidget);
      final loads = playlist.catalogueLoads;
      // Events has no sport or league scope any more: its cards stay put.
      expect(card, findsOneWidget,
          reason: 'Matched cards stay visible without a filter round trip');
      final dynamic restored = tester.widget(card);
      expect((restored.match as ChannelMatch).isConfident, true);
      await flush();
      expect(epg.requests, hasLength(1),
          reason: 'Browsing never queries the same guide evidence again');
      expect(playlist.catalogueLoads, loads);
      for (final picker in [false, true]) {
        nav.currentState!.pop();
        await tester.pump();
        expect(find.byType(SportsScreen), findsNothing);
        scores.pending = Completer<List<SportsGame>>();
        open(picker: picker);
        await tester.pump();
        expect(card, findsOneWidget,
            reason:
                'Known matches visible on the first frame before scores return');
        final dynamic restored = tester.widget(card);
        expect((restored.match as ChannelMatch).isConfident, true);
        await flush();
        expect(epg.requests, hasLength(1),
            reason: 'No repeated guide query on a warm visit');
        expect(playlist.catalogueLoads, loads,
            reason: 'No repeated catalogue preparation');
        scores.pending!.complete(scores.cached);
        await flush();
        scores.pending = null;
      }
      nav.currentState!.pop();
      await tester.pump();
      epg.notifyListeners(); // Real guide updates invalidate a saved match snapshot.
      open(picker: true);
      await tester.pump();
      expect(card, findsNothing);
      await flush();
      expect(epg.requests, hasLength(2));
      epg.notifyListeners(); // Another guide revision while matching is in flight.
      epg.requests.last.complete(scores.rows());
      await flush();
      expect(card, findsNothing,
          reason: 'An obsolete guide reply cannot become a completed match');
      expect(epg.requests, hasLength(3));
      epg.requests.last.complete(scores.rows());
      await flush();
      expect(card, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 11));
      SportsChannelMatcher.disposeShared();
      playback.dispose();
      playlist.dispose();
      epg.dispose();
      prefs.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  for (final tv in [false, true]) {
    testWidgets(
        'background matching preserves browsing position on ${tv ? "TV" : "phone"}',
        (tester) async {
      tester.view.physicalSize =
          tv ? const Size(1280, 720) : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      setLayoutPreferences({'sports_online_extras': false});
      final storage = StorageService();
      await storage.init();
      await storage.setSportsAddedLeagues(['nhl']);
      await storage.setSportsLeagues(['nhl']);
      await storage.setSportsChannelFilter('matched');
      final prefs = AppPreferences(storage);
      await prefs.init();
      prefs.isTelevision = tv;
      final playlist = LayoutPlaylist(storage, CatalogDatabase());
      final playback = LayoutPlayback(storage, playlist);
      // Only the explicitly supplied guide rows are evidence for these feeds.
      final epg = LayoutSlowGuide(storage)
        ..withoutGuide.addAll([for (var i = 0; i < 24; i++) 'feed-$i']);
      // Keep the simulated refresh within the fixture day, with guide
      // programmes that also cover the matcher's wall clock.
      final fixtureNow = DateTime.now();
      final scores = LayoutBrowseScores(
          start: DateTime(fixtureNow.year, fixtureNow.month, fixtureNow.day,
              fixtureNow.hour));
      var now = scores.start;
      playlist.fixtureChannels
        ..clear()
        ..addAll([
          for (var i = 0; i < 24; i++)
            Channel(
                id: 'feed-$i',
                rawId: 'feed-$i',
                playlistId: 'demo',
                name: 'Event feed $i',
                group: 'Sports',
                url: 'https://example.invalid')
        ]);
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
              home: SportsScreen(scores: scores, clock: () => now))));
      Future<void> flush() async {
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 10));
        }
      }

      await flush();
      expect(epg.requests, hasLength(1));
      expect(find.byKey(const ValueKey('card-nhl:browse-0')), findsNothing,
          reason: 'With channel does not admit unchecked events');
      epg.requests.first.complete(scores.rows());
      await flush();
      if (!tv) {
        await tester.tap(find.byKey(const ValueKey('sport-heading:hockey')));
        await tester.pump();
      }
      final viewport = find.byKey(const PageStorageKey('sports-events'));
      final scrollTop = tester.getTopLeft(viewport).dy;
      final statusSlot = find.byKey(const ValueKey('sports-status-slot'));
      expect(tester.getSize(statusSlot).height, 38);
      final target = tv
          ? find
              .byWidgetPredicate(
                  (w) => w is ListView && w.scrollDirection == Axis.horizontal)
              .last
          : viewport;
      await tester.drag(
          target, tv ? const Offset(-1800, 0) : const Offset(0, -900));
      await tester.pumpAndSettle();
      final controller = tv
          ? tester.widget<ListView>(target).controller!
          : tester.widget<CustomScrollView>(viewport).controller!;
      final offset = controller.offset;
      expect(offset, greaterThan(100));
      final cards = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('card-nhl:'));
      final anchor = cards
          .evaluate()
          .firstWhere((element) {
            final box = element.renderObject as RenderBox;
            final p = box.localToGlobal(Offset.zero);
            return tv
                ? p.dx >= 20 && p.dx < 900
                : p.dy >= scrollTop && p.dy < 700;
          })
          .widget
          .key!;
      final anchorFinder = find.byKey(anchor);
      if (tv) {
        final dynamic card = tester.widget(anchorFinder);
        (card.focusNode as FocusNode).requestFocus();
        await tester.pump(const Duration(milliseconds: 400));
      }
      final anchorPosition = tester.getTopLeft(anchorFinder);
      final settledOffset = controller.offset;
      // Invalidate the guide and refresh. The completed match stays visible
      // while the query is pending, then real removals above us are anchored.
      final sportsState = tester.state(find.byType(SportsScreen));
      final navigator = Navigator.of(tester.element(find.byType(SportsScreen)));
      unawaited(navigator.push(PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) =>
              const Scaffold(body: Text('Floating player')))));
      await tester.pump(const Duration(milliseconds: 400));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 6));
      await tester.pump(const Duration(minutes: 6));
      epg.notifyListeners();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      navigator.pop();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.state(find.byType(SportsScreen)), same(sportsState));
      await flush();
      expect(epg.requests, hasLength(2));
      expect(find.textContaining('Channels: guide scan'), findsOneWidget);
      expect(tester.getSize(statusSlot).height, 38);
      expect(
          find.descendant(
              of: statusSlot, matching: find.byType(LinearProgressIndicator)),
          findsNothing);
      expect(
          find.descendant(
              of: statusSlot, matching: find.byType(CircularProgressIndicator)),
          findsNothing);
      expect(tester.getTopLeft(anchorFinder), anchorPosition);
      final dynamic retainedCard = tester.widget(anchorFinder);
      expect((retainedCard.match as ChannelMatch).isConfident, true);
      expect(
          find.descendant(
              of: anchorFinder, matching: find.byType(SportsEventMatchStatus)),
          findsNothing,
          reason:
              'Usable channels keep their program details during a recheck');
      expect(
          find.descendant(
              of: anchorFinder, matching: find.byType(ChannelNowLabel)),
          findsOneWidget);
      expect((retainedCard.game as SportsGame).home.score, isNotEmpty);
      epg.requests.last.complete(scores.rows(from: 3));
      await flush();
      expect(controller.offset, lessThan(settledOffset));
      expect(tester.getTopLeft(viewport).dy, scrollTop);
      expect(tester.getTopLeft(anchorFinder), anchorPosition);
      expect(find.byKey(const ValueKey('card-nhl:browse-0')), findsNothing);
      expect(find.byKey(const ValueKey('sports-apply-updates')), findsNothing);
      for (final element in cards.evaluate()) {
        final dynamic card = element.widget;
        expect((card.match as ChannelMatch).isConfident, true);
      }
      if (tv) {
        final dynamic card = tester.widget(anchorFinder);
        // Refresh button was tapped, so explicitly restore remote browsing.
        (card.focusNode as FocusNode).requestFocus();
        await tester.pump();
      }
      // A database failure is not a successful empty match result.
      epg.notifyListeners();
      await tester.tap(find.byKey(const ValueKey('sports-refresh')));
      await flush();
      expect(epg.requests, hasLength(3));
      epg.requests.last.completeError(StateError('simulated guide failure'));
      await flush();
      final dynamic keptAfterFailure = tester.widget(anchorFinder);
      expect((keptAfterFailure.match as ChannelMatch).isConfident, true);
      expect(find.textContaining('Channels: check failed'), findsOneWidget,
          reason: tester
              .widget<Text>(find.byKey(const ValueKey('sports-load-status')))
              .data);
      expect(tester.getTopLeft(anchorFinder), anchorPosition);
      // Retry the failed lookup without a guide revision. The failed future
      // must have left the query cache. Remove the focused card this time.
      await tester.tap(find.byKey(const ValueKey('sports-refresh')));
      await flush();
      expect(epg.requests, hasLength(4));
      final anchorId = (anchor as ValueKey<String>).value.split('browse-').last;
      if (tv) {
        final dynamic card = tester.widget(anchorFinder);
        (card.focusNode as FocusNode).requestFocus();
        await tester.pump();
      }
      epg.requests.last.complete(scores
          .rows(from: 3)
          .where((p) => p.channelId != 'feed-$anchorId')
          .toList());
      await flush();
      expect(anchorFinder, findsNothing);
      if (tv) {
        expect(FocusManager.instance.primaryFocus?.debugLabel,
            'sports-card-nhl:browse-${int.parse(anchorId) + 1}');
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
}
