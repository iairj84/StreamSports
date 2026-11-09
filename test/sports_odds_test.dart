import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/services/sports_service.dart';
import 'package:nox_iptv/utils/sports_odds_presentation.dart';
import 'package:nox_iptv/widgets/sports_fixture_row.dart';
import 'package:nox_iptv/widgets/sports_hero_details.dart';

const _billsAtVikings = {
  'events': [
    {
      'id': '401',
      'date': '2026-11-09T18:00:00Z',
      'status': {
        'type': {'state': 'pre', 'shortDetail': '7:00 PM'}
      },
      'competitions': [
        {
          'id': '401',
          'date': '2026-11-09T18:00:00Z',
          'status': {
            'type': {'state': 'pre', 'shortDetail': '7:00 PM'}
          },
          'competitors': [
            {
              'id': '16',
              'homeAway': 'home',
              'team': {
                'id': '16',
                'abbreviation': 'MIN',
                'name': 'Vikings',
                'displayName': 'Minnesota Vikings',
                'shortDisplayName': 'Vikings',
              },
            },
            {
              'id': '2',
              'homeAway': 'away',
              'team': {
                'id': '2',
                'abbreviation': 'BUF',
                'name': 'Bills',
                'displayName': 'Buffalo Bills',
                'shortDisplayName': 'Bills',
              },
            },
          ],
          'odds': [
            {
              'provider': {'name': 'DraftKings'},
              'details': 'BUF -3.5',
              'overUnder': 45.5,
              'spread': 3.5,
              'awayTeamOdds': {'favorite': true, 'moneyLine': -175},
              'homeTeamOdds': {'favorite': false, 'moneyLine': 150},
            }
          ],
        }
      ],
    }
  ],
};

SportsGame _parse(Map<String, dynamic> board) => parseEspnScoreboard(
      (jsonEncode(board), sportsLeagueById('nfl')!),
    ).single;

Map<String, dynamic> _withOdds(Object? odds) {
  final board = jsonDecode(jsonEncode(_billsAtVikings)) as Map<String, dynamic>;
  final comp = ((board['events'] as List).first
      as Map<String, dynamic>)['competitions'] as List;
  (comp.first as Map<String, dynamic>)['odds'] = odds;
  return board;
}

void main() {
  test('a scoreboard line keeps the book, the spread and both moneylines', () {
    final game = _parse(_billsAtVikings);
    final odds = game.odds!;
    expect(odds.provider, 'DraftKings');
    expect(odds.details, 'BUF -3.5');
    expect(odds.overUnder, 45.5);
    expect(odds.homeMoneyLine, '+150');
    expect(odds.awayMoneyLine, '-175');
    expect(odds.drawMoneyLine, isNull);
    expect(sportsOddsLine(odds), 'BUF -3.5 · O/U 45.5');
    expect(sportsOddsMoneyLine(odds, game), 'MIN +150 · BUF -175');
  });

  test('a game without a published line carries none', () {
    final game = _parse(_withOdds(null));
    expect(game.odds, isNull);
    expect(sportsOddsLine(game.odds), isNull);
    expect(sportsOddsMoneyLine(game.odds, game), isNull);
  });

  test('the total stands alone when the book gives no handicap wording', () {
    final game = _parse(_withOdds([
      {
        'provider': {'name': 'DraftKings'},
        'overUnder': 2.5,
        'moneyline': {
          'home': {
            'close': {'odds': '-300'}
          },
          'away': {
            'close': {'odds': '+700'}
          },
          'draw': {
            'close': {'odds': '+450'}
          },
        },
      }
    ]));
    expect(sportsOddsLine(game.odds), 'O/U 2.5');
    expect(sportsOddsMoneyLine(game.odds, game),
        'MIN -300 · BUF +700 · Draw +450');
  });

  test('whole totals lose the decimal, half-point totals keep it', () {
    expect(sportsOddsNumber(45), '45');
    expect(sportsOddsNumber(45.5), '45.5');
  });

  test('the copy that carries online listings keeps the line', () {
    final game = _parse(_billsAtVikings);
    final copied = game.withOnlineBroadcasts(const []);
    expect(copied.odds?.details, 'BUF -3.5');
  });

  testWidgets('the focused game shows its line under the insight',
      (tester) async {
    final game = _parse(_billsAtVikings);
    await tester.pumpWidget(MaterialApp(
        home:
            Scaffold(body: SportsHeroDetails(game: game, hideScores: false))));
    expect(find.textContaining('BUF -3.5'), findsOneWidget);
    expect(find.textContaining('O/U 45.5'), findsOneWidget);
    expect(find.textContaining('DraftKings'), findsOneWidget);
  });

  testWidgets('the fixture row carries the line below the matchup',
      (tester) async {
    final game = _parse(_billsAtVikings);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SportsFixtureRow(
                game: game,
                time: '7:00 PM',
                hideScores: false,
                use24h: false))));
    expect(find.text('BUF -3.5 · O/U 45.5'), findsOneWidget);
  });

  testWidgets('the Sports options toggle takes the line off the rows',
      (tester) async {
    final game = _parse(_billsAtVikings);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SportsFixtureRow(
                game: game,
                time: '7:00 PM',
                hideScores: false,
                showOdds: false,
                use24h: false))));
    expect(find.textContaining('BUF -3.5'), findsNothing);
    expect(find.textContaining('O/U'), findsNothing);
  });

  test('the preference is on until the viewer turns it off', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    expect(storage.getSportsShowOdds(), isTrue);
    await storage.setSportsShowOdds(false);
    expect(storage.getSportsShowOdds(), isFalse);
  });
}
