import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/screens/sports_teams_screen.dart';
import 'package:nox_iptv/screens/sports_league_manager_screen.dart';
import 'package:nox_iptv/services/sports_follows.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/widgets/sports_panel.dart';
import 'package:nox_iptv/services/sports_service.dart';
import 'package:nox_iptv/services/sports_standings_service.dart';
import 'package:nox_iptv/widgets/compact_choice_list.dart';
import 'package:nox_iptv/widgets/sports_schedule_panel.dart';
import 'sports_panel_test.dart' as harness;
import 'sports_schedule_panel_test.dart' show DayScores;
import 'sports_teams_screen_test.dart' show RecordingStandings;

class SaveStorage extends StorageService {
  bool failOnce = false;
  Completer<void>? gate;
  @override
  Future<void> setSportsFavoriteLeague(String? value) async {
    if (failOnce) {
      failOnce = false;
      throw StateError('fixture failure');
    }
    await gate?.future;
    await super.setSportsFavoriteLeague(value);
  }
}

Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

bool focused(String id) {
  final node = FocusManager.instance.primaryFocus;
  bool found = false;
  node?.context?.visitAncestorElements((e) {
    if (e.widget.key == ValueKey(id)) found = true;
    return !found;
  });
  return found;
}

Widget layout(Widget filters, Widget actions, Widget content) =>
    Column(children: [
      SizedBox(
          height: 48,
          child: Row(children: [
            const SizedBox(
                width: 350,
                child: TextButton(onPressed: null, child: Text('Tabs'))),
            Expanded(child: filters),
            actions
          ])),
      Expanded(
          child: Row(children: [
        const SizedBox(width: 350),
        Expanded(child: content)
      ])),
    ]);
void main() {
  testWidgets('TV league manager keeps search first and bulk controls compact',
      (tester) async {
    harness.viewport(tester, const Size(960, 540));
    final (storage, prefs) = await harness.preferences(true);
    addTearDown(prefs.dispose);
    // One shown league leaves both bulk buttons usable for the focus walk.
    await storage.setSportsLeagues(['nfl']);
    await tester.pumpWidget(harness.app(
        storage, prefs, const SportsLeagueManagerScreen(embedded: true)));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('league-manager-search'));
    final tabs = find.byKey(const ValueKey('follow-tabs'));
    final bulk = find.byKey(const ValueKey('show-visible-leagues'));
    expect(tester.getSize(search).height, 34);
    expect(tester.getRect(tabs).bottom, lessThan(tester.getRect(search).top));
    expect(tester.getRect(search).bottom, lessThan(tester.getRect(bulk).top));
    expect(tester.getSize(bulk).height, 28);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focused('league-manager-search'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused('league-manager-search'), isFalse,
        reason: 'Down leaves search for the bulk row, not the tree.');
    expect(find.byKey(const ValueKey('league-manager-state')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty league draft can close, restore and recover from a failed replacement',
      (tester) async {
    harness.viewport(tester, const Size(390, 844));
    final (_, prefs) = await harness.preferences(false);
    addTearDown(prefs.dispose);
    final storage = SaveStorage();
    await storage.init();
    await storage.setHiddenGuideLeagues(
        kAutomaticSportsLeagues.map((l) => l.id).toList());
    await storage.setSportsFavoriteLeague('nhl');
    bool? changed;
    await tester.pumpWidget(harness.app(
        storage,
        prefs,
        Builder(
            builder: (context) => TextButton(
                onPressed: () async {
                  changed = await showSportsPanel<bool>(
                      context: context,
                      builder: (_) =>
                          const SportsLeagueManagerScreen(embedded: true));
                },
                child: const Text('Open')))));
    Future<void> clear() async {
      await tester.tap(find.byKey(const ValueKey('hide-visible-leagues')));
      await tester.pumpAndSettle();
      expect(savedSportsLeagues(storage).map((l) => l.id), ['nhl']);
      expect(storage.getSportsFavoriteLeague(), 'nhl');
      expect(find.byType(SnackBar), findsNothing);
    }

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await clear();
    await tester.tap(find.byKey(const ValueKey('close-leagues')));
    await tester.pumpAndSettle();
    expect(changed, isFalse);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await clear();
    await tester.enterText(
        find.byKey(const ValueKey('league-manager-search')), 'NBA');
    await tester.pumpAndSettle();
    storage.failOnce = true;
    await tester.tap(find.byKey(const ValueKey('nba')));
    await tester.pumpAndSettle();
    expect(savedSportsLeagues(storage).map((l) => l.id), ['nhl']);
    expect(storage.getSportsFavoriteLeague(), 'nhl');
    expect(find.textContaining('0 shown · Choose leagues to finish'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nba')));
    await tester.pumpAndSettle();
    expect(savedSportsLeagues(storage).map((l) => l.id), ['nba']);
    expect(storage.getSportsFavoriteLeague(), isNull);
    await tester.tap(find.byKey(const ValueKey('close-leagues')));
    await tester.pumpAndSettle();
    expect(changed, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('league search retains keyboard and compact layout at $size',
        (tester) async {
      harness.viewport(tester, size);
      final (storage, prefs) = await harness.preferences(false);
      addTearDown(prefs.dispose);
      Widget screen(double keyboard) => harness.app(
          storage, prefs, const SportsLeagueManagerScreen(embedded: true),
          keyboard: keyboard);
      await tester.pumpWidget(screen(0));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('league-manager-search'));
      await tester.enterText(search, 'No matching league xyz');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clear-league-filters')));
      await tester.pumpAndSettle();
      final state = tester.state<EditableTextState>(find.byType(EditableText));
      await tester.pumpWidget(screen(size.width > size.height ? 180 : 280));
      await tester.pumpAndSettle();
      expect(tester.state<EditableTextState>(find.byType(EditableText)),
          same(state));
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(search.hitTestable(), findsOneWidget);
      await tester.enterText(search, 'NBA');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nba')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'league write failure rolls back; close waits for an in-flight save',
      (tester) async {
    harness.viewport(tester, const Size(960, 540));
    final (_, prefs) = await harness.preferences(true);
    addTearDown(prefs.dispose);
    final storage = SaveStorage();
    await storage.init();
    await storage.setSportsAddedLeagues([]);
    await storage.setHiddenGuideLeagues(
        kAutomaticSportsLeagues.map((l) => l.id).toList());
    bool? changed;
    await tester.pumpWidget(harness.app(
        storage,
        prefs,
        Builder(
            builder: (context) => TextButton(
                onPressed: () async {
                  changed = await showSportsPanel<bool>(
                      context: context,
                      builder: (_) =>
                          const SportsLeagueManagerScreen(embedded: true));
                },
                child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    storage.failOnce = true;
    await tester.tap(find.byKey(const ValueKey('show-all-leagues')));
    await tester.pumpAndSettle();
    expect(savedSportsLeagues(storage).map((l) => l.id), ['nhl']);
    expect(
        find.text('Could not save leagues. Please try again.'), findsOneWidget);
    storage.gate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('show-all-leagues')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('close-leagues')));
    await tester.pump();
    expect(find.byType(SportsLeagueManagerScreen), findsOneWidget);
    storage.gate!.complete();
    await tester.pumpAndSettle();
    expect(changed, isTrue);
    expect(find.text('Open').hitTestable(), findsOneWidget);
    expect(storage.getSportsAllLeagues(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('league search keeps typing focus after an empty result',
      (tester) async {
    harness.viewport(tester, const Size(390, 844));
    final (storage, prefs) = await harness.preferences(false);
    addTearDown(prefs.dispose);
    await tester.pumpWidget(harness.app(
        storage, prefs, const SportsLeagueManagerScreen(embedded: true)));
    await tester.pumpAndSettle();
    final finder = find.byKey(const ValueKey('league-manager-search'));
    await tester.enterText(finder, 'zzzxxyyno-league');
    await tester.pumpAndSettle();
    expect(find.text('No matching leagues'), findsOneWidget);
    await tester.enterText(finder, 'Premier');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(finder).focusNode!.hasFocus, isTrue);
    expect(find.byType(CompactChoiceList), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('league paging and held OK work without losing the selected row',
      (tester) async {
    harness.viewport(tester, const Size(960, 540));
    final (storage, prefs) = await harness.preferences(true);
    addTearDown(prefs.dispose);
    // One open sport keeps the first league row one press below its sport.
    await storage.setSportsLeagues(['nfl']);
    await tester.pumpWidget(harness.app(
        storage, prefs, const SportsLeagueManagerScreen(embedded: true)));
    await tester.pumpAndSettle();
    final choices = tester
        .widget<CompactChoiceList>(find.byType(CompactChoiceList))
        .choices;
    await key(tester, LogicalKeyboardKey.end);
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'choice-${choices.last.id}');
    await key(tester, LogicalKeyboardKey.home);
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'choice-${choices.first.id}');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'choice-nfl');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Set as opening league'), findsOneWidget);
    await tester.tap(find.text('Set as opening league'));
    await tester.pumpAndSettle();
    expect(storage.getSportsFavoriteLeague(), 'nfl');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'choice-nfl');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'schedule remote crosses every control, returns through local rows, and keeps requests bounded',
      (tester) async {
    harness.viewport(tester, const Size(960, 540));
    final (storage, prefs) = await harness.preferences(true);
    addTearDown(prefs.dispose);
    final entry = FocusNode();
    addTearDown(entry.dispose);
    final scores = DayScores();

    await tester.pumpWidget(harness.app(
        storage,
        prefs,
        SportsSchedulePanel(
            browseState: SportsScheduleBrowseState(),
            entryFocus: entry,
            onFocusToolbar: () {
              fail('Local rows must not jump to left tabs');
            },
            service: scores,
            overviewLeagues: [
              sportsLeagueById('nba')!,
              sportsLeagueById('eng.1')!
            ],
            clock: () => DateTime(2026, 11, 3),
            layoutBuilder: layout)));
    await tester.pumpAndSettle();
    entry.requestFocus();
    await tester.pump();
    expect(focused('schedule-range-1'), isTrue);
    for (final id in [
      'schedule-range-7',
      'schedule-range-30',
      'schedule-display',
      'schedule-date',
      'schedule-search-toggle'
    ]) {
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(id), isTrue, reason: id);
    }
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused('schedule-previous'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focused('schedule-search-toggle'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focused('schedule-league'), isTrue);
    entry.requestFocus();
    await tester.pump();
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(
        FocusManager.instance.primaryFocus?.debugLabel, startsWith('choice-'));
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focused('schedule-previous'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focused('schedule-range-1'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.enter);
    expect(focused('schedule-range-7'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus, isNot(entry));
    expect(scores.days.length, 1,
        reason:
            'Navigation and unopened calendar summaries do not fetch dates');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'standings Up leaves the first row through search and league, not left tabs',
      (tester) async {
    harness.viewport(tester, const Size(960, 540));
    final (storage, prefs) = await harness.preferences(true);
    addTearDown(prefs.dispose);
    final data = LeagueStandings(tables: [
      StandingTable('Table', [
        for (var i = 0; i < 100; i++)
          StandingTeam(
              SportsTeam(
                  id: '$i',
                  name: 'Club $i',
                  shortName: 'Club',
                  abbreviation: 'C'),
              {'points': '10'},
              i + 1)
      ])
    ]);
    final service = RecordingStandings(data: data);
    addTearDown(service.close);
    await tester.pumpWidget(harness.app(
        storage,
        prefs,
        SportsTeamsScreen(
            follows: SportsFollows.load(storage),
            service: service,
            initialLeague: sportsLeagueById('eng.1'),
            embedded: true,
            layoutBuilder: layout,
            onFocusToolbar: () {
              fail('Search must return to the league dropdown');
            })));
    await tester.pumpAndSettle();
    final node = FocusManager.instance.rootScope.traversalDescendants
        .firstWhere((n) =>
            n.context?.findAncestorWidgetOfExactType<InkWell>()?.key ==
            const ValueKey('record-0'));
    node.requestFocus();
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
    }
    for (var i = 0; i < 12; i++) {
      await key(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(focused('record-0'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focused('standings-search'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focused('standings-league'), isTrue);
    expect(service.loads, 1);
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(960, 540)
  ]) {
    testWidgets(
        'the sport tree opens in place and bulk changes affect only the leagues it lists, with remote paging at $size',
        (tester) async {
      harness.viewport(tester, size);
      final (storage, prefs) = await harness.preferences(size.width == 960);
      addTearDown(prefs.dispose);
      await storage.setSportsLeagues(['mlb']);
      await storage.setSportsAddedLeagues([]);
      await storage.setHiddenGuideLeagues(
          kAutomaticSportsLeagues.map((l) => l.id).toList());
      await tester.pumpWidget(harness.app(
          storage, prefs, const SportsLeagueManagerScreen(embedded: true)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sport:football')));
      await tester.pumpAndSettle();
      final ids = {
        for (final choice
            in tester
                .widget<CompactChoiceList>(find.byType(CompactChoiceList))
                .choices)
          if (!choice.id.startsWith('sport:')) choice.id
      };
      expect(ids, containsAll(['mlb', 'nfl', 'college-football']));
      expect(ids, isNot(contains('nhl')),
          reason: 'Only the open sports list their leagues.');

      await tester.tap(find.byKey(const ValueKey('show-visible-leagues')));
      await tester.pumpAndSettle();
      final saved = savedSportsLeagues(storage).map((l) => l.id).toSet();
      expect(saved,
          containsAll(['mlb', 'nfl', 'college-football', 'baseball.college-baseball']),
          reason: 'Show listed covers every league of the open sports.');
      expect(saved, isNot(contains('nba')),
          reason: 'A closed sport is never changed in bulk.');
      expect(saved, isNot(contains('nhl')));

      await tester.tap(find.byKey(const ValueKey('hide-visible-leagues')));
      await tester.pumpAndSettle();
      expect(savedSportsLeagues(storage).map((l) => l.id).toSet(), saved,
          reason: 'Hiding everything listed is a draft, never a save.');
      expect(find.textContaining('0 shown · Choose leagues to finish'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('league-manager-state')), findsNothing,
          reason: 'One list: inclusion is the only filter');

      await tester.tap(find.byKey(const ValueKey('restore-league-selection')));
      await tester.pumpAndSettle();
      expect(find.textContaining('${saved.length} shown · Saved automatically'),
          findsOneWidget);

      final search = find.byKey(const ValueKey('league-manager-search'));
      await tester.tap(search);
      if (prefs.isTelevision) {
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
      }
      await tester.enterText(search, 'NBA');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nba')));
      await tester.pumpAndSettle();
      expect(savedSportsLeagues(storage).map((l) => l.id), contains('nba'));
      expect(tester.takeException(), isNull);
    });
  }
}
