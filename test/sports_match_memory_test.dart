import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/epg_program.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/services/sports_match_disk_cache.dart';
import 'package:nox_iptv/services/sports_match_inputs.dart';
import 'package:nox_iptv/utils/stable_hash.dart';

void main() {
  final now = DateTime.utc(2026, 11, 18, 18, 0);
  SportsGame fixture(GameState state, Duration fromNow,
          {List<EpgProgram> programmes = const []}) =>
      SportsGame(
          id: '401',
          league: sportsLeagueById('nba')!,
          start: now.add(fromNow),
          end: now.add(fromNow + const Duration(hours: 2)),
          state: state,
          statusText: 'Scheduled',
          source: 'ESPN',
          guideProgrammes: programmes,
          home: const SportsTeam(
              id: 'bos',
              name: 'Boston Celtics',
              shortName: 'Celtics',
              abbreviation: 'BOS'),
          away: const SportsTeam(
              id: 'lal',
              name: 'Los Angeles Lakers',
              shortName: 'Lakers',
              abbreviation: 'LAL'));
  EpgProgram programme(Duration start, Duration stop) => EpgProgram(
      channelId: '101',
      title: 'NBA: Lakers @ Celtics',
      start: now.add(start),
      stop: now.add(stop));

  group('StableHash', () {
    // Golden values: Object.hash would produce different numbers in each test
    // process, so a fixed expectation is what proves a disk key can match
    // after a restart.
    test('fingerprints the same fields to the same value every run', () {
      expect(StableHash.of(['p::1', '1', 'NHL: BOS vs TOR', '', 'Sports', '1']),
          694186687);
      expect(StableHash.of(['a', 'bc']), 2717841835);
      expect(StableHash.of(['ab', 'c']), 888409153);
    });

    test('separates fields, so shifted text is a different fingerprint', () {
      expect(StableHash.of(['ab', 'c']), isNot(StableHash.of(['a', 'bc'])));
      expect(StableHash.of(['same']), StableHash.of(['same']));
    });
  });

  group('sportsMatchMemoryUntil', () {
    test('rechecks a live game as often as the board does', () {
      expect(sportsMatchMemoryUntil(fixture(GameState.live, -const Duration(minutes: 5)), now),
          now.add(const Duration(minutes: 5)));
    });

    test('keeps an imminent game short, since evidence moves at kick-off', () {
      expect(
          sportsMatchMemoryUntil(
              fixture(GameState.pre, const Duration(minutes: 20)), now),
          now.add(const Duration(minutes: 5)));
    });

    test('remembers a later game for half an hour', () {
      expect(
          sportsMatchMemoryUntil(
              fixture(GameState.pre, const Duration(hours: 3)), now),
          now.add(const Duration(minutes: 30)));
    });

    test('never outlives a known transition', () {
      final game = fixture(GameState.pre, const Duration(hours: 3),
          programmes: [programme(const Duration(minutes: 10), const Duration(hours: 3))]);
      expect(sportsMatchMemoryUntil(game, now),
          now.add(const Duration(minutes: 10)));
    });

    test('keeps a finished game for six hours', () {
      expect(
          sportsMatchMemoryUntil(
              fixture(GameState.post, -const Duration(hours: 3)), now),
          now.add(const Duration(hours: 6)));
    });
  });

  group('SportsMatchDiskCache memory', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sports-memory-');
    });
    tearDown(() => dir.delete(recursive: true));

    test('a match survives longer than five minutes and until its own expiry',
        () async {
      final file = File('${dir.path}/matches.json');
      final cache = SportsMatchDiskCache(file);
      cache.put('key', [], now, now.add(const Duration(minutes: 30)));
      await cache.flush();
      final restored = SportsMatchDiskCache(file);
      await restored.load(now);
      expect(restored.read('key', now.add(const Duration(minutes: 25))),
          isNotNull);
      expect(restored.read('key', now.add(const Duration(minutes: 31))), isNull);
    });

    test('nothing outlives the ceiling, whatever its expiry says', () async {
      final file = File('${dir.path}/matches.json');
      final cache = SportsMatchDiskCache(file);
      cache.put('key', [], now, now.add(const Duration(hours: 12)));
      await cache.flush();
      final restored = SportsMatchDiskCache(file);
      await restored.load(now);
      expect(
          restored.read('key', now.add(const Duration(hours: 5))), isNotNull);
      expect(
          restored.read('key', now.add(const Duration(hours: 7))), isNull);
    });
  });
}
