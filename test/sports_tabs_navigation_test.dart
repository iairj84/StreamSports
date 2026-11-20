import 'package:nox_iptv/services/sports_standings_service.dart';
import 'sports_standings_service_test.dart' as standings_fixture;
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
    const Size(320, 568),
    const Size(844, 390),
    const Size(960, 540)
  ]) {
    testWidgets(
        'sports tabs separate touch selection and remote focus at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final previousStrategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      addTearDown(
          () => FocusManager.instance.highlightStrategy = previousStrategy);
      setLayoutPreferences({'sports_online_extras': false});
      final storage = StorageService();
      await storage.init();
      await storage.setSportsLeagues(['nhl']);
      await storage.setSportsChannelFilter('all');
      final prefs = AppPreferences(storage);
      await prefs.init();
      final tv = prefs.isTelevision = size.width == 960;
      final playlist = LayoutPlaylist(storage, CatalogDatabase());
      final playback = LayoutPlayback(storage, playlist);
      final guide = LayoutEpg(storage), scores = LayoutInlineScores();
      final standings = SportsStandingsService(
          client: MockClient((_) async =>
              http.Response(standings_fixture.table(teams: 8), 200)));
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
              home: SportsScreen(
                  scores: scores,
                  standings: standings,
                  clock: () => scores.start))));
      await settleSports(tester);
      Finder tab(String id) => find.byKey(ValueKey('sports-view-$id'));
      FocusNode node(String id) =>
          tester.widget<TextButton>(tab(id)).focusNode!;
      const ids = ['events', 'standings', 'schedule', 'replays'];
      void expectTabs(String selected, {String? outlined}) {
        for (final id in ids) {
          final button = tester.widget<TextButton>(tab(id));
          final semantics = button.child! as Semantics;
          expect(semantics.properties.selected, id == selected,
              reason: '$id selection');
          final underline =
              ((semantics.child! as Container).decoration! as BoxDecoration)
                  .border! as Border;
          expect(underline.bottom.color.a > 0, id == selected,
              reason: '$id underline');
          final material = tester
              .widgetList<Material>(
                  find.descendant(of: tab(id), matching: find.byType(Material)))
              .firstWhere((m) => m.type == MaterialType.button);
          expect((material.shape! as RoundedRectangleBorder).side.color.a > 0,
              id == outlined,
              reason: '$id focus border');
          expect(material.color!.a > 0, id == outlined,
              reason: '$id focus fill');
        }
      }

      node('events').requestFocus();
      await tester.pumpAndSettle();
      expectTabs('events', outlined: tv ? 'events' : null);
      await tester.tap(tab('standings'));
      await settleSports(tester);
      expect(node('standings').hasFocus, isTrue);
      expectTabs('standings', outlined: tv ? 'standings' : null);
      final calls = scores.calls;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      await tester.pumpAndSettle();
      expectTabs('standings', outlined: 'standings');
      expect(scores.calls, calls,
          reason: 'Changing input mode only repaints tabs');
      final standingsPanel =
          find.byKey(const ValueKey('sports-inline-standings'));
      final retained = tester.widget(standingsPanel);
      final screenContext = tester.element(find.byType(SportsScreen));
      unawaited(showDialog<void>(
          context: screenContext,
          builder: (context) => AlertDialog(actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close probe'))
              ])));
      await tester.pumpAndSettle();
      expect(tester.widget(standingsPanel), same(retained),
          reason: 'A popup must not rebuild unchanged Sports content');
      await tester.tap(find.text('Close probe'));
      await tester.pumpAndSettle();
      expect(tester.widget(standingsPanel), same(retained));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(node('events').hasFocus, isTrue);
      expectTabs('standings', outlined: 'events');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleSports(tester);
      expectTabs('events', outlined: 'events');
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
      for (final id in ['schedule', 'standings', 'replays', 'events']) {
        await tester.ensureVisible(tab(id));
        await tester.pumpAndSettle();
        await tester.tap(tab(id));
        await settleSports(tester);
        expect(node(id).hasFocus, isTrue);
        expectTabs(id, outlined: tv ? id : null);
      }
      // Real key input restores keyboard focus visuals on a touch device.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(node('standings').hasFocus, isTrue);
      expectTabs('events', outlined: 'standings');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleSports(tester);
      expectTabs('standings', outlined: 'standings');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expectTabs('standings');
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

  for (final destination in [
    'tab',
    'manager',
    'background',
    'covered',
    'dispose'
  ]) {
    testWidgets('favorite feed work stops on $destination and resumes safely',
        (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      setLayoutPreferences({'sports_online_extras': false});
      final storage = StorageService();
      await storage.init();
      await storage.setSportsLeagues(['nhl', 'nba', 'eng.1']);
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
      expect(scores.activityChecks, hasLength(1));
      final original = scores.activityChecks.single;
      expect(original(), isTrue);
      if (destination == 'tab') {
        await tester.tap(find.byKey(const ValueKey('sports-view-schedule')));
      } else if (destination == 'manager') {
        await tester.tap(find.byTooltip('Sports options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Leagues & teams'));
      } else if (destination == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      } else if (destination == 'covered') {
        Navigator.of(tester.element(find.byType(SportsScreen))).push<void>(
            MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Other page'))));
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      await tester.pump();
      expect(original(), isFalse,
          reason: 'Leaving must stop scheduling, not only hide progress.');
      await scores.firstBatch();
      scores.done.complete(scores.batch);
      // The held fixture never answers every feed, so its progress bar keeps
      // animating; pump a bounded window instead of waiting for stillness.
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      if (destination != 'dispose') {
        if (destination == 'manager') {
          await tester.tap(find.byKey(const ValueKey('close-leagues')));
        } else if (destination == 'background') {
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        } else if (destination == 'covered') {
          Navigator.of(tester.element(find.text('Other page'))).pop();
          await tester.pump(const Duration(seconds: 6));
        } else {
          await tester.tap(find.byKey(const ValueKey('sports-view-events')));
        }
        await settleSports(tester);
        expect(scores.activityChecks.length, greaterThan(1));
        expect(original(), isFalse,
            reason: 'Returning cannot revive old work.');
        expect(scores.activityChecks.last(), isTrue);
        expect(
            find.byKey(const ValueKey('sports-view-events')), findsOneWidget);
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

  for (final (clock, label, expected) in [
    (DateTime(2026, 4, 5, 12), 'Tomorrow', DateTime(2026, 4, 6)),
    (DateTime(2026, 10, 5, 12), 'Yesterday', DateTime(2026, 10, 4)),
  ]) {
    testWidgets(
        'sports day picker follows calendar dates across DST: $label from $clock',
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
      final scores = LayoutCalendarScores();
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
              home: SportsScreen(scores: scores, clock: () => clock))));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.ensureVisible(find.byKey(const ValueKey('sports-day')));
      await tester.tap(find.byKey(const ValueKey('sports-day')));
      await tester.pump(const Duration(milliseconds: 200));
      if (clock.month == 4) {
        expect(find.text('Tue 7 Apr'), findsOneWidget,
            reason: 'dated labels use the same calendar as requested events');
      }
      await tester.tap(find.text(label));
      await tester.pump(const Duration(milliseconds: 200));
      expect(scores.days.last, expected);
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
