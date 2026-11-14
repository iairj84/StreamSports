import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/models/epg_program.dart';
import 'package:nox_iptv/utils/catchup.dart';

Channel _channel({
  String url = 'https://example.invalid/live/1',
  String? mode,
  int? days,
  String? source,
}) =>
    Channel(
      id: 'test::ch',
      rawId: 'ch',
      playlistId: 'test',
      name: 'Channel',
      group: 'TV',
      url: url,
      catchupMode: mode,
      catchupDays: days,
      catchupSource: source,
    );

EpgProgram _program(DateTime start, DateTime stop) => EpgProgram(
      channelId: 'ch',
      title: 'Show',
      start: start,
      stop: stop,
    );

void main() {
  test('M3U default catch-up appends utc and lutc', () {
    final channel = _channel(mode: 'default', days: 3);
    final range = CatchupRange(DateTime(2026, 11, 14, 20, 0), 90);
    final url = catchupUrlFor(channel, range);
    final epoch = DateTime(2026, 11, 14, 20, 0).millisecondsSinceEpoch ~/ 1000;
    expect(url, 'https://example.invalid/live/1?utc=$epoch&lutc=90');
  });

  test('M3U catch-up keeps an existing query string', () {
    final channel = _channel(
        url: 'https://example.invalid/live/1?token=abc',
        mode: 'shift',
        days: 3);
    final range = CatchupRange(DateTime(2026, 11, 14, 20, 0), 60);
    final epoch = DateTime(2026, 11, 14, 20, 0).millisecondsSinceEpoch ~/ 1000;
    expect(catchupUrlFor(channel, range),
        'https://example.invalid/live/1?token=abc&utc=$epoch&lutc=60');
  });

  test('catchup-source template wins over utc/lutc params', () {
    final channel = _channel(
        mode: 'default',
        source: 'https://example.invalid/timeshift?start=\${start}&len=\${duration}');
    final range = CatchupRange(DateTime(2026, 11, 14, 20, 0), 45);
    final epoch = DateTime(2026, 11, 14, 20, 0).millisecondsSinceEpoch ~/ 1000;
    expect(catchupUrlFor(channel, range),
        'https://example.invalid/timeshift?start=$epoch&len=45');
  });

  test('unknown mode without a template refuses to guess', () {
    expect(
        catchupUrlFor(
            _channel(mode: 'flussonic'),
            CatchupRange(DateTime(2026, 11, 14, 20, 0), 30)),
        isNull);
    expect(
        catchupUrlFor(
            _channel(), CatchupRange(DateTime(2026, 11, 14, 20, 0), 30)),
        isNull);
  });

  test('Xtream archive builds the panel timeshift URL', () {
    final channel = _channel(
        url: 'http://example.invalid:8080/live/user/pass/123.ts',
        mode: 'xc',
        days: 4);
    final range = CatchupRange(DateTime(2026, 11, 14, 20, 5), 65);
    expect(catchupUrlFor(channel, range),
        'http://example.invalid:8080/timeshift/user/pass/65/2026-11-14:20-05/123.m3u8');
  });

  test('Xtream derivation rejects non-live URL shapes', () {
    final channel = _channel(
        url: 'http://example.invalid:8080/custom/stream.m3u8', mode: 'xc');
    expect(
        catchupUrlFor(
            channel, CatchupRange(DateTime(2026, 11, 14, 20, 0), 30)),
        isNull);
  });

  test('guide slot inside the window resolves to the programme', () {
    final now = DateTime(2026, 11, 14, 20, 30);
    final range = catchupRangeFor(_channel(mode: 'default', days: 3),
        program: _program(
            DateTime(2026, 11, 14, 20, 0), DateTime(2026, 11, 14, 21, 0)),
        now: now);
    expect(range, isNotNull);
    expect(range!.start, DateTime(2026, 11, 14, 20, 0));
    expect(range.durationMinutes, 30);
  });

  test('guide slot predating the archive window does not resolve', () {
    final now = DateTime(2026, 11, 14, 20, 30);
    final range = catchupRangeFor(_channel(mode: 'default', days: 1),
        program: _program(
            DateTime(2026, 11, 12, 20, 0), DateTime(2026, 11, 12, 21, 0)),
        now: now);
    expect(range, isNull);
    expect(
        canWatchFromStart(_channel(mode: 'default', days: 1),
            currentProgram: _program(
                DateTime(2026, 11, 12, 20, 0), DateTime(2026, 11, 12, 21, 0)),
            now: now),
        isFalse);
  });

  test('future guide slot does not resolve', () {
    final now = DateTime(2026, 11, 14, 20, 30);
    expect(
        catchupRangeFor(_channel(mode: 'xc', days: 4),
            program: _program(DateTime(2026, 11, 14, 21, 0),
                DateTime(2026, 11, 14, 22, 0)),
            now: now),
        isNull);
  });

  test('no guide slot falls back to a bounded rewind', () {
    final now = DateTime(2026, 11, 14, 20, 30);
    final range =
        catchupRangeFor(_channel(mode: 'default', days: 3), now: now);
    expect(range, isNotNull);
    expect(range!.durationMinutes, 180);
    expect(range.start, now.subtract(const Duration(hours: 3)));
  });

  test('channels without catch-up never resolve', () {
    final now = DateTime(2026, 11, 14, 20, 30);
    expect(
        catchupRangeFor(_channel(), now: now), isNull);
    expect(canWatchFromStart(_channel(), now: now), isFalse);
  });
}
