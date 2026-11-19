import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/sports.dart';

/// ESPN's shared scoreboard API root.
const String espnApiBase = 'https://site.api.espn.com/apis/site/v2/sports';

/// `YYYYMMDD` for one local calendar day, the format ESPN's queries take.
String sportsEspnDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';

/// ESPN `groups` filter in force for [league]: an explicit conference id, or
/// the whole-division default the college scoreboards use.
String? espnGroupFor(SportsLeague league) =>
    league.espnGroup ??
    switch (league.espnPath) {
      'basketball/mens-college-basketball' => '50',
      'football/college-football' => '80',
      _ => null,
    };

/// Extra query arguments one league's scoreboard request needs.
String espnScoreboardOptions(SportsLeague league) {
  final group = espnGroupFor(league);
  if (group != null) return '&groups=$group&limit=300';
  return league.id == 'rugby.live' ? '&limit=100' : '';
}

/// The catalogue's one parser signature, for an entry point that takes a
/// record so [compute] can send a single argument.
List<SportsGame> parseEspnScoreboardBody(String body, SportsLeague league) =>
    parseEspnScoreboard((body, league));

/// Top-level so [compute] can run it on a background isolate.
@visibleForTesting
List<SportsGame> parseEspnScoreboard((String, SportsLeague) args) {
  final (body, league) = args;
  final json = jsonDecode(body);
  if (json is! Map<String, dynamic>) {
    throw const FormatException('Expected scoreboard object');
  }
  final events = json['events'];
  if (events is! List) {
    throw const FormatException('Expected scoreboard events');
  }
  final games = <SportsGame>[];
  for (final e in events) {
    try {
      final m = e as Map<String, dynamic>;
      switch (league.kind) {
        case SportsKind.broadcast:
          break;
        case SportsKind.team:
          final game = _parseEvent(
              m, league.id == 'rugby.live' ? _rugbyEventLeague(m) : league);
          if (game != null) games.add(game);
        case SportsKind.golf:
          final game = _parseGolf(m, league);
          if (game != null) games.add(game);
        case SportsKind.racing:
          games.addAll(_parseRacing(m, league));
        case SportsKind.fight:
          final game = _parseFightCard(m, league);
          if (game != null) games.add(game);
        case SportsKind.tennis:
          games.addAll(_parseTennis(m, league));
      }
    } catch (_) {
      // One malformed event shouldn't drop the whole league.
    }
  }
  // A poll view is the same scoreboard, narrowed to games with a ranked
  // side; ESPN reports poll positions on both competitors.
  if (league.rankedOnly) {
    return [
      for (final game in games)
        if (game.home.rank != null || game.away.rank != null) game
    ];
  }
  return games;
}

// ESPN's all-rugby feed supplies the competition slug in event links. Keep
// stable league IDs so picks and ordinary per-league fixtures refer to one event.
final _rugbyLeagueLink = RegExp(r'/league/(\d+)');
SportsLeague _rugbyEventLeague(Map<String, dynamic> event) {
  for (final link in event['links'] as List? ?? const []) {
    if (link is! Map) continue;
    final id = _rugbyLeagueLink.firstMatch(link['href']?.toString() ?? '')?[1];
    if (id == null) continue;
    return sportsLeagueById('rugby.$id') ??
        SportsLeague(
            id: 'rugby.$id',
            espnPath: 'rugby/$id',
            name: 'International & club rugby',
            shortName: 'Rugby',
            logoUrl: '',
            hasStandings: false);
  }
  return kLiveRugbyLeague;
}

// ------------------------------------------------------------ event sports

// These statuses interrupt an ongoing contest; a provider's broad "post"
// state must not turn an unfinished match into a final result.
const _interruptedStatuses = {
  'STATUS_SUSPENDED': 'Suspended',
  'STATUS_INTERRUPTED': 'Interrupted',
  'STATUS_MEDICAL_TIMEOUT': 'Medical timeout',
  'STATUS_TIMEOUT': 'Timeout',
  'STATUS_RAIN_DELAY': 'Rain delay',
};

GameState _stateOf(Map<String, dynamic>? status) {
  final type = status?['type'] as Map?;
  if (type?['completed'] == true) return GameState.post;
  if (_interruptedStatuses.containsKey(type?['name'])) return GameState.live;
  return switch (type?['state']) {
    'in' => GameState.live,
    'post' => GameState.post,
    _ => GameState.pre,
  };
}

String _statusTextOf(Map<String, dynamic>? status) {
  final type = status?['type'] as Map?;
  // Interrupted feeds can omit shortDetail or leave it blank. Keep the reason
  // visible on the card rather than showing an empty live-status label.
  for (final key in ['shortDetail', 'detail', 'description']) {
    final text = type?[key]?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return _interruptedStatuses[type?['name']] ?? '';
}

List<String> _broadcastsOf(Iterable<Map<String, dynamic>> comps) =>
    _broadcastDetailsOf(comps).map((b) => b.name).toSet().toList();

List<SportsBroadcast> _broadcastDetailsOf(
    Iterable<Map<String, dynamic>> comps) {
  final out = <String, SportsBroadcast>{};
  String label(Object? value) => value is Map
      ? (value['shortName'] ??
              value['name'] ??
              value['displayName'] ??
              value['type'] ??
              '')
          .toString()
      : value is String
          ? value
          : '';
  for (final comp in comps) {
    for (final key in ['broadcasts', 'geoBroadcasts']) {
      final rows = comp[key];
      if (rows is! List) continue;
      for (final row in rows.whereType<Map>()) {
        final names = <String>{
          if (row['names'] is List)
            ...(row['names'] as List).whereType<String>(),
          label(row['media'])
        };
        for (final raw in names) {
          final name = raw.trim();
          if (name.isEmpty) continue;
          final listing = SportsBroadcast(name,
              source: 'ESPN',
              country: SportsBroadcast.countryName('${row['region'] ?? ''}'),
              medium: label(row['type']),
              market: label(row['market']),
              language: '${row['lang'] ?? ''}');
          out[listing.evidenceKey] = listing;
        }
      }
    }
  }
  // Geo metadata overrides a duplicate unqualified network from broadcasts.
  final qualified = out.values
      .where((b) => b.country.isNotEmpty || b.medium.isNotEmpty)
      .map((b) => b.name.toLowerCase())
      .toSet();
  return out.values
      .where((b) =>
          b.country.isNotEmpty ||
          b.medium.isNotEmpty ||
          !qualified.contains(b.name.toLowerCase()))
      .toList();
}

String? _venueOf(Map<String, dynamic> e, Map<String, dynamic>? comp) {
  Object? v = e['circuit'] ?? comp?['venue'] ?? e['venues'];
  if (v is List) v = v.isEmpty ? null : v.first;
  if (v is! Map) return null;
  final name = v['fullName']?.toString();
  final city = (v['address'] as Map?)?['city']?.toString();
  if (name == null || name.isEmpty) return city;
  return city == null || city.isEmpty || name.contains(city)
      ? name
      : '$name, $city';
}

List<Map<String, dynamic>> _competitorsByOrder(Map<String, dynamic> comp) {
  final list = [
    for (final c in (comp['competitors'] as List?) ?? const [])
      (c as Map).cast<String, dynamic>()
  ];
  int order(Map<String, dynamic> c) => (c['order'] as num?)?.toInt() ?? 1 << 20;
  list.sort((a, b) => order(a).compareTo(order(b)));
  return list;
}

String? _flagOf(Map<String, dynamic> c) =>
    ((c['athlete'] as Map?)?['flag'] as Map?)?['href']?.toString();

String _athleteName(Map<String, dynamic> c, {bool short = false}) {
  final a = (c['athlete'] as Map?) ?? const {};
  return ((short ? a['shortName'] : null) ??
          a['displayName'] ??
          a['fullName'] ??
          '')
      .toString();
}

/// Golf and racing have no sides; the cards read the event instead, but the
/// rest of the tab (glow, picks, search) still expects two teams.
SportsTeam _placeholderSide(SportsLeague league, String title) => SportsTeam(
      id: '',
      name: title,
      shortName: title,
      abbreviation: league.shortName,
      logoUrl: league.logoUrl,
    );

SportsGame? _parseGolf(Map<String, dynamic> e, SportsLeague league) {
  final comp = ((e['competitions'] as List?)?.firstOrNull as Map?)
      ?.cast<String, dynamic>();
  if (comp == null) return null;
  final status = (comp['status'] ?? e['status']) as Map<String, dynamic>?;
  final state = _stateOf(status);
  final title = (e['name'] ?? '').toString();
  final players = _competitorsByOrder(comp);
  // Ties share a place ("T3"), the way every leaderboard shows them.
  final leaders = <SportsEventEntry>[];
  if (state != GameState.pre) {
    for (var i = 0; i < players.length && leaders.length < 5; i++) {
      final score = players[i]['score']?.toString();
      var first = i;
      while (first > 0 && players[first - 1]['score']?.toString() == score) {
        first--;
      }
      final tied = (i + 1 < players.length &&
              players[i + 1]['score']?.toString() == score) ||
          first != i;
      leaders.add(SportsEventEntry(
        position: '${tied ? 'T' : ''}${first + 1}',
        name: _athleteName(players[i], short: true),
        flagUrl: _flagOf(players[i]),
        value: score,
      ));
    }
  }
  final round = (status?['period'] as num?)?.toInt();
  final side = _placeholderSide(league, title);
  final endRaw = e['endDate']?.toString();
  return SportsGame(
    id: e['id'].toString(),
    league: league,
    start: DateTime.parse((e['date'] ?? comp['date']).toString()).toUtc(),
    end: endRaw == null ? null : DateTime.tryParse(endRaw)?.toUtc(),
    state: state,
    statusText: _statusTextOf(status),
    home: side,
    away: side,
    broadcasts: _broadcastsOf([comp]),
    scoreboardBroadcasts: _broadcastDetailsOf([comp]),
    event: SportsEventInfo(
      title: title,
      participantIds: [
        for (final player in players)
          if (player['athlete'] case {'id': final Object id}) id.toString()
      ],
      playActive: !const {
        'STATUS_PLAY_COMPLETE',
        'STATUS_SUSPENDED',
        'STATUS_DELAYED',
        'STATUS_POSTPONED',
      }.contains((status?['type'] as Map?)?['name']),
      session: state != GameState.pre && round != null && round > 0
          ? 'Round $round'
          : null,
      venue: _venueOf(e, comp),
      leaders: leaders,
    ),
  );
}

/// ESPN's session abbreviations. F1 practices are watchable sessions too.
const Map<String, String?> _racingSessions = {
  'FP1': null,
  'FP2': null,
  'FP3': null,
  'SS': 'Sprint Qualifying',
  'SR': 'Sprint',
  'Qual': 'Qualifying',
  'Race': 'Race',
};

List<SportsGame> _parseRacing(Map<String, dynamic> e, SportsLeague league) {
  final title = (e['name'] ?? '').toString();
  final side = _placeholderSide(league, title);
  final out = <SportsGame>[];
  for (final raw in (e['competitions'] as List?) ?? const []) {
    final comp = (raw as Map).cast<String, dynamic>();
    final abbr = (comp['type'] as Map?)?['abbreviation']?.toString();
    // NASCAR/IndyCar events are one untyped competition: the race.
    final session = abbr == null
        ? 'Race'
        : (_racingSessions.containsKey(abbr) ? _racingSessions[abbr] : abbr);
    final shownSession = session ??
        (league.id == 'racing.f1' && const {'FP1', 'FP2', 'FP3'}.contains(abbr)
            ? 'Practice ${abbr!.substring(2)}'
            : null);
    if (shownSession == null) continue;
    final status = (comp['status'] ?? e['status']) as Map<String, dynamic>?;
    final state = _stateOf(status);
    final drivers = _competitorsByOrder(comp);
    out.add(SportsGame(
      id: (comp['id'] ?? e['id']).toString(),
      league: league,
      start: DateTime.parse((comp['date'] ?? e['date']).toString()).toUtc(),
      state: state,
      statusText: _statusTextOf(status),
      home: side,
      away: side,
      broadcasts: _broadcastsOf([comp]),
      scoreboardBroadcasts: _broadcastDetailsOf([comp]),
      event: SportsEventInfo(
        title: title,
        participantIds: [
          for (final driver in drivers)
            if (driver['athlete'] case {'id': final Object id}) id.toString()
        ],
        participantNames: {
          for (final driver in drivers)
            if (driver['athlete'] case {'id': final Object id})
              id.toString(): _athleteName(driver)
        },
        session: shownSession,
        venue: _venueOf(e, comp),
        // Before the start the order is just the entry list.
        leaders: state == GameState.pre
            ? const []
            : [
                for (var i = 0; i < drivers.length && i < 5; i++)
                  SportsEventEntry(
                    position: '${i + 1}',
                    name: _athleteName(drivers[i], short: true),
                    flagUrl: _flagOf(drivers[i]),
                  ),
              ],
      ),
    ));
  }
  return out;
}

/// A tennis tournament is one ESPN event with `groupings` (Men's Singles,
/// Women's Doubles…), each listing every match of the tournament. Each
/// main-draw singles match becomes a card ([gamesForDay] keeps the day's):
/// doubles (no athlete per side) and qualifying rounds are left out — a
/// tournament day would otherwise be 50+ cards. Score = sets won.
List<SportsGame> _parseTennis(Map<String, dynamic> e, SportsLeague league) {
  final tournament = (e['name'] ?? '').toString();
  final out = <SportsGame>[];
  for (final g in (e['groupings'] as List?) ?? const []) {
    final grouping =
        ((g as Map)['grouping'] as Map?)?['displayName']?.toString() ?? '';
    if (!grouping.toLowerCase().contains('singles')) continue;
    for (final c in (g['competitions'] as List?) ?? const []) {
      final comp = (c as Map).cast<String, dynamic>();
      final round = ((comp['round'] as Map?)?['displayName'] ?? '').toString();
      if (round.toLowerCase().contains('qualif')) continue;
      final players = _competitorsByOrder(comp);
      if (players.length != 2 || players.any((p) => p['athlete'] is! Map)) {
        continue;
      }
      final date = DateTime.tryParse((comp['date'] ?? '').toString());
      if (date == null) continue;
      final status = comp['status'] as Map<String, dynamic>?;
      final state = _stateOf(status);
      List<num> sets(Map<String, dynamic> p) => [
            for (final l in (p['linescores'] as List?) ?? const [])
              ((l as Map)['value'] as num?) ?? 0,
          ];
      final a = sets(players[0]), b = sets(players[1]);
      int won(List<num> mine, List<num> theirs) {
        var n = 0;
        for (var i = 0; i < mine.length && i < theirs.length; i++) {
          // A set still being played counts once it's over (6+ games, 2 up,
          // or 7 after a tie-break) — otherwise only finished matches.
          final done = state == GameState.post || i < mine.length - 1;
          if (done && mine[i] > theirs[i]) n++;
        }
        return n;
      }

      SportsTeam player(Map<String, dynamic> p, int setsWon) {
        final full = _athleteName(p);
        return SportsTeam(
          id: ((p['athlete'] as Map?)?['id'] ?? p['id'] ?? full).toString(),
          name: full,
          shortName: full,
          abbreviation: full
              .split(' ')
              .where((w) => w.isNotEmpty)
              .map((w) => w[0])
              .take(2)
              .join()
              .toUpperCase(),
          logoUrl: _flagOf(p),
          score: state == GameState.pre ? null : '$setsWon',
        );
      }

      out.add(SportsGame(
        id: comp['id'].toString(),
        league: league,
        start: date.toUtc(),
        state: state,
        statusText: _statusTextOf(status),
        home: player(players[0], won(a, b)),
        away: player(players[1], won(b, a)),
        broadcasts: _broadcastsOf([e, comp]),
        scoreboardBroadcasts: _broadcastDetailsOf([e, comp]),
        event: SportsEventInfo(
          title: tournament,
          matchingNames: {
            for (final key in ['shortName', 'shortDisplayName'])
              if (e[key] is String && (e[key] as String).trim().isNotEmpty)
                (e[key] as String).trim(),
            if (comp['venue'] is Map &&
                (comp['venue']['fullName'] ?? '').toString().contains(','))
              comp['venue']['fullName'].toString().split(',').first.trim(),
            // City names often replace the sponsor title in TV listings.
            for (final v in [
              comp['venue'],
              if (e['venues'] is List) ...(e['venues'] as List),
            ])
              if (v is Map && v['address'] is Map)
                if ((v['address']['city'] ?? '').toString().trim().length >= 4)
                  v['address']['city'].toString().trim(),
          }.toList(),
          session: round.isEmpty ? grouping : round,
          court: (comp['venue'] as Map?)?['court']?.toString(),
          venue: _venueOf(e, comp),
        ),
      ));
    }
  }
  return out;
}

/// A fight card is one ESPN event with a competition per fight. The card
/// shows the main event: the fight whose two names are in the event's name
/// ("UFC Fight Night: Allen vs. Duncan"), else the last one listed.
SportsGame? _parseFightCard(Map<String, dynamic> e, SportsLeague league) {
  final comps = [
    for (final c in (e['competitions'] as List?) ?? const [])
      (c as Map).cast<String, dynamic>()
  ];
  if (comps.isEmpty) return null;
  final name = (e['name'] ?? '').toString();
  final lowerName = name.toLowerCase();
  bool billed(Map<String, dynamic> comp) {
    final fighters = (comp['competitors'] as List?) ?? const [];
    return fighters.length == 2 &&
        fighters.every((f) {
          final full = _athleteName((f as Map).cast<String, dynamic>());
          final parts = full.toLowerCase().split(' ');
          return parts.isNotEmpty && lowerName.contains(parts.last);
        });
  }

  final main = comps.where(billed).lastOrNull ?? comps.last;
  final fighters = _competitorsByOrder(main);
  if (fighters.length != 2) return null;
  final status = (e['status'] ?? main['status']) as Map<String, dynamic>?;
  final liveBout = comps
      .where((c) =>
          _stateOf(c['status'] as Map<String, dynamic>?) == GameState.live)
      .firstOrNull;
  // The headline fight can still be scheduled while the undercard is live.
  // Use an actual live bout, never the wall clock, to repair a pending card.
  final effectiveStatus = _stateOf(status) == GameState.pre && liveBout != null
      ? liveBout['status'] as Map<String, dynamic>?
      : status;
  final mainState = _stateOf(main['status'] as Map<String, dynamic>?);
  SportsTeam fighter(Map<String, dynamic> c) {
    final full = _athleteName(c);
    final records = c['records'] as List?;
    return SportsTeam(
      id: ((c['athlete'] as Map?)?['id'] ?? c['id'] ?? full).toString(),
      name: full,
      shortName: full,
      abbreviation: full
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => w[0])
          .take(2)
          .join()
          .toUpperCase(),
      logoUrl: _flagOf(c),
      record: (records != null && records.isNotEmpty)
          ? (records.first as Map)['summary']?.toString()
          : null,
      // W / L once the main event is decided (no score in MMA). A draw or
      // no contest has no winner, so no letters.
      score: mainState == GameState.post &&
              fighters.any((f) => f['winner'] == true)
          ? (c['winner'] == true ? 'W' : 'L')
          : null,
    );
  }

  DateTime start =
      DateTime.parse((comps.first['date'] ?? e['date']).toString());
  for (final c in comps) {
    final d = DateTime.tryParse((c['date'] ?? '').toString());
    if (d != null && d.isBefore(start)) start = d;
  }
  final type = main['type'] as Map?;
  final weightClass = (type?['text'] ?? type?['abbreviation'])?.toString();
  return SportsGame(
    id: e['id'].toString(),
    league: league,
    start: start.toUtc(),
    state: _stateOf(effectiveStatus),
    statusText: _statusTextOf(effectiveStatus),
    home: fighter(fighters[0]),
    away: fighter(fighters[1]),
    broadcasts: _broadcastsOf([e, ...comps]),
    scoreboardBroadcasts: _broadcastDetailsOf([e, ...comps]),
    event: SportsEventInfo(
      title: name,
      participantIds: [
        for (final competition in comps)
          for (final fighter
              in (competition['competitors'] as List?) ?? const [])
            if (fighter case {'athlete': {'id': final Object id}}) id.toString()
      ],
      session: weightClass,
      venue: _venueOf(e, null),
    ),
  );
}

SportsGame? _parseEvent(Map<String, dynamic> e, SportsLeague league) {
  final competitions = e['competitions'] as List?;
  if (competitions == null || competitions.isEmpty) return null;
  final comp = competitions.first as Map<String, dynamic>;
  final competitors = (comp['competitors'] as List?) ?? const [];
  SportsTeam? home;
  SportsTeam? away;
  for (final c in competitors) {
    final m = c as Map<String, dynamic>;
    final team = _parseTeam(m);
    if (m['homeAway'] == 'home') {
      home = team;
    } else {
      away = team;
    }
  }
  if (home == null || away == null) return null;

  final status = (comp['status'] ?? e['status']) as Map<String, dynamic>?;
  final state = _stateOf(status);

  final broadcasts = _broadcastsOf([e, comp]);

  return SportsGame(
    id: e['id'].toString(),
    league: league,
    start: DateTime.parse((comp['date'] ?? e['date']).toString()).toUtc(),
    state: state,
    statusText: _statusTextOf(status),
    home: home,
    away: away,
    broadcasts: broadcasts.toList(),
    scoreboardBroadcasts: _broadcastDetailsOf([e, comp]),
    leaders: _scoreboardLeaders(comp, competitors),
    situation: state == GameState.live
        ? _situationOf(comp['situation'], league)
        : null,
    odds: _oddsOf(comp['odds']),
  );
}

/// The book's line for this game. ESPN keeps the current prices on the
/// scoreboard, so no second request is needed; a game without a published
/// line simply carries none.
SportsOdds? _oddsOf(Object? raw) {
  if (raw is! List) return null;
  for (final entry in raw) {
    if (entry is! Map) continue;
    final details = entry['details']?.toString().trim() ?? '';
    final overUnder = (entry['overUnder'] as num?)?.toDouble();
    final moneyline = entry['moneyline'] as Map?;
    String? close(String side) {
      final row = moneyline?[side] as Map?;
      return _moneyLine((row?['close'] as Map?)?['odds'] ??
          (row?['current'] as Map?)?['odds']);
    }

    final home = close('home') ??
        _moneyLine((entry['homeTeamOdds'] as Map?)?['moneyLine']);
    final away = close('away') ??
        _moneyLine((entry['awayTeamOdds'] as Map?)?['moneyLine']);
    final draw = close('draw') ??
        _moneyLine((entry['drawOdds'] as Map?)?['moneyLine']);
    if (details.isEmpty && overUnder == null && home == null && away == null) {
      continue;
    }
    return SportsOdds(
      provider: ((entry['provider'] as Map?)?['name'] ?? '').toString(),
      details: details,
      overUnder: overUnder,
      homeMoneyLine: home,
      awayMoneyLine: away,
      drawMoneyLine: draw,
    );
  }
  return null;
}

/// "+150" for 150 and "-110" for -110; already-signed strings pass through.
String? _moneyLine(Object? value) {
  if (value == null) return null;
  if (value is num) return value > 0 ? '+${value.round()}' : '${value.round()}';
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final number = num.tryParse(text);
  return number == null ? text : _moneyLine(number);
}

/// ESPN's "rating" leader repeats another line ("29 PTS").
const _skippedLeaderStats = {'RAT', 'MLB'};

SportsLeader? _leaderOf(Map category, {String? teamId}) {
  final first = (category['leaders'] as List?)?.firstOrNull as Map?;
  final athlete = first?['athlete'] as Map?;
  if (first == null || athlete == null) return null;
  final name = (athlete['shortName'] ?? athlete['displayName'])?.toString();
  final value = first['displayValue']?.toString();
  if (name == null || value == null || value.isEmpty) return null;
  return SportsLeader(
    stat: (category['shortDisplayName'] ??
            category['abbreviation'] ??
            category['displayName'] ??
            '')
        .toString(),
    name: name,
    value: value,
    teamId: ((first['team'] as Map?)?['id'] ??
            (athlete['team'] as Map?)?['id'] ??
            teamId)
        ?.toString(),
    position: (athlete['position'] as Map?)?['abbreviation']?.toString(),
  );
}

/// Football puts one leader per stat on the competition; hockey/basketball/
/// baseball give each team its own — merged here to the better of the two
/// per stat, in ESPN's order.
List<SportsLeader> _scoreboardLeaders(
    Map<String, dynamic> comp, List competitors) {
  final out = <SportsLeader>[];
  for (final c in (comp['leaders'] as List?) ?? const []) {
    final l = _leaderOf(c as Map);
    if (l != null && !_skippedLeaderStats.contains(l.stat)) out.add(l);
  }
  if (out.isNotEmpty) return out;
  final byStat = <String, (SportsLeader, double)>{};
  final order = <String>[];
  for (final t in competitors) {
    final teamId = (((t as Map)['team'] as Map?)?['id'] ?? t['id'])?.toString();
    for (final c in (t['leaders'] as List?) ?? const []) {
      final l = _leaderOf(c as Map, teamId: teamId);
      if (l == null || _skippedLeaderStats.contains(l.stat)) continue;
      final v =
          ((c['leaders'] as List).first['value'] as num?)?.toDouble() ?? 0;
      final had = byStat[l.stat];
      if (had == null) order.add(l.stat);
      if (had == null || v > had.$2) byStat[l.stat] = (l, v);
    }
  }
  return [for (final s in order) byStat[s]!.$1];
}

String? _nonEmptyText(Object? value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// The composed down-and-distance line from a numeric down and distance,
/// for live states where ESPN has not composed the text yet (early in a
/// game the block carries down/distance but no text; down 0 is a kickoff
/// with no down to show). Returns null outside downs 1-4.
String? _syntheticDownDistance(Map raw) {
  int? number(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
  final down = number(raw['down']);
  final distance = number(raw['distance']);
  if (down == null || distance == null || down < 1 || down > 4) return null;
  const ordinals = ['1st', '2nd', '3rd', '4th'];
  return '${ordinals[down - 1]} & $distance';
}

SportsSituation? _situationOf(Object? raw, SportsLeague league) {
  if (raw is! Map) return null;
  final lastPlay = (raw['lastPlay'] as Map?)?['text']?.toString();
  String? text = _nonEmptyText(raw['downDistanceText']) ??
      _nonEmptyText(raw['shortDownDistanceText']) ??
      _syntheticDownDistance(raw);
  if (text == null && raw['outs'] != null) {
    // Baseball: "1-2, 2 out · 1st, 3rd".
    bool on(String k) => raw[k] == true || raw[k] is Map;
    final bases = [
      if (on('onFirst')) '1st',
      if (on('onSecond')) '2nd',
      if (on('onThird')) '3rd',
    ];
    text = [
      if (raw['balls'] != null && raw['strikes'] != null)
        '${raw['balls']}-${raw['strikes']}',
      '${raw['outs']} out',
      if (bases.isNotEmpty) bases.join(', '),
    ].join(' · ');
  }
  final possession = raw['possession']?.toString();
  if (text == null && possession == null && lastPlay == null) return null;
  return SportsSituation(
    text: text,
    possessionTeamId: possession,
    redZone: raw['isRedZone'] == true,
    lastPlay: lastPlay,
  );
}

SportsTeam _parseTeam(Map<String, dynamic> c) {
  final t = (c['team'] as Map?)?.cast<String, dynamic>() ?? const {};
  String? record;
  final records = c['records'] as List?;
  if (records != null && records.isNotEmpty) {
    record = (records.first as Map)['summary']?.toString();
  }
  // Team schedules: `record: [{displayValue: "2-1-0, 4 PTS"}]`.
  final schedRecord = c['record'];
  if (record == null && schedRecord is List && schedRecord.isNotEmpty) {
    record = (schedRecord.first as Map)['displayValue']
        ?.toString()
        .split(',')
        .first
        .trim();
  }
  // Scoreboard: "3"; team schedules: {value: 3.0, displayValue: "3"}.
  final rawScore = c['score'];
  final score = rawScore is Map
      ? rawScore['displayValue']?.toString()
      : rawScore?.toString();
  String? logo = t['logo']?.toString();
  final logos = t['logos'];
  if (logo == null && logos is List && logos.isNotEmpty) {
    logo = (logos.first as Map)['href']?.toString();
  }
  final name = (t['displayName'] ?? t['name'] ?? '').toString();
  // College scoreboards carry the poll position here; 99 means unranked.
  final curated = (c['curatedRank'] as Map?)?['current'];
  final rank = curated is num && curated > 0 && curated < 99
      ? curated.toInt()
      : null;
  return SportsTeam(
    id: (t['id'] ?? name).toString(),
    name: name,
    shortName: (t['shortDisplayName'] ?? t['name'] ?? name).toString(),
    abbreviation: (t['abbreviation'] ?? '').toString(),
    location: t['location']?.toString(),
    logoUrl: logo,
    color: t['color']?.toString(),
    record: record,
    score: score,
    rank: rank,
  );
}
