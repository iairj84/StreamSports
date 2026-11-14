import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/services/sports_service.dart';
import 'package:nox_iptv/utils/sports_fixture_presentation.dart';

/// End to end through the real parser: a genuine ESPN scoreboard event
/// (Miami vs Duke, 14 Nov 2026) flipped to a live 4th quarter with a
/// situation block mirroring a real live-game sample from the same day.
/// If possession or down & distance ever stops reaching the cards, this
/// is the test that names the layer that dropped it.
void main() {
  test('live parser keeps possession and down and distance', () async {
    final body = await File(
            'test/fixtures/cfb_live_situation_2026_11_14.json')
        .readAsString();
    final now = DateTime.utc(2026, 11, 14, 17, 30);
    final service =
        SportsService.withClient(MockClient((request) async => http.Response(
              body,
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )), clock: () => now);
    final games = await service.gamesForDay(
        [sportsLeagueById('college-football')!], now.toLocal());
    expect(games, hasLength(1));
    final game = games.single;
    expect(game.isLive, isTrue);
    expect(game.situation, isNotNull);
    expect(game.situation!.text, '2nd & 9 at DUKE 26');
    expect(game.situation!.possessionTeamId, game.home.id);
    expect(game.home.id, isNotEmpty);
    expect(game.situation!.possessionTeamId, isNot(equals(game.away.id)));
    // The cards' shared line carries the spot next to the clock.
    expect(sportsLiveProgress(game), contains('2nd & 9 at DUKE 26'));
  });
}
