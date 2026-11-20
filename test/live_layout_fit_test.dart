import 'package:nox_iptv/utils/sports_channel_filter.dart';
import 'package:nox_iptv/utils/sports_time_filter.dart';
import 'dart:async';
import 'dart:convert';
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
import 'package:nox_iptv/models/epg_program.dart';
import 'package:nox_iptv/screens/tv_home_screen.dart';
import 'package:nox_iptv/screens/sports_screen.dart';
import 'package:nox_iptv/widgets/player_controls.dart';
import 'package:nox_iptv/screens/sports_live_list_screen.dart';
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
  var scoreRequests = 0;
  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(390, 844)
  ]) {
    testWidgets(
        'guide and navigation fit ${size.width} x ${size.height}',
        (tester) => http.runWithClient(() async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              setLayoutPreferences({'sports_online_extras': false});
              final storage = StorageService();
              await storage.init();
              await storage.setSportsLeagues(['nba', 'nhl', 'nfl']);
              await storage.setSportsChannelFilter('matched');
              // These layout fixtures deliberately reuse one demo channel for
              // several simultaneous games. Explicit picks establish that UI
              // setup; automatic matching must now flag shared feeds uncertain.
              await storage.setSportsChannelPicks(jsonEncode({
                'events': {
                  for (final league in ['nba', 'nhl', 'nfl'])
                    for (var i = 1; i < 5; i++)
                      '$league:$i': {
                        'c': 'demo::Fox Sports',
                        't': DateTime.now().millisecondsSinceEpoch
                      }
                },
                'teams': <String, String>{}
              }));
              const themeId = String.fromEnvironment('LAYOUT_THEME');
              if (themeId.isNotEmpty) await storage.setPaletteId(themeId);
              final prefs = AppPreferences(storage);
              await prefs.init();
              prefs.isTelevision = size.width > 600;
              final playlist = LayoutPlaylist(storage, CatalogDatabase());
              final playback = LayoutPlayback(storage, playlist);
              final epg = LayoutEpg(storage);
              final capture = GlobalKey();
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
                child: RepaintBoundary(
                    child: MaterialApp(
                        debugShowCheckedModeBanner: false,
                        theme: buildAppTheme(prefs.palette),
                        navigatorObservers: [appRouteObserver],
                        home: RepaintBoundary(
                            key: capture, child: const TvHomeScreen()))),
              ));
              await tester.pump(const Duration(milliseconds: 300));
              expect(find.text('Movies'), findsOneWidget);
              expect(find.text('Series'), findsOneWidget);
              expect(find.text('Media Hub'), findsNothing);
              expect(find.text('Sports'), findsOneWidget);
              expect(find.text('ABC HD'), findsWidgets);
              expect(tester.takeException(), isNull);
              if (size.width > 600) {
                // Live TV -> groups -> programmes; programme navigation stays in grid.
                await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
                await tester.pump(const Duration(milliseconds: 300));
                await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
                await tester.pump(const Duration(milliseconds: 300));
                final first = FocusManager.instance.primaryFocus;
                expect(
                    first?.ancestors
                        .any((node) => node.debugLabel == 'timeline-grid'),
                    isTrue);
                await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
                await tester.pump(const Duration(milliseconds: 300));
                expect(FocusManager.instance.primaryFocus, isNot(first));
                await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
                await tester.pump(const Duration(milliseconds: 300));
                expect(
                    FocusManager.instance.primaryFocus?.ancestors
                        .any((node) => node.debugLabel == 'timeline-grid'),
                    isTrue);
              }
              if (size.width > 600) {
                // Tap the Now shortcut, then use the remote to move across
                // the toolbar and down into the guide again.
                await tester.tap(find.byKey(const ValueKey('guide-now')));
                await tester.pump();
                await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
                await tester.pump();
                await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
                await tester.pump();
                expect(FocusManager.instance.primaryFocus?.debugLabel,
                    'guide-now');
                await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
                await tester.pump();
                expect(
                    FocusManager.instance.primaryFocus?.ancestors
                        .any((n) => n.debugLabel == 'timeline-grid'),
                    isTrue);
              }
              expect(tester.takeException(), isNull);
              await tester.pump(const Duration(milliseconds: 200));
              if (const bool.fromEnvironment('CAPTURE_LAYOUT')) {
                await tester.runAsync(() async {
                  final boundary = capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
                  final image = await boundary.toImage();
                  final bytes =
                      await image.toByteData(format: ui.ImageByteFormat.png);
                  await File('/tmp/iptv-guide-${size.width.toInt()}.png')
                      .writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
              if (size.width < 600) {
                // Touch scrolling must work on either column, including flings.
                final originalCount = playlist.fixtureChannels.length;
                playlist.fixtureChannels.addAll(List.generate(
                    100,
                    (i) => Channel(
                        id: 'demo::extra$i',
                        rawId: 'extra$i',
                        playlistId: 'demo',
                        name: [0, 30, 70, 98].contains(i)
                            ? '### Section $i ###'
                            : 'Extra $i',
                        group: 'Australian TV',
                        url: 'https://example.test/$i')));
                playlist.notifyListeners();
                await tester.pump(const Duration(milliseconds: 100));
                final labels =
                    find.byKey(const ValueKey('guide-channel-scroll'));
                final programmes =
                    find.byKey(const ValueKey('guide-programme-scroll'));
                ScrollController scroll(Finder finder) =>
                    tester.widget<ListView>(finder).controller!;
                await tester.fling(labels, const Offset(0, -220), 1200);
                await tester.pump(const Duration(milliseconds: 250));
                expect(scroll(labels).offset, greaterThan(150));
                expect(scroll(programmes).offset,
                    closeTo(scroll(labels).offset, .1));
                await tester.pump(const Duration(seconds: 2));
                final beforeGridDrag = scroll(programmes).offset;
                await tester.dragFrom(Offset(300, tester.getCenter(labels).dy),
                    const Offset(0, -150));
                await tester.pump(const Duration(milliseconds: 100));
                expect(scroll(programmes).offset,
                    closeTo(scroll(labels).offset, .1));
                expect(scroll(programmes).offset, greaterThan(beforeGridDrag));
                await playback.play(playlist.fixtureChannels[50]);
                await tester.pump();
                await tester
                    .tap(find.byKey(const ValueKey('guide-playing-channel')));
                await tester.pump();
                await tester.pump();
                expect(scroll(labels).offset, greaterThan(1500));
                expect(
                    find.text(playlist.fixtureChannels[50].name).hitTestable(),
                    findsWidgets);
                final time = find.byKey(const ValueKey('guide-time-scroll'));
                final horizontal =
                    tester.widget<SingleChildScrollView>(time).controller!;
                final now = horizontal.offset;
                horizontal.jumpTo(now + 300);
                await tester.pump();
                await tester.tap(find.byKey(const ValueKey('guide-now')));
                await tester.pump();
                expect(horizontal.offset, closeTo(now, .1));
                // Reopening search must focus the field, not retain focus on its button.
                for (var i = 0; i < 2; i++) {
                  await tester.tap(find.byKey(const ValueKey('guide-search')));
                  await tester.pump();
                  await tester.pump();
                  final field =
                      tester.widget<TextField>(find.byType(TextField));
                  expect(field.focusNode!.hasFocus, true);
                  expect(tester.testTextInput.isVisible, true);
                  await tester.enterText(find.byType(TextField), 'Extra 4');
                  await tester.pump();
                  expect(field.focusNode!.hasFocus, true);
                  await tester.tap(find.byTooltip('Close filter'));
                  await tester.pump();
                }
                // Search current EPG titles/descriptions as well as channel names.
                await tester.tap(find.byKey(const ValueKey('guide-search')));
                await tester.pump();
                await tester.pump();
                await tester.enterText(find.byType(TextField), 'World Today');
                await tester.pump();
                await tester.pump(const Duration(milliseconds: 200));
                await tester.pump();
                expect(
                    tester
                        .widget<ListView>(labels)
                        .childrenDelegate
                        .estimatedChildCount,
                    playlist.fixtureChannels.length - 4);
                await tester.enterText(find.byType(TextField), 'not-a-show');
                await tester.pump();
                await tester.pump(const Duration(milliseconds: 200));
                await tester.pump();
                expect(find.text('No channels found.'), findsOneWidget);
                expect(
                    find.byKey(const ValueKey('guide-search')), findsOneWidget);
                await tester.tap(find.byTooltip('Close filter'));
                await tester.pump();
                // Tap cycles headers; holding offers direct selection. No stream is opened.
                scroll(labels).jumpTo(0);
                await tester.pump();
                final playsBefore = playback.played.length;
                final sectionButton =
                    find.byKey(const ValueKey('guide-next-section'));
                for (final index in [
                  originalCount,
                  originalCount + 30,
                  originalCount + 70,
                  originalCount + 98,
                  originalCount
                ]) {
                  await tester.tap(sectionButton);
                  await tester.pump();
                  await tester.pump();
                  expect(
                      scroll(labels).offset,
                      closeTo(
                          (index * tester.widget<ListView>(labels).itemExtent!)
                              .clamp(
                                  0.0, scroll(labels).position.maxScrollExtent),
                          .1));
                }
                await tester.longPress(sectionButton);
                await tester.pump(const Duration(milliseconds: 300));
                expect(find.byKey(const ValueKey('guide-section-picker')),
                    findsOneWidget);
                expect(
                    tester
                        .widget<ListView>(find.descendant(
                            of: find
                                .byKey(const ValueKey('guide-section-picker')),
                            matching: find.byType(ListView)))
                        .itemExtent,
                    40);
                await captureSports(tester, size, 'guide-sections');
                await tester.tap(find
                    .byKey(ValueKey('guide-section-${originalCount + 70}')));
                await settleSports(tester);
                expect(
                    scroll(labels).offset,
                    closeTo(
                        (originalCount + 70) *
                            tester.widget<ListView>(labels).itemExtent!,
                        .1));
                expect(playback.played.length, playsBefore);
                // The same button supports a real remote hold (repeat + release),
                // without the held key selecting a popup item accidentally.
                await tester.tap(find.byKey(const ValueKey('guide-now')));
                await tester.pump();
                await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
                await tester.pump();
                await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
                await tester.pump(const Duration(milliseconds: 600));
                await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
                await settleSports(tester);
                await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
                await tester.pump();
                expect(find.byKey(const ValueKey('guide-section-picker')),
                    findsOneWidget);
                await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
                await tester.pump();
                await tester.sendKeyEvent(LogicalKeyboardKey.select);
                await settleSports(tester);
                expect(find.byKey(const ValueKey('guide-section-picker')),
                    findsNothing);
                expect(
                    scroll(labels).offset,
                    closeTo(
                        (originalCount + 30) *
                            tester.widget<ListView>(labels).itemExtent!,
                        .1));
                // History is a normal guide category, newest first, with EPG rows.
                playback.history.addAll(
                    [playlist.fixtureChannels[4], playlist.fixtureChannels[2]]);
                playback.notifyListeners();
                await tester.tap(find.byKey(const ValueKey('bottom-live')));
                await tester.pump();
                await tester.tap(find.text('History'));
                await tester.pump();
                expect(find.byType(SimpleDialog), findsNothing);
                expect(find.text('History'), findsOneWidget);
                expect(
                    tester
                        .widget<ListView>(labels)
                        .childrenDelegate
                        .estimatedChildCount,
                    2);
                await tester.pump();
                expect(
                    find.text('The World Today').hitTestable(), findsWidgets);
                final rulerScroll = tester
                    .widget<SingleChildScrollView>(
                        find.byKey(const ValueKey('guide-ruler-scroll')))
                    .controller!;
                expect(horizontal.offset, closeTo(rulerScroll.offset, .1));
                if (const bool.fromEnvironment('CAPTURE_LAYOUT')) {
                  await tester.runAsync(() async {
                    final image = await (capture.currentContext!
                            .findRenderObject() as RenderRepaintBoundary)
                        .toImage();
                    final bytes =
                        await image.toByteData(format: ui.ImageByteFormat.png);
                    await File('/tmp/iptv-history-390.png')
                        .writeAsBytes(bytes!.buffer.asUint8List());
                    image.dispose();
                  });
                }
                await tester.tap(find.byKey(const ValueKey('bottom-live')));
                await tester.pump();
                await tester.tap(find.text('Australian TV'));
                await tester.pump();
                playlist.fixtureChannels.removeRange(
                    originalCount, playlist.fixtureChannels.length);
                playlist.notifyListeners();
                await playback.stop();
                await tester.pump();
              }
              // The same active channel survives switching into Sports without a play/stop.
              final originalChannel = playlist.fixtureChannels.first;
              await playback.play(originalChannel);
              final playCount = playback.played.length;
              await tester.pump();
              epg.pending = Completer<List<EpgProgram>>();
              // TV hides passed columns; return through them before using tabs.
              for (var i = 0;
                  i < 2 &&
                      find
                          .byIcon(Icons.sports)
                          .hitTestable()
                          .evaluate()
                          .isEmpty;
                  i++) {
                await tester.binding.handlePopRoute();
                await tester.pumpAndSettle();
              }
              await tester.tap(find.byIcon(Icons.sports));
              await tester.pump(const Duration(milliseconds: 300));
              // Scoreboard parsing runs in an isolate, outside the fake test clock.
              await tester.runAsync(() async {
                await Future<void>.delayed(const Duration(milliseconds: 400));
              });
              await tester.pump(const Duration(milliseconds: 400));
              await tester.pump(const Duration(milliseconds: 200));
              for (var attempt = 0;
                  attempt < 20 && find.text('Celtics').evaluate().isEmpty;
                  attempt++) {
                await tester.runAsync(() =>
                    Future<void>.delayed(const Duration(milliseconds: 50)));
                await tester.pump(const Duration(milliseconds: 100));
              }
              // Loading state never bypasses the confidence filter.
              expect(find.byKey(const ValueKey('sports-load-status')),
                  findsOneWidget);
              expect(find.byKey(const ValueKey('card-nba:0')), findsNothing);
              await captureSports(tester, size, 'sports-loading');
              epg.pending!.complete([]);
              epg.pending = null;
              // A quiet frame does not mean the matching isolate has replied.
              for (var attempt = 0;
                  attempt < 100 &&
                      find
                          .byKey(const ValueKey('card-nba:1'))
                          .evaluate()
                          .isEmpty;
                  attempt++) {
                await tester.runAsync(() =>
                    Future<void>.delayed(const Duration(milliseconds: 10)));
                await tester.pump(const Duration(milliseconds: 16));
              }
              await settleSports(tester);
              await tester.pump(const Duration(milliseconds: 100));
              await tester.pump(const Duration(milliseconds: 100));
              if (find
                  .byKey(const ValueKey('event-filters'))
                  .evaluate()
                  .isEmpty) {
                expect(find.text('Matched'), findsOneWidget);
              } else {
                expect(
                    tester
                        .widget<IconButton>(
                            find.byKey(const ValueKey('event-filters')))
                        .tooltip,
                    contains(SportsChannelFilter.matched.label));
              }
              expect(find.text('NFL RedZone'), findsNothing);
              expect(playback.currentChannel, same(originalChannel));
              expect(playback.played.length, playCount);
              Future<void> finishRefresh(int expectedRequests) async {
                for (var attempt = 0; attempt < 30; attempt++) {
                  await tester.runAsync(() =>
                      Future<void>.delayed(const Duration(milliseconds: 50)));
                  await tester.pump(const Duration(milliseconds: 100));
                  if (scoreRequests >= expectedRequests &&
                      tester
                              .widget<IconButton>(
                                  find.byKey(const ValueKey('sports-refresh')))
                              .onPressed !=
                          null) {
                    break;
                  }
                }
                expect(
                    tester
                        .widget<IconButton>(
                            find.byKey(const ValueKey('sports-refresh')))
                        .onPressed,
                    isNotNull);
              }

              // A tap or pull while a poll is in flight is a silent no-op:
              // wait for the request count to settle first.
              Future<void> waitScoresIdle() async {
                for (var i = 0; i < 30; i++) {
                  final seen = scoreRequests;
                  await tester.runAsync(() =>
                      Future<void>.delayed(const Duration(milliseconds: 50)));
                  await tester.pump(const Duration(milliseconds: 100));
                  if (scoreRequests == seen) return;
                }
              }
              final beforeRefresh = scoreRequests;
              await waitScoresIdle();
              await tester.tap(find.byKey(const ValueKey('sports-refresh')));
              await tester.pump();
              expect(find.byKey(const ValueKey('card-nba:1')), findsOneWidget);
              await finishRefresh(beforeRefresh + 9);
              expect(scoreRequests, beforeRefresh + 9);
              if (size.width < 600) {
                await settleSports(tester);
                final beforePull = scoreRequests;
                final groups =
                    find.byKey(const PageStorageKey('sports-events'));
                Future<void> pullOnce() async {
                  tester.widget<ScrollView>(groups).controller!.jumpTo(0);
                  await tester.pumpAndSettle();
                  final pull = await tester.startGesture(
                      tester.getTopLeft(groups) + const Offset(100, 24));
                  for (var step = 0; step < 6; step++) {
                    await pull.moveBy(const Offset(0, 50));
                    await tester.pump(const Duration(milliseconds: 50));
                  }
                  await captureSports(tester, size, 'sports-refresh');
                  await pull.up();
                  // Start the snap animation before advancing its fake clock.
                  await tester.pump();
                  await tester.pump(const Duration(milliseconds: 300));
                }
                // A poll can start mid-gesture and swallow the pull; retry on
                // an idle screen until the pull's own fetch lands.
                for (var attempt = 0;
                    attempt < 3 && scoreRequests < beforePull + 9;
                    attempt++) {
                  await waitScoresIdle();
                  await pullOnce();
                  await finishRefresh(beforePull + 9);
                }
                expect(scoreRequests, beforePull + 9);
              }
              expect(playback.currentChannel, same(originalChannel));
              expect(playback.played.length, playCount);
              expect(find.byType(VideoPlayerPane), findsOneWidget);
              final compactFilters =
                  find.byKey(const ValueKey('event-filters'));
              SportsTimeFilter currentTime() {
                final tip = tester.widget<IconButton>(compactFilters).tooltip!;
                return SportsTimeFilter.values.singleWhere(
                    (mode) => tip.startsWith('Filters: ${mode.label} ·'));
              }

              SportsChannelFilter currentChannels() {
                final tip = tester.widget<IconButton>(compactFilters).tooltip!;
                return SportsChannelFilter.values
                    .singleWhere((mode) => tip.endsWith('· ${mode.label}'));
              }

              Future<void> openFilter(String key) async {
                await tester.tap(compactFilters);
                await tester.pumpAndSettle();
              }

              Future<void> finishFilter() async {
                if (find.text('Done').evaluate().isNotEmpty) {
                  await tester.tap(find.text('Done'));
                }
                await tester.pumpAndSettle();
              }

              expect(currentTime(), isNot(SportsTimeFilter.all));
              expect(currentChannels(), SportsChannelFilter.matched);
              expect(find.byKey(const ValueKey('card-nba:0')), findsNothing);
              // The wider lazy row mounts the upcoming card; on phones it is
              // beyond the viewport/cache extent until scrolled into view.
              if (size.width >= 600) {
                expect(
                    find.byKey(const ValueKey('card-nba:3')), findsOneWidget);
              }
              Future<void> chooseTime(String mode) async {
                await openFilter('live-only');
                await tester.tap(find.byKey(ValueKey('time-filter-$mode')));
                await finishFilter();
              }

              Future<void> toggleLive() => chooseTime(
                  currentTime() == SportsTimeFilter.live ? 'all' : 'live');
              final requestsBeforeTime = scoreRequests;
              await chooseTime('liveAndSoon');
              expect(currentTime(), SportsTimeFilter.liveAndSoon);
              expect(currentChannels(), SportsChannelFilter.matched);
              await captureSports(tester, size, 'sports-showing');
              await chooseTime('live');
              await settleSports(tester);
              expect(scoreRequests, requestsBeforeTime,
                  reason: 'Time filters must not fetch data');
              Future<void> chooseChannelFilter(String mode) async {
                await openFilter('with-channel');
                await tester.tap(find.byKey(ValueKey('channel-filter-$mode')));
                await finishFilter();
              }

              await chooseChannelFilter('possible');
              expect(storage.getSportsChannelFilter(), 'possible');
              expect(currentChannels(), SportsChannelFilter.possible);
              await openFilter('with-channel');
              await captureSports(tester, size, 'channel-filter');
              await tester
                  .tap(find.byKey(const ValueKey('channel-filter-matched')));
              await tester.pump(const Duration(milliseconds: 200));
              await finishFilter();
              // Capture lets the opening animation finish, so closing can
              // take longer than the partial animation in non-capture runs.
              await settleSports(tester);
              // Exercise the remaining filters starting from the unfiltered view.
              await playback.stop();
              await toggleLive();
              await chooseChannelFilter('all');
              await settleSports(tester);
              expect(find.byKey(const ValueKey('sports-channel-box')),
                  findsOneWidget);
              expect(playback.currentChannel, isNull);
              // An unmatched live fixture is visible until explicitly filtered.
              expect(find.byKey(const ValueKey('card-nba:0')), findsOneWidget);
              await chooseChannelFilter('matched');
              await tester.pump(const Duration(milliseconds: 200));
              expect(storage.getSportsWithChannel(), isTrue);
              expect(find.byKey(const ValueKey('card-nba:0')), findsNothing);
              expect(find.byKey(const ValueKey('card-nba:1')), findsOneWidget);
              await chooseChannelFilter('all');
              await tester.pump(const Duration(milliseconds: 200));
              expect(storage.getSportsWithChannel(), isFalse);
              expect(find.byKey(const ValueKey('card-nba:0')), findsOneWidget);
              expect(find.byKey(const ValueKey('sport-heading:basketball')),
                  findsOneWidget);
              expect(find.byKey(const ValueKey('sport-heading:hockey')),
                  findsOneWidget);
              if (size.width < 600) {
                expect(
                    tester
                        .getSize(
                            find.byKey(const ValueKey('sports-channel-box')))
                        .width,
                    greaterThan(340));
              }
              final overviewCard = find.descendant(
                  of: find.byKey(const ValueKey('card-nba:1')),
                  matching: find.byType(InkWell));
              tester.widget<InkWell>(overviewCard).focusNode!.requestFocus();
              await settleSports(tester);
              if (size.width > 600) {
                await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
                await settleSports(tester);
                expect(FocusManager.instance.primaryFocus?.debugLabel,
                    'sports-card-nfl:1');
                await tester.ensureVisible(
                    find.byKey(const ValueKey('sport-heading:basketball')));
                await tester.tap(
                    find.byKey(const ValueKey('sport-heading:basketball')));
                await settleSports(tester);
                expect(find.byKey(const ValueKey('sport-heading:hockey')),
                    findsNothing);
                await tester.binding.handlePopRoute();
                await settleSports(tester);
                expect(find.byKey(const ValueKey('sport-heading:hockey')),
                    findsOneWidget);
                tester.widget<InkWell>(overviewCard).focusNode!.requestFocus();
                await settleSports(tester);
              }
              // Capture the default live/matched overview, then continue filter checks.
              await toggleLive();
              await chooseChannelFilter('matched');
              await settleSports(tester);
              final scrollable = find
                  .descendant(
                      of: find.byKey(const PageStorageKey('sports-events')),
                      matching: find.byType(Scrollable))
                  .first;
              tester.state<ScrollableState>(scrollable).position.jumpTo(0);
              await settleSports(tester);
              await captureSports(tester, size, 'sports');
              await tester
                  .ensureVisible(find.byKey(const ValueKey('leagues-gear')));
              await tester.tap(find.byKey(const ValueKey('leagues-gear')));
              await settleSports(tester);
              expect(
                  find.descendant(
                      of: find.byKey(const ValueKey('sports-panel-surface')),
                      matching: find.text('American football')),
                  findsWidgets);
              await tester.tap(find.byType(TextField));
              await tester.sendKeyEvent(LogicalKeyboardKey.select);
              await tester.pump();
              await tester.enterText(find.byType(TextField), 'NBA');
              await tester.pump();
              expect(find.text('Basketball'), findsWidgets);
              await tester.enterText(find.byType(TextField), '');
              await tester.pump();
              // The league manager no longer sorts; close it with its
              // close action (escape does not pop its guarding PopScope).
              // Sort now lives in the event filter picker, covered by its
              // own tests.
              await tester.tap(find.byKey(const ValueKey('close-leagues')));
              await settleSports(tester);
              await captureSports(tester, size, 'sports-leagues');
              await toggleLive();
              await chooseChannelFilter('all');
              await settleSports(tester);
              await toggleLive();
              await settleSports(tester);
              expect(find.byKey(const ValueKey('card-nba:3')), findsNothing);
              await toggleLive();
              await settleSports(tester);
              await tester.ensureVisible(
                  find.byKey(const ValueKey('sport-heading:basketball')));
              await settleSports(tester);
              await tester
                  .tap(find.byKey(const ValueKey('sport-heading:basketball')));
              await settleSports(tester);
              expect(find.byKey(const ValueKey('sport-heading:hockey')),
                  findsNothing);
              // The basketball heading already selects the sport; the
              // standalone sport picker dialog is gone (sport is chosen via
              // headings and managed in the league manager, covered above).
              await tester
                  .ensureVisible(find.byKey(const ValueKey('leagues-gear')));
              await tester.tap(find.byKey(const ValueKey('leagues-gear')));
              await settleSports(tester);
              expect(find.text('Leagues & teams'), findsOneWidget);
              await tester.tap(find.byKey(const ValueKey('close-leagues')));
              await settleSports(tester);
              // Secondary controls remain available in the options menu.
              await tester.tap(find.byIcon(Icons.more_horiz));
              await tester.pump(const Duration(milliseconds: 200));
              expect(find.text('Leagues & teams'), findsOneWidget);
              expect(find.text('My Teams'), findsNothing);
              expect(find.text('Standings').hitTestable(), findsOneWidget);
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pump(const Duration(milliseconds: 200));
              // Focusing a matched game fills the idle preview without playing.
              await chooseChannelFilter('matched');
              await tester.pump(const Duration(milliseconds: 200));
              expect(find.text('Later today'), findsOneWidget);
              await toggleLive();
              await settleSports(tester);
              expect(find.text('Later today'), findsNothing);
              // Counts retain upcoming games even when Live-only is on;
              // verified through the visible section headings below.
              await settleSports(tester);
              await toggleLive();
              await settleSports(tester);
              final gameInk = find.descendant(
                  of: find.byKey(const ValueKey('card-nba:1')),
                  matching: find.byType(InkWell));
              tester.widget<InkWell>(gameInk).focusNode!.requestFocus();
              await tester.pump(const Duration(milliseconds: 200));
              expect(find.text('Choose a game'), findsNothing);
              expect(playback.currentChannel, isNull);
              expect(
                  find.descendant(
                      of: find.byKey(const ValueKey('sports-channel-box')),
                      matching: find.text('Fox Sports')),
                  findsOneWidget);
              expect(find.text('Celtics'), findsWidgets);
              expect(tester.takeException(), isNull);
              if (size.width > 600) {
                expect(FocusManager.instance.primaryFocus?.debugLabel,
                    'sports-card-nba:1');
                await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
                await tester.pump(const Duration(milliseconds: 200));
                expect(FocusManager.instance.primaryFocus?.debugLabel,
                    'sports-card-nba:2');
                await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
                await tester.pump(const Duration(milliseconds: 200));
              }
              await tester.pump(const Duration(milliseconds: 200));
              if (const bool.fromEnvironment('CAPTURE_LAYOUT')) {
                await tester.runAsync(() async {
                  final boundary =
                      tester.firstRenderObject<RenderRepaintBoundary>(
                          find.byType(RepaintBoundary));
                  final image = await boundary.toImage();
                  final bytes =
                      await image.toByteData(format: ui.ImageByteFormat.png);
                  await File(
                          '/tmp/iptv-sports-detail-${size.width.toInt()}.png')
                      .writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
              // Long-press presents channels once, with a clear preview action.
              await tester
                  .ensureVisible(find.byKey(const ValueKey('card-nba:1')));
              await settleSports(tester);
              await tester.longPress(find.byKey(const ValueKey('card-nba:1')));
              await settleSports(tester);
              expect(find.text('Watch on…'), findsOneWidget);
              expect(find.text('Find another channel'), findsOneWidget);
              expect(find.text('Play here'), findsNothing);
              expect(find.byKey(const ValueKey('sports-channel-dialog')),
                  findsOneWidget);
              expect(find.byType(BottomSheet), findsNothing);
              expect(find.textContaining('The World Today'), findsWidgets);
              await captureSports(tester, size, 'sports-channels');
              await tester.binding.handlePopRoute();
              await settleSports(tester);
              if (prefs.isTelevision) {
                expect(FocusManager.instance.primaryFocus?.debugLabel,
                    'sports-card-nba:1');
              }
              await tester.longPress(find.byKey(const ValueKey('card-nba:1')));
              await settleSports(tester);

              await tester.tap(
                  find.byKey(const ValueKey('game-channel:demo::Fox Sports')));
              await settleSports(tester);
              expect(find.text('Watch on…'), findsNothing);
              expect(playback.currentChannel?.name, 'Fox Sports');
              await playback.stop();
              await settleSports(tester);
              playback.played.clear();
              // A single tap on an unfocused card starts its matched channel.
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pump();
              await tester
                  .ensureVisible(find.byKey(const ValueKey('card-nba:1')));
              await settleSports(tester);
              await tester.tap(find.byKey(const ValueKey('card-nba:1')));
              await tester.pump(const Duration(milliseconds: 200));
              expect(playback.played, hasLength(1));
              expect(playback.currentChannel?.name, 'Fox Sports');
              await tester
                  .ensureVisible(find.byKey(const ValueKey('card-nba:2')));
              await settleSports(tester);
              if (size.width > 600) {
                final second = find.descendant(
                    of: find.byKey(const ValueKey('card-nba:2')),
                    matching: find.byType(InkWell));
                tester.widget<InkWell>(second).focusNode!.requestFocus();
                await settleSports(tester);
                expect(playback.played, hasLength(1));
                await tester.sendKeyEvent(LogicalKeyboardKey.select);
              } else {
                await tester.tap(find.byKey(const ValueKey('card-nba:2')));
              }
              await tester.pump(const Duration(milliseconds: 200));
              expect(playback.played, hasLength(2));
              expect(find.byType(SportsScreen), findsOneWidget);
              // Back returns to the overview while the channel keeps playing.
              await tester.binding.handlePopRoute();
              await settleSports(tester);
              expect(playback.currentChannel?.name, 'Fox Sports');
              await tester
                  .tap(find.byKey(const ValueKey('sport-heading:basketball')));
              await settleSports(tester);
              // Lazy phone rows release offscreen headers: scroll back before
              // opening the stats action, as a viewer would.
              if (size.width < 600) {
                tester
                    .widget<CustomScrollView>(find
                        .descendant(
                            of: find.byType(SportsScreen),
                            matching: find.byType(CustomScrollView))
                        .first)
                    .controller!
                    .jumpTo(0);
                await tester.pump();
              }
              // See all keeps the same filter after its own data refresh.
              await tester.ensureVisible(find.text('See all · stats'));
              await settleSports(tester);
              await tester.tap(find.text('See all · stats'));
              await tester.pump(const Duration(milliseconds: 300));
              await tester.runAsync(() =>
                  Future<void>.delayed(const Duration(milliseconds: 200)));
              await tester.pump(const Duration(milliseconds: 200));
              final liveRows = tester
                  .widgetList<InkWell>(find.byType(InkWell))
                  .where((w) =>
                      w.focusNode?.debugLabel?.startsWith('sports-live-') ??
                      false)
                  .map((w) => w.focusNode!.debugLabel)
                  .toList();
              expect(liveRows,
                  unorderedEquals(['sports-live-nba:1', 'sports-live-nba:2']));
              Navigator.of(tester.element(find.byType(SportsLiveListScreen)))
                  .pop();
              await tester.pump(const Duration(milliseconds: 300));
              await settleSports(tester);
              expect(storage.getSportsWithChannel(), isTrue);
              // Replays use direct guide mappings, keep the current preview,
              // and preserve the Events filters when switching back.
              final replayNow = DateTime.now();
              for (final entry in [
                ('Replay 1', 'NBA League Pass'),
                ('NFL Replay 1', 'NFL Sunday Ticket'),
                ('NFL Replay 2', 'NFL Sunday Ticket'),
                ('NFL Replay 3', 'NFL Sunday Ticket'),
                ('NHL Replay 1', 'NHL Center Ice'),
                ('NHL Replay 2', 'NHL Center Ice'),
                ('PL REPLAY 1 HD', 'Soccer Replay'),
                ('PL REPLAY 2 HD', 'Soccer Replay'),
              ]) {
                playlist.fixtureChannels.add(Channel(
                    id: 'demo::${entry.$1}',
                    rawId: entry.$1,
                    playlistId: 'demo',
                    name: entry.$1,
                    group: entry.$2,
                    url: 'https://example.test/no-stream'));
                epg.withoutGuide.add(entry.$1);
              }
              playlist.notifyListeners();
              epg.replays = [
                for (final entry in [
                  (
                    'Fox Sports',
                    'NBA: Boston Celtics v New York Knicks (Replay)',
                    'Full game replay from 21 October 2026. Madison Square Garden, New York.'
                  ),
                  (
                    'Fox Sports HD',
                    'NBA: Boston Celtics v New York Knicks (Replay)',
                    'Full game replay from 21 October 2026. Madison Square Garden, New York.'
                  ),
                  (
                    'ABC HD',
                    'NCAA Women’s Volleyball: Texas v Stanford (Replay)',
                    'Replay of the women’s college volleyball match.'
                  ),
                  (
                    'SBS HD',
                    'NCAA Women’s Soccer: Florida Atlantic v South Florida (Replay)',
                    'Full match replay from 21 October.'
                  ),
                  (
                    'Seven',
                    'Cricket: Australia v India — 2nd ODI',
                    'Coverage of the second one-day international.'
                  ),
                  (
                    'Nine',
                    'Formula 1: Australian Grand Prix (Replay)',
                    'Full race replay from 24 March 2024. Albert Park, Melbourne.'
                  ),
                ])
                  EpgProgram(
                      channelId: entry.$1,
                      title: entry.$2,
                      description: entry.$3,
                      start: replayNow.subtract(const Duration(minutes: 25)),
                      stop: replayNow.add(const Duration(minutes: 95))),
              ];
              epg.notifyListeners();
              final beforeReplays = playback.played.length;
              final livePreviewRect =
                  tester.getRect(find.byKey(const ValueKey('sports-preview')));
              final liveRefreshRect =
                  tester.getRect(find.byKey(const ValueKey('sports-refresh')));
              final livePlayerElement =
                  tester.element(find.byType(VideoPlayerPane));
              tester
                  .widget<TextButton>(
                      find.byKey(const ValueKey('sports-view-replays')))
                  .focusNode!
                  .requestFocus();
              await tester.pumpAndSettle();
              await tester.sendKeyEvent(LogicalKeyboardKey.select);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 300));
              expect(find.textContaining('4 shown'), findsOneWidget);
              expect(
                  tester.getRect(find.byKey(const ValueKey('sports-preview'))),
                  livePreviewRect);
              expect(
                  tester.getRect(find.byKey(const ValueKey('replays-refresh'))),
                  liveRefreshRect);
              expect(tester.element(find.byType(VideoPlayerPane)),
                  same(livePlayerElement));
              expect(
                  tester
                      .getBottomRight(
                          find.byKey(const ValueKey('replay-sport-picker')))
                      .dy,
                  lessThan(livePreviewRect.top));
              await tester.tap(find.byKey(const ValueKey('replay-options')));
              await settleSports(tester);
              await captureSports(tester, size, 'replay-options');
              await tester.tap(find.text('Include possible replays'));
              await settleSports(tester);
              expect(find.textContaining('5 shown'), findsOneWidget);
              expect(find.text('21 Oct 2026'), findsWidgets);
              expect(find.byKey(const ValueKey('replay-view-toggle')),
                  findsNothing);
              await tester.tap(find.byKey(const ValueKey('replay-options')));
              await settleSports(tester);
              await tester.tap(find.text('Search replays'));
              await settleSports(tester);
              final searchField =
                  find.byKey(const ValueKey('replay-search-field'));
              expect(tester.widget<TextField>(searchField).focusNode!.hasFocus,
                  true);
              if (tester.widget<TextField>(searchField).readOnly) {
                await tester.sendKeyEvent(LogicalKeyboardKey.select);
                await tester.pump();
              }
              await tester.enterText(searchField, 'new york');
              await settleSports(tester);
              expect(find.textContaining('1 shown'), findsOneWidget);
              await captureSports(tester, size, 'replay-search');
              await tester.enterText(searchField, 'fox sports hd');
              await settleSports(tester);
              expect(find.textContaining('1 shown'), findsOneWidget);
              await tester.enterText(searchField, 'Austrália India');
              await settleSports(tester);
              expect(find.textContaining('1 shown'), findsOneWidget);
              await tester.enterText(searchField, 'no such event');
              await settleSports(tester);
              expect(find.textContaining('0 shown'), findsOneWidget);
              expect(find.text('Clear filters'), findsOneWidget);
              await tester.tap(find.text('Clear filters'));
              await settleSports(tester);
              expect(find.textContaining('5 shown'), findsOneWidget);
              await tester.tap(find.byTooltip('Close search'));
              await settleSports(tester);
              expect(searchField, findsNothing);
              expect(playback.played.length, beforeReplays);

              await tester
                  .tap(find.byKey(const ValueKey('replay-sort-picker')));
              await settleSports(tester);
              expect(find.text('Order within each sport'), findsOneWidget);
              await tester.tap(find.text('Ending soon'));
              await settleSports(tester);
              expect(find.text('Ending soon'), findsOneWidget);
              await tester
                  .tap(find.byKey(const ValueKey('replay-sort-picker')));
              await settleSports(tester);
              await tester.tap(find.text('Recent events'));
              await settleSports(tester);
              expect(find.byKey(const ValueKey('replay-channel-directory')),
                  findsNothing);
              await tester.tap(find.byKey(const ValueKey('replay-options')));
              await settleSports(tester);
              await tester.tap(find.byWidgetPredicate(
                  (w) => w is PopupMenuItem<String> && w.value == 'likely'));
              await settleSports(tester);
              expect(find.textContaining('4 shown'), findsOneWidget);
              await tester.tap(find.byKey(const ValueKey('replay-options')));
              await settleSports(tester);
              await tester.tap(find.byWidgetPredicate(
                  (w) => w is PopupMenuItem<String> && w.value == 'likely'));
              await settleSports(tester);
              expect(find.textContaining('5 shown'), findsOneWidget);
              await tester
                  .tap(find.byKey(const ValueKey('replay-date-picker')));
              await settleSports(tester);
              await captureSports(tester, size, 'replay-browser');
              await tester.tap(find.text('Date unclear'));
              await settleSports(tester);
              expect(find.textContaining('3 shown'), findsOneWidget);
              await tester
                  .tap(find.byKey(const ValueKey('replay-date-picker')));
              await settleSports(tester);
              await tester.tap(find.text('All dates'));
              await settleSports(tester);
              expect(find.textContaining('5 shown'), findsOneWidget);
              await tester
                  .tap(find.byKey(const ValueKey('replay-sort-picker')));
              await settleSports(tester);
              expect(find.text('Past 4 weeks'), findsNothing);
              expect(find.text('By sport'), findsNothing);
              await tester.tap(find.text('Top leagues'));
              await settleSports(tester);
              await tester
                  .tap(find.byKey(const ValueKey('replay-sport-picker')));
              await settleSports(tester);
              await tester.tap(find.descendant(
                  of: find.byType(SimpleDialog),
                  matching: find.text('Basketball')));
              await settleSports(tester);
              expect(find.textContaining('1 shown'), findsOneWidget);
              expect(playback.played.length, beforeReplays);
              await tester
                  .tap(find.byKey(const ValueKey('replay-sport-picker')));
              await settleSports(tester);
              await tester.tap(find.descendant(
                  of: find.byType(SimpleDialog),
                  matching: find.text('All sports')));
              await settleSports(tester);
              expect(find.textContaining('5 shown'), findsOneWidget);
              final catalogueLoads = playlist.catalogueLoads;
              await tester.tap(find.byKey(const ValueKey('replays-refresh')));
              await settleSports(tester);
              expect(playlist.catalogueLoads, catalogueLoads);
              final replayScroll = find.byKey(const ValueKey('replays-scroll'));
              final replayPull = await tester.startGesture(
                  tester.getTopLeft(replayScroll) + const Offset(20, 12));
              for (var i = 0; i < 8; i++) {
                await replayPull.moveBy(const Offset(0, 40));
                await tester.pump(const Duration(milliseconds: 40));
              }
              await replayPull.up();
              await settleSports(tester);
              expect(find.text('Couldn’t refresh'), findsNothing);
              expect(playlist.catalogueLoads, catalogueLoads);
              expect(playback.played.length, beforeReplays);
              expect(playback.currentChannel?.name, 'Fox Sports');
              expect(find.byType(VideoPlayerPane), findsOneWidget);
              expect(find.byKey(const ValueKey('replay-heading-basketball')),
                  findsOneWidget);
              await tester.pump(const Duration(seconds: 2));
              await settleSports(tester);
              await captureSports(tester, size, 'sports-replays');
              final replayCard = find.byWidgetPredicate((w) =>
                  w is InkWell &&
                  (w.key?.toString().contains('replay-demo::Fox Sports:') ??
                      false));
              expect(replayCard, findsOneWidget);
              await tester.longPress(replayCard);
              await settleSports(tester);
              expect(
                  find.text('Replay identified in the guide'), findsOneWidget);
              expect(
                  find.descendant(
                    of: find.byType(Dialog),
                    matching: find.textContaining('Madison Square Garden'),
                  ),
                  findsOneWidget);
              await captureSports(tester, size, 'sports-replay-channels');
              await tester.tap(find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.text('Fox Sports HD')));
              await settleSports(tester);
              expect(playback.currentChannel?.name, 'Fox Sports HD');
              expect(playback.played.length, beforeReplays + 1);
              await tester
                  .tap(find.byKey(const ValueKey('replay-sport-picker')));
              await settleSports(tester);
              await tester.tap(find.descendant(
                  of: find.byType(SimpleDialog),
                  matching: find.text('Volleyball')));
              await settleSports(tester);
              expect(find.textContaining('1 shown'), findsOneWidget);
              expect(find.textContaining('NCAA Women’s Volleyball'),
                  findsOneWidget);
              // Remote OK tunes the exact programme channel once.
              final volleyball = find.byWidgetPredicate((w) =>
                  w is InkWell &&
                  (w.key?.toString().contains('replay-demo::ABC HD:') ??
                      false));
              tester.widget<InkWell>(volleyball).focusNode!.requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(LogicalKeyboardKey.select);
              await settleSports(tester);
              expect(playback.currentChannel?.name, 'ABC HD');
              expect(playback.played.length, beforeReplays + 2);
              // Missing guide listings are explicit, don't start streams when
              // opened, and only tune the channel the user actually chooses.
              await tester.tap(find.byKey(const ValueKey('replay-options')));
              await settleSports(tester);
              await tester
                  .tap(find.byKey(const ValueKey('replay-channel-directory')));
              await settleSports(tester);
              expect(find.textContaining('availability is unverified'),
                  findsOneWidget);
              expect(playback.played.length, beforeReplays + 2);
              await captureSports(tester, size, 'replay-directory');
              await tester.tap(find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.text('NFL Replay 1')));
              await settleSports(tester);
              expect(playback.currentChannel?.name, 'NFL Replay 1');
              expect(playback.played.length, beforeReplays + 3);
              // The highlights view tab is gone; its panel survives only as
              // a widget. Coverage resumes with the replays already playing.
              expect(tester.takeException(), isNull);
              tester
                  .widget<TextButton>(
                      find.byKey(const ValueKey('sports-view-events')))
                  .focusNode!
                  .requestFocus();
              await tester.pumpAndSettle();
              await tester.sendKeyEvent(LogicalKeyboardKey.select);
              await settleSports(tester);
              epg.replays = [];
              // An empty matched-channel result stays useful and can be cleared.
              playlist.fixtureChannels.clear();
              playlist.notifyListeners();
              await tester
                  .ensureVisible(find.byKey(const ValueKey('sports-day')));
              await tester.tap(find.byKey(const ValueKey('sports-day')));
              await tester.pump(const Duration(milliseconds: 200));
              await tester.tap(find.text('Tomorrow'));
              await tester.pump(const Duration(milliseconds: 200));
              await tester.runAsync(() =>
                  Future<void>.delayed(const Duration(milliseconds: 400)));
              await tester.pump(const Duration(milliseconds: 200));
              await tester.tap(find.byKey(const ValueKey('sports-day')));
              await tester.pump(const Duration(milliseconds: 200));
              await tester
                  .ensureVisible(find.byKey(const ValueKey('sports-day')));
              await tester.tap(find.text('Today'));
              await tester.pump(const Duration(milliseconds: 200));
              await tester.runAsync(() =>
                  Future<void>.delayed(const Duration(milliseconds: 200)));
              await tester.pump(const Duration(milliseconds: 200));
              await settleSports(tester);
              expect(
                  find.text('No games with a matched channel'), findsOneWidget);
              await chooseChannelFilter('all');
              await tester.pump(const Duration(milliseconds: 200));
              expect(find.byKey(const ValueKey('card-nba:0')), findsOneWidget);
              expect(tester.takeException(), isNull);
              if (size.width < 600) {
                expect(
                    find.byKey(const ValueKey('bottom-live')), findsOneWidget);
                await tester.tap(find.byKey(const ValueKey('bottom-settings')));
                await tester.tap(find.byKey(const ValueKey('bottom-settings')));
                await settleSports(tester);
                expect(find.byType(SportsScreen), findsNothing);
                expect(playback.currentChannel?.name, 'NFL Replay 1');
                expect(find.text('Settings'), findsWidgets);
                await tester.tap(find.byKey(const ValueKey('bottom-sports')));
                await settleSports(tester);
                final beforeReturn = playback.played.length;
                expect(playback.currentChannel?.name, 'NFL Replay 1');
                await tester.tap(find.byKey(const ValueKey('bottom-live')));
                await settleSports(tester);
                expect(playback.played.length, beforeReturn);
                expect(playback.currentChannel?.name, 'NFL Replay 1');
                expect(find.byType(SportsScreen), findsNothing);
                expect(
                    find.byKey(const ValueKey('bottom-live')), findsOneWidget);
              }
              await tester.pumpWidget(const SizedBox());
              SportsChannelMatcher.disposeShared();
              await tester.pump(const Duration(seconds: 31));
              prefs.dispose();
              playlist.dispose();
              playback.dispose();
              epg.dispose();
            },
                () => MockClient((request) async {
                      if (request.url.path.contains('/tennis/')) {
                        return layoutTennisFixture();
                      }
                      if (!['/nba/', '/nhl/', '/nfl/']
                          .any(request.url.path.contains)) {
                        return http.Response('{"events":[]}', 200);
                      }
                      if (request.url.path.endsWith('/scoreboard')) {
                        scoreRequests++;
                      }
                      return http.Response(
                          jsonEncode({
                            'events': [
                              for (var i = 0; i < 5; i++)
                                {
                                  'id': '$i',
                                  'date':
                                      DateTime.now().toUtc().toIso8601String(),
                                  'competitions': [
                                    {
                                      'status': {
                                        'type': {
                                          'state': i < 3 ? 'in' : 'pre',
                                          'shortDetail':
                                              i < 3 ? 'Q3 06:24' : 'Tonight'
                                        }
                                      },
                                      'broadcasts': [
                                        if (i != 0)
                                          {
                                            'names': ['Fox Sports']
                                          }
                                      ],
                                      'competitors': [
                                        {
                                          'homeAway': 'home',
                                          'score': '84',
                                          'team': {
                                            'id': 'b$i',
                                            'displayName': request.url.path
                                                    .contains('/football/')
                                                ? 'Buffalo Bills'
                                                : request.url.path
                                                        .contains('/hockey/')
                                                    ? 'Vancouver Canucks'
                                                    : 'Boston Celtics',
                                            'shortDisplayName': request.url.path
                                                    .contains('/football/')
                                                ? 'Bills'
                                                : request.url.path
                                                        .contains('/hockey/')
                                                    ? 'Canucks'
                                                    : 'Celtics',
                                            'abbreviation': request.url.path
                                                    .contains('/football/')
                                                ? 'BUF'
                                                : request.url.path
                                                        .contains('/hockey/')
                                                    ? 'VAN'
                                                    : 'BOS'
                                          }
                                        },
                                        {
                                          'homeAway': 'away',
                                          'score': '78',
                                          'team': {
                                            'id': 'l$i',
                                            'displayName': request.url.path
                                                    .contains('/football/')
                                                ? 'Kansas City Chiefs'
                                                : request.url.path
                                                        .contains('/hockey/')
                                                    ? 'Edmonton Oilers'
                                                    : 'Los Angeles Lakers',
                                            'shortDisplayName': request.url.path
                                                    .contains('/football/')
                                                ? 'Chiefs'
                                                : request.url.path
                                                        .contains('/hockey/')
                                                    ? 'Oilers'
                                                    : 'Lakers',
                                            'abbreviation': request.url.path
                                                    .contains('/football/')
                                                ? 'KC'
                                                : request.url.path
                                                        .contains('/hockey/')
                                                    ? 'EDM'
                                                    : 'LAL'
                                          }
                                        },
                                      ],
                                    }
                                  ],
                                }
                            ],
                          }),
                          200);
                    })));
  }
}
