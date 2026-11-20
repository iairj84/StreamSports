// Shared fixtures for the live-layout suites: the fake playlist, guide,
// playback and score services plus the pump and capture helpers that
// live_layout_navigation_test.dart, sports_tabs_navigation_test.dart,
// sports_panels_navigation_test.dart, sports_card_navigation_test.dart,
// sports_matching_navigation_test.dart and live_layout_fit_test.dart all use.
//
// Split out of one 6,461-line file so the suites run in parallel isolates;
// the tests themselves are unchanged. Keep fake services here so every suite
// exercises the same harness.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/models/epg_program.dart';
import 'package:nox_iptv/models/m3u_group.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/models/sports_progress.dart';
import 'package:nox_iptv/services/epg_service.dart';
import 'package:nox_iptv/services/playback_service.dart';
import 'package:nox_iptv/services/playlist_manager.dart';
import 'package:nox_iptv/services/sports_supplement_service.dart';
import 'package:nox_iptv/services/sports_service.dart';

class LayoutSupplement extends SportsSupplementService {
  LayoutSupplement()
      : super.withClient(MockClient((_) async => http.Response('{}', 200)));
  int warms = 0, loads = 0;
  final games = [
    SportsGame(
      id: 'extra-demo',
      league: sportsLeagueById('tennis.atp')!,
      start: DateTime.now(),
      state: GameState.live,
      statusText: 'Live',
      source: 'TheSportsDB',
      home: const SportsTeam(
          id: 'a', name: 'Extra Player', shortName: 'Extra', abbreviation: ''),
      away: const SportsTeam(
          id: 'b',
          name: 'Another Player',
          shortName: 'Another',
          abbreviation: ''),
      event: const SportsEventInfo(title: 'European Open'),
    )
  ];
  @override
  Future<void> warmBroadcasts(List<SportsGame> games,
      {required bool Function() cancelled}) async {
    warms++;
  }

  @override
  Future<List<SportsGame>> gamesForDay(List<SportsLeague> leagues, DateTime day,
      {bool Function()? cancelled}) async {
    loads++;
    return games;
  }

  @override
  List<SportsGame> cachedGamesForDay(
          List<SportsLeague> leagues, DateTime day) =>
      loads == 0 ? const [] : games;
}

class LayoutPollingScores extends SportsService {
  LayoutPollingScores({DateTime? start})
      : start = start ?? DateTime.now(),
        super.withClient(MockClient((_) async => http.Response('{}', 200)));
  final DateTime start;
  int calls = 0;

  // This fixture supplies its complete schedule in memory. Do not inherit the
  // network/parser fallback when navigation selects a league with no rows.
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
  @override
  Future<List<SportsGame>> gamesForDay(List<SportsLeague> leagues, DateTime day,
      {void Function(List<SportsGame>)? onProgress,
      bool forceRefresh = false,
      void Function(SportsWorkProgress)? onStatus}) async {
    calls++;
    return [
      for (var i = 0; i < (calls == 1 ? 216 : 217); i++)
        SportsGame(
            id: 'poll-$i',
            league: sportsLeagueById('nhl')!,
            start: start,
            state: GameState.live,
            statusText: 'Live',
            home: SportsTeam(
                id: 'h$i',
                name: i == 216 ? 'Zebrafish United' : 'Boston Bruins',
                shortName: 'Home',
                abbreviation: 'H',
                score: '$calls'),
            away: const SportsTeam(
                id: 'a',
                name: 'Toronto Maple Leafs',
                shortName: 'Away',
                abbreviation: 'A'))
    ];
  }
}

class LayoutInlineScores extends LayoutPollingScores {
  @override
  Future<({List<SportsGame> games, bool incomplete})> scheduleGames(
          SportsLeague league, DateTime from, DateTime through,
          {bool Function()? shouldContinue}) async =>
      (games: await gamesForDay([league], from), incomplete: false);

  @override
  Future<({List<SportsGame> games, bool incomplete})> scheduleDay(
          List<SportsLeague> leagues, DateTime day,
          {bool Function()? shouldContinue,
          void Function(List<SportsGame>)? onProgress}) async =>
      (games: await gamesForDay(leagues, day), incomplete: false);
}

class LayoutBrowseScores extends LayoutPollingScores {
  LayoutBrowseScores({super.start});
  final requestedLeagues = <List<String>>[];
  @override
  Future<({List<SportsGame> games, bool incomplete})> scheduleGames(
          SportsLeague league, DateTime from, DateTime through,
          {bool Function()? shouldContinue}) async =>
      (games: const <SportsGame>[], incomplete: false);
  @override
  Future<({List<SportsGame> games, bool incomplete})> scheduleDay(
          List<SportsLeague> leagues, DateTime day,
          {bool Function()? shouldContinue,
          void Function(List<SportsGame>)? onProgress}) async =>
      (games: const <SportsGame>[], incomplete: false);
  @override
  Future<List<SportsGame>> gamesForDay(List<SportsLeague> leagues, DateTime day,
      {void Function(List<SportsGame>)? onProgress,
      bool forceRefresh = false,
      void Function(SportsWorkProgress)? onStatus}) async {
    calls++;
    requestedLeagues.add(leagues.map((l) => l.id).toList());
    return [
      for (var i = 0; i < 24; i++)
        SportsGame(
          id: 'browse-$i',
          league: sportsLeagueById('nhl')!,
          start: start,
          state: GameState.live,
          statusText: 'Live',
          home: SportsTeam(
              id: 'h$i',
              name: 'Homealpha${String.fromCharCode(97 + i)}',
              shortName: 'Homealpha${String.fromCharCode(97 + i)}',
              abbreviation: '',
              score: '$calls'),
          away: SportsTeam(
              id: 'a$i',
              name: 'Awaybeta${String.fromCharCode(97 + i)}',
              shortName: 'Awaybeta${String.fromCharCode(97 + i)}',
              abbreviation: ''),
        )
    ];
  }

  List<EpgProgram> rows({int from = 0}) => [
        for (var i = from; i < 24; i++)
          EpgProgram(
              channelId: 'feed-$i',
              title:
                  'Ice Hockey: Homealpha${String.fromCharCode(97 + i)} vs Awaybeta${String.fromCharCode(97 + i)}',
              start: start.subtract(const Duration(minutes: 5)),
              stop: start.add(const Duration(hours: 2)))
      ];
}

class LayoutFilterScopeScores extends LayoutBrowseScores {
  @override
  Future<List<SportsGame>> gamesForDay(List<SportsLeague> leagues, DateTime day,
      {void Function(List<SportsGame>)? onProgress,
      bool forceRefresh = false,
      void Function(SportsWorkProgress)? onStatus}) async {
    calls++;
    requestedLeagues.add(leagues.map((l) => l.id).toList());
    return [
      for (final league in leagues)
        if (['nhl', 'eng.1', 'nba'].contains(league.id))
          for (var i = 0; i < 2; i++)
            SportsGame(
                id: 'scope-$i',
                league: league,
                start: start,
                state: GameState.live,
                statusText: 'Live',
                home: SportsTeam(
                    id: 'h$i',
                    name: 'Home $i',
                    shortName: 'Home $i',
                    abbreviation: 'H'),
                away: const SportsTeam(
                    id: 'a',
                    name: 'Away',
                    shortName: 'Away',
                    abbreviation: 'A'))
    ];
  }
}

class LayoutReopenScores extends LayoutBrowseScores {
  List<SportsGame> cached = [];
  Completer<List<SportsGame>>? pending;
  @override
  List<SportsGame> cachedGamesForDay(
          List<SportsLeague> leagues, DateTime day) =>
      cached
          .where((game) => leagues.any((l) => l.id == game.league.id))
          .toList();
  @override
  Future<List<SportsGame>> gamesForDay(List<SportsLeague> leagues, DateTime day,
      {void Function(List<SportsGame>)? onProgress,
      bool forceRefresh = false,
      void Function(SportsWorkProgress)? onStatus}) async {
    cached = pending != null
        ? await pending!.future
        : await super.gamesForDay(leagues, day);
    return cachedGamesForDay(leagues, day);
  }
}

class LayoutRowScores extends LayoutPollingScores {
  LayoutRowScores(
      {this.counts = const {},
      this.upcoming = const {},
      this.namedTeams = false});
  final bool namedTeams;
  final Map<String, int> counts;
  final Set<String> upcoming;
  @override
  Future<List<SportsGame>> gamesForDay(List<SportsLeague> leagues, DateTime day,
          {void Function(List<SportsGame>)? onProgress,
          bool forceRefresh = false,
          void Function(SportsWorkProgress)? onStatus}) async =>
      [
        for (final league in leagues)
          for (var i = 0;
              i < (counts[league.id] ?? (counts.isEmpty ? 20 : 0));
              i++)
            SportsGame(
                id: 'row-$i',
                league: league,
                start: start,
                state: upcoming.contains(league.id)
                    ? GameState.pre
                    : GameState.live,
                statusText: 'Live',
                home: SportsTeam(
                    id: 'h$i',
                    name: namedTeams ? 'Boston Bruins' : 'Home $i',
                    shortName: namedTeams ? 'Boston Bruins' : 'Home $i',
                    abbreviation: 'H'),
                away: SportsTeam(
                    id: 'a$i',
                    name: namedTeams ? 'Toronto Maple Leafs' : 'Away $i',
                    shortName: namedTeams ? 'Toronto Maple Leafs' : 'Away $i',
                    abbreviation: 'A'))
      ];
}

/// One live football game with a parsed ESPN situation — the hub card
/// must show who has the ball and the spot.
class LayoutPossessionScores extends LayoutPollingScores {
  @override
  Future<List<SportsGame>> gamesForDay(List<SportsLeague> leagues, DateTime day,
      {void Function(List<SportsGame>)? onProgress,
      bool forceRefresh = false,
      void Function(SportsWorkProgress)? onStatus}) async {
    calls++;
    return [
      SportsGame(
        id: 'possession-game',
        league: sportsLeagueById('nfl')!,
        start: start.subtract(const Duration(hours: 1)),
        state: GameState.live,
        statusText: '3rd 04:12',
        home: const SportsTeam(
            id: 'ne',
            name: 'New England Patriots',
            shortName: 'Patriots',
            abbreviation: 'NE',
            score: '14'),
        away: const SportsTeam(
            id: 'buf',
            name: 'Buffalo Bills',
            shortName: 'Bills',
            abbreviation: 'BUF',
            score: '10'),
        situation: const SportsSituation(
            text: '2nd & 7 at NE 32', possessionTeamId: 'ne'),
      )
    ];
  }
}

class LayoutHeldScores extends LayoutPollingScores {
  final activityChecks = <bool Function()>[];
  @override
  Future<List<SportsGame>> gamesForDayWhileActive(
      List<SportsLeague> leagues, DateTime day,
      {required bool Function() shouldContinue,
      bool forceRefresh = false,
      void Function(List<SportsGame>)? onProgress,
      void Function(SportsWorkProgress)? onStatus}) {
    activityChecks.add(shouldContinue);
    return super.gamesForDayWhileActive(leagues, day,
        shouldContinue: shouldContinue,
        forceRefresh: forceRefresh,
        onProgress: onProgress,
        onStatus: onStatus);
  }

  final done = Completer<List<SportsGame>>();
  void Function(List<SportsGame>)? publish;
  List<SportsGame> batch = [];
  @override
  Future<List<SportsGame>> gamesForDay(List<SportsLeague> leagues, DateTime day,
      {void Function(List<SportsGame>)? onProgress,
      bool forceRefresh = false,
      void Function(SportsWorkProgress)? onStatus}) {
    publish = onProgress;
    onStatus?.call(const SportsWorkProgress(SportsWorkStage.scores, total: 3));
    return done.future;
  }

  Future<void> firstBatch() async {
    batch =
        (await super.gamesForDay([sportsLeagueById('nhl')!], DateTime.now()))
            .take(1)
            .toList();
    publish?.call(batch);
  }
}

class LayoutCalendarScores extends LayoutPollingScores {
  final days = <DateTime>[];
  @override
  Future<List<SportsGame>> gamesForDay(List<SportsLeague> leagues, DateTime day,
      {void Function(List<SportsGame>)? onProgress,
      bool forceRefresh = false,
      void Function(SportsWorkProgress)? onStatus}) async {
    days.add(day);
    return [];
  }
}

class LayoutRecoveringScores extends LayoutHeldScores {
  final retries = <Completer<List<SportsGame>>>[];
  @override
  Future<List<SportsGame>> gamesForDay(List<SportsLeague> leagues, DateTime day,
      {void Function(List<SportsGame>)? onProgress,
      bool forceRefresh = false,
      void Function(SportsWorkProgress)? onStatus}) {
    if (publish == null) {
      return super.gamesForDay(leagues, day,
          onProgress: onProgress,
          forceRefresh: forceRefresh,
          onStatus: onStatus);
    }
    final request = Completer<List<SportsGame>>();
    retries.add(request);
    onStatus?.call(const SportsWorkProgress(SportsWorkStage.scores, total: 3));
    return request.future;
  }
}

class LayoutWarmGuide extends LayoutSlowGuide {
  LayoutWarmGuide(super.storage);
  int reads = 0;
  @override
  EpgProgram? getCurrentProgram(String id) {
    reads++;
    return super.getCurrentProgram(id);
  }
}

class LayoutSlowGuide extends LayoutEpg {
  LayoutSlowGuide(super.storage);
  final requests = <Completer<List<EpgProgram>>>[];
  @override
  Future<List<EpgProgram>> findProgrammesByTitle(
      DateTime from, DateTime to, List<String> terms,
      {List<String>? channelIds}) {
    final request = Completer<List<EpgProgram>>();
    requests.add(request);
    return request.future;
  }
}

class LayoutPriorityGuide extends LayoutEpg {
  LayoutPriorityGuide(super.storage);
  final laterGate = Completer<void>();
  final order = <String>[];
  bool held = false;
  @override
  Future<List<EpgProgram>> findProgrammesByTitle(
      DateTime from, DateTime to, List<String> terms,
      {List<String>? channelIds}) async {
    if (from.isAfter(DateTime.now().add(const Duration(hours: 1)))) {
      order.add('later');
      if (!held) {
        held = true;
        await laterGate.future;
      }
    } else if (terms.any((term) => term.contains('zebrafish'))) {
      order.add('urgent');
    }
    return [];
  }
}

class LayoutPlaylist extends PlaylistManager {
  LayoutPlaylist(super.storage, super.db);
  final fixtureChannels = [
    for (final name in [
      'ABC HD',
      'SBS HD',
      'Seven',
      'Nine',
      '10 HD',
      'ABC News',
      'SBS World',
      'Fox Sports',
      'Fox Sports HD'
    ])
      Channel(
          id: 'demo::$name',
          rawId: name,
          playlistId: 'demo',
          name: name,
          group: 'Australian TV',
          url: 'https://example.test/live'),
  ];
  @override
  bool get hasLiveChannels => channels.isNotEmpty;

  @override
  List<Channel> get channels => fixtureChannels;
  @override
  List<M3uGroup> get tvGroups => [
        M3uGroup(
            title: 'Australian TV',
            playlistId: 'demo',
            channels: fixtureChannels)
      ];
  @override
  List<Channel> visibleChannels(
          {String? playlistId, String? groupTitle, required String category}) =>
      groupTitle == null
          ? fixtureChannels
          : fixtureChannels.where((c) => c.group == groupTitle).toList();
  @override
  Future<void> ensureLiveChannelsLoaded() async {
    catalogueLoads++;
  }

  int catalogueLoads = 0;
}

class LayoutRailPlaylist extends LayoutPlaylist {
  LayoutRailPlaylist(super.storage, super.db);
  @override
  List<M3uGroup> get tvGroups => [
        for (final c in fixtureChannels)
          M3uGroup(title: c.group, playlistId: c.playlistId, channels: [c])
      ];
  @override
  List<Channel> get favoriteLiveChannelsWithGroups =>
      fixtureChannels.take(2).toList();
}

class LayoutPlayback extends PlaybackService {
  LayoutPlayback(super.storage, super.playlist);
  final played = <Channel>[];
  Completer<void>? openGate;
  Completer<void>? stopGate;
  final history = <Channel>[];
  @override
  List<Channel> recentLiveChannels({int limit = 10}) =>
      history.take(limit).toList();
  @override
  Future<void> play(Channel channel, {String? urlOverride}) async {
    played.add(channel);
    currentChannel = channel;
    notifyListeners();
    await openGate?.future;
  }

  @override
  Future<void> stop() async {
    await stopGate?.future;
    currentChannel = null;
    notifyListeners();
  }
}

class LayoutScheduleQueryEpg extends LayoutEpg {
  LayoutScheduleQueryEpg(super.storage);
  int queries = 0;
  @override
  Future<List<EpgProgram>> findSportsProgrammesForChannels(
      List<String> ids, DateTime from, DateTime to) {
    queries++;
    return super.findSportsProgrammesForChannels(ids, from, to);
  }

  @override
  Future<List<EpgProgram>> findProgrammesByTitle(
      DateTime from, DateTime to, List<String> terms,
      {List<String>? channelIds}) {
    queries++;
    return super.findProgrammesByTitle(from, to, terms, channelIds: channelIds);
  }
}

class LayoutDrillEpg extends LayoutEpg {
  LayoutDrillEpg(super.storage);
  late final anchor = DateTime(
      now.year, now.month, now.day, now.hour, now.minute - now.minute % 30);
  @override
  List<EpgProgram> getPrograms(String channelId) => [
        for (var i = -24; i < 96; i++)
          EpgProgram(
            channelId: channelId,
            title: 'Slot $i',
            start: anchor.add(Duration(minutes: i * 5)),
            stop: anchor.add(Duration(minutes: (i + 1) * 5)),
          ),
      ];
}

class LayoutEpg extends EpgService {
  LayoutEpg(super.storage);
  Completer<List<EpgProgram>>? pending;
  List<EpgProgram> replays = [];
  @override
  Future<List<EpgProgram>> findSportsProgrammesForChannels(
          List<String> ids, DateTime from, DateTime to) async =>
      replays
          .where((p) =>
              ids.contains(p.channelId) &&
              p.start.isBefore(to) &&
              p.stop.isAfter(from))
          .toList();
  /// This fake keeps its guide in the getters below: an empty slice keeps
  /// matching on that path instead of opening a real store in a widget test.
  @override
  Future<Map<String, List<EpgProgram>>> sportsGuideSlice(
          Iterable<String> channelIds) async =>
      const {};
  final withoutGuide = <String>{};
  @override
  Iterable<EpgProgram> cachedCurrentProgrammes(DateTime now) =>
      replays.where((p) => p.isNowPlaying(now));
  @override
  Future<List<EpgProgram>> findProgrammesByTitle(
          DateTime from, DateTime to, List<String> terms,
          {List<String>? channelIds}) async =>
      pending == null ? [] : await pending!.future;
  final now = DateTime.now();
  @override
  List<EpgProgram> getPrograms(String channelId) => [
        for (var i = -1; i < 5; i++)
          EpgProgram(
              channelId: channelId,
              title: [
                'Morning News',
                'The World Today',
                'Live Sport',
                'Evening Report',
                'Coast to Coast',
                'Night News'
              ][i + 1],
              description:
                  'News, stories and live coverage from across Australia and around the world.',
              start: DateTime(now.year, now.month, now.day, now.hour)
                  .add(Duration(hours: i)),
              stop: DateTime(now.year, now.month, now.day, now.hour)
                  .add(Duration(hours: i + 1))),
      ];
  @override
  EpgProgram? getCurrentProgram(String channelId) => withoutGuide
          .contains(channelId)
      ? null
      : replays
              .where((p) =>
                  normalizeEpgId(p.channelId) == normalizeEpgId(channelId) &&
                  p.isNowPlaying(DateTime.now()))
              .firstOrNull ??
          getPrograms(channelId)[1];
  @override
  EpgProgram? getNextProgram(String channelId) => getPrograms(channelId)[2];
}

// Isolate replies use real time; pumpAndSettle alone advances only fake time.
// Matching/layout fixtures explicitly exercise favorite feeds. Scope tests below
// start with no Events selection to verify the unfiltered production default.
void setLayoutPreferences(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues({
    'sports_events_selection': <String>['', '', 'favorites'],
    ...values,
  });
}

Future<void> settleSports(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 16));
    if (!tester.binding.hasScheduledFrame) break;
  }
  await tester.pumpAndSettle();
}

Future<void> captureSports(WidgetTester tester, Size size, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_LAYOUT')) return;
  await tester.pump(const Duration(milliseconds: 200));
  await tester.runAsync(() async {
    final boundary = tester
        .firstRenderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary));
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/iptv-$name-${size.width.toInt()}.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

http.Response layoutTennisFixture() => http.Response(
    jsonEncode({
      'events': [
        {
          'id': 'tournament',
          'name': 'BNP Paribas Fortis European Open',
          'groupings': [
            {
              'grouping': {'displayName': "Men's Singles"},
              'competitions': [
                {
                  'id': 'tennis-demo',
                  'date': DateTime.now().toUtc().toIso8601String(),
                  'round': {'displayName': 'Round 2'},
                  'venue': {
                    'fullName': 'Brussels, Belgium',
                    'court': 'Court 2'
                  },
                  'status': {
                    'type': {'state': 'in', 'shortDetail': '2nd Set'}
                  },
                  'competitors': [
                    {
                      'athlete': {'id': '1', 'displayName': 'Yunchaokete Bu'},
                      'linescores': [
                        {'value': 6},
                        {'value': 3}
                      ]
                    },
                    {
                      'athlete': {'id': '2', 'displayName': 'Casper Ruud'},
                      'linescores': [
                        {'value': 4},
                        {'value': 2}
                      ]
                    },
                  ]
                }
              ]
            }
          ]
        }
      ]
    }),
    200);
