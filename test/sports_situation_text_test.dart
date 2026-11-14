import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/services/sports_service.dart';
import 'package:nox_iptv/utils/sports_fixture_presentation.dart';

/// The parser must not depend on ESPN composing the down-and-distance text:
/// live blocks regularly carry down/distance (or only the short text) with
/// no `downDistanceText` — e.g. the real Duke at Miami kickoff state on
/// 14 Nov 2026 (down 0, distance 11, possession Miami, no text keys).
Map<String, Object?> _event(String id, String name, Map<String, Object?> comp,
        String homeId, String home, String awayId, String away) =>
    {
      'id': id,
      'name': name,
      'date': '2026-11-14T17:05Z',
      'competitions': [
        {
          'id': id,
          'date': '2026-11-14T17:05Z',
          'status': {
            'type': {'state': 'in', 'shortDetail': '1st Quarter'}
          },
          'competitors': [
            {
              'homeAway': 'home',
              'score': '0',
              'team': {
                'id': homeId,
                'name': home,
                'displayName': home,
                'shortDisplayName': home.split(' ').last,
                'abbreviation': home.split(' ').last.substring(0, 3).toUpperCase(),
              },
            },
            {
              'homeAway': 'away',
              'score': '0',
              'team': {
                'id': awayId,
                'name': away,
                'displayName': away,
                'shortDisplayName': away.split(' ').last,
                'abbreviation': away.split(' ').last.substring(0, 3).toUpperCase(),
              },
            },
          ],
          ...comp,
        },
      ],
    };

Future<List<SportsGame>> _games(Map<String, Object?> body) async {
  final now = DateTime.utc(2026, 11, 14, 17, 30);
  final service =
      SportsService.withClient(MockClient((request) async => http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )), clock: () => now);
  return service.gamesForDay(
      [sportsLeagueById('college-football')!], now.toLocal());
}

void main() {
  test('kickoff state without text keys keeps possession, shows no down',
      () async {
    final games = await _games({
      'events': [
        _event(
            '401858296',
            'Duke Blue Devils at Miami Hurricanes',
            {
              'situation': {
                'down': 0,
                'distance': 11,
                'yardLine': 55,
                'isRedZone': false,
                'possession': 2390,
                'lastPlay': {'text': 'Timeout Duke, clock 08:32'},
              },
            },
            '2390',
            'Miami Hurricanes',
            '150',
            'Duke Blue Devils'),
      ],
    });
    expect(games, hasLength(1));
    final game = games.single;
    expect(game.isLive, isTrue);
    expect(game.situation, isNotNull);
    // Down 0 is a kickoff: no down to show, but the ball is still Miami's.
    expect(game.situation!.text, isNull);
    expect(game.situation!.possessionTeamId, game.home.id);
  });

  test('numeric down and distance synthesize the line when text is absent',
      () async {
    final games = await _games({
      'events': [
        _event(
            '401858301',
            'Wake Forest Demon Deacons at SMU Mustangs',
            {
              'situation': {
                'down': 2,
                'distance': 15,
                'yardLine': 67,
                'isRedZone': false,
                'possession': 154,
              },
            },
            '2567',
            'SMU Mustangs',
            '154',
            'Wake Forest Demon Deacons'),
      ],
    });
    expect(games, hasLength(1));
    final game = games.single;
    expect(game.situation?.text, '2nd & 15');
    expect(game.situation?.possessionTeamId, game.away.id);
    expect(sportsLiveProgress(game), contains('2nd & 15'));
  });

  test('short text is used when the full line is missing', () async {
    final games = await _games({
      'events': [
        _event(
            '401858522',
            'Northwestern Wildcats at Ohio State Buckeyes',
            {
              'situation': {
                'down': 3,
                'distance': 2,
                'yardLine': 28,
                'isRedZone': false,
                'possession': 77,
                'shortDownDistanceText': '3rd & 2',
              },
            },
            '194',
            'Ohio State Buckeyes',
            '77',
            'Northwestern Wildcats'),
      ],
    });
    expect(games, hasLength(1));
    expect(games.single.situation?.text, '3rd & 2');
  });
}
