import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/services/buffering_failover.dart';
import 'package:nox_iptv/services/playback_health.dart';
import 'package:nox_iptv/services/storage_service.dart';

Channel _channel(String rawId, String name, {String playlistId = 'fixture'}) =>
    Channel(
        id: '$playlistId::$rawId',
        rawId: rawId,
        playlistId: playlistId,
        name: name,
        group: 'Sports',
        url: 'https://example.invalid/never-opened');

void main() {
  final start = DateTime(2026, 11, 21, 20);

  /// One health update [atSeconds] into the watch.
  bool feed(BufferingFailoverWatcher watcher, StreamPhase phase, int seconds,
          int atSeconds) =>
      watcher.observe(
          phase: phase,
          seconds: seconds,
          now: start.add(Duration(seconds: atSeconds)));

  group('buffering counter', () {
    test('two real stalls inside ten minutes trip once', () {
      final watcher = BufferingFailoverWatcher()..watch('a');

      expect(feed(watcher, StreamPhase.playing, 0, 0), isFalse);
      // Under three seconds is a normal refill, not a stall.
      expect(feed(watcher, StreamPhase.buffering, 2, 2), isFalse);
      expect(feed(watcher, StreamPhase.playing, 0, 4), isFalse);
      expect(feed(watcher, StreamPhase.buffering, 3, 30), isFalse);
      expect(feed(watcher, StreamPhase.buffering, 4, 31), isFalse);
      expect(feed(watcher, StreamPhase.playing, 0, 40), isFalse);
      expect(feed(watcher, StreamPhase.buffering, 3, 300), isTrue);
      // The same stall continuing is not a third one.
      expect(feed(watcher, StreamPhase.buffering, 4, 301), isFalse);
    });

    test('stalls more than ten minutes apart do not add up', () {
      final watcher = BufferingFailoverWatcher()..watch('a');

      expect(feed(watcher, StreamPhase.buffering, 3, 10), isFalse);
      expect(feed(watcher, StreamPhase.playing, 0, 20), isFalse);
      // 601 s after the first stall: out of the window.
      expect(feed(watcher, StreamPhase.buffering, 3, 611), isFalse);
    });

    test('a shorter stall never counts', () {
      final watcher = BufferingFailoverWatcher()..watch('a');

      for (var i = 0; i < 4; i++) {
        expect(feed(watcher, StreamPhase.buffering, 1, i * 10), isFalse);
        expect(feed(watcher, StreamPhase.playing, 0, i * 10 + 1), isFalse);
      }
    });

    test('watching another channel starts the count over', () {
      final watcher = BufferingFailoverWatcher()..watch('a');
      expect(feed(watcher, StreamPhase.buffering, 3, 10), isFalse);

      watcher.watch('b');
      expect(feed(watcher, StreamPhase.buffering, 3, 20), isFalse);
    });

    test('reset clears what was counted', () {
      final watcher = BufferingFailoverWatcher()..watch('a');
      expect(feed(watcher, StreamPhase.buffering, 3, 10), isFalse);

      watcher.reset();
      expect(feed(watcher, StreamPhase.playing, 0, 20), isFalse);
      expect(feed(watcher, StreamPhase.buffering, 3, 30), isFalse);
    });
  });

  group('failover target', () {
    final channel = _channel('espn', 'ESPN');
    final backup = _channel('espn_star', 'ESPN *');

    test('returns the resolved backup', () {
      expect(autoFailoverTarget(channel, backup: backup), backup);
    });

    test('nothing to switch to leaves the channel alone', () {
      expect(autoFailoverTarget(channel, backup: null), isNull);
      expect(autoFailoverTarget(channel, backup: channel), isNull);
    });

    test('either side of the last switch is never switched again', () {
      expect(
          autoFailoverTarget(channel,
              backup: backup, lastFromId: channel.id, lastToId: backup.id),
          isNull);
      expect(
          autoFailoverTarget(backup,
              backup: channel, lastFromId: channel.id, lastToId: backup.id),
          isNull);
    });
  });

  test('automatic failover is off until the viewer turns it on', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();

    expect(storage.getAutoFailoverBuffering(), isFalse);
    await storage.setAutoFailoverBuffering(true);
    expect(storage.getAutoFailoverBuffering(), isTrue);
  });
}
