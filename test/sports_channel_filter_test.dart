import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/services/sports_channel_matcher.dart';
import 'package:nox_iptv/models/epg_program.dart';
import 'package:nox_iptv/utils/sports_channel_filter.dart';

void main() {
  final channel = Channel(
      id: 'test',
      rawId: 'test',
      playlistId: 'test',
      name: 'Sports channel',
      group: 'Sports',
      url: 'https://example.invalid');
  final strong = ChannelMatch(channel, MatchReason.name, 420);
  final weak = ChannelMatch(channel, MatchReason.sport, 80);
  test('pending events appear only in possible/all, never With channel', () {
    expect(SportsChannelFilter.matched.accepts([], pending: true), false);
    expect(SportsChannelFilter.matched.accepts([weak], pending: true), false);
    expect(SportsChannelFilter.possible.accepts([], pending: true), true);
    expect(SportsChannelFilter.possible.accepts([], pending: false), false);
    expect(SportsChannelFilter.possible.accepts([weak], pending: true), true);
    expect(SportsChannelFilter.all.accepts([], pending: true), true);
  });
  test('possible mode adds weaker suggestions without weakening With channel',
      () {
    expect(SportsChannelFilter.matched.accepts([weak], pending: false), false);
    expect(SportsChannelFilter.possible.accepts([weak], pending: false), true);
    for (final mode in SportsChannelFilter.values) {
      expect(mode.accepts([strong, weak], pending: false), true);
    }
  });
  test('pending weak suggestions cannot auto-play under With channel', () {
    expect(SportsChannelFilter.matched.preferred([weak]), isNull);
    expect(SportsChannelFilter.matched.preferred([weak, strong]), same(strong));
    expect(SportsChannelFilter.possible.preferred([weak]), same(weak));
    expect(SportsChannelFilter.all.preferred([]), isNull);
  });

  Channel named(String id, String name) => Channel(
      id: id,
      rawId: id,
      playlistId: 'p',
      name: name,
      group: 'Sports',
      url: 'https://example.invalid');
  final slot = EpgProgram(
      channelId: 'x',
      title: 'Abu Dhabi Grand Prix',
      start: DateTime.utc(2026, 11, 12, 20),
      stop: DateTime.utc(2026, 11, 12, 22));
  test('playback plays the 4K copy while the ranked order keeps provider order',
      () {
    final matches = [
      ChannelMatch(named('hd', 'Sky Sports F1 HD'), MatchReason.guide, 320,
          programme: slot),
      ChannelMatch(named('uhd', 'Sky Sports F1 4K'), MatchReason.guide, 320,
          programme: slot),
    ];
    expect(SportsChannelFilter.matched.preferred(matches)!.channel.id, 'hd',
        reason: 'Picker order and labels keep the provider order');
    expect(
        preferredPlaybackChannel(matches, SportsChannelFilter.matched)!
            .channel
            .id,
        'uhd');
  });
  test('only identical evidence promotes a 4K copy', () {
    final hd = ChannelMatch(named('hd', 'Sky Sports F1 HD'),
        MatchReason.guide, 320, programme: slot);
    final weaker4k = ChannelMatch(named('uhd', 'Sky Sports F1 4K'),
        MatchReason.guide, 310, programme: slot);
    final other4k = ChannelMatch(named('cricket', 'Sky Sports Cricket 4K'),
        MatchReason.guide, 320, programme: slot);
    final otherSlot = ChannelMatch(named('uhd2', 'Sky Sports F1 UHD'),
        MatchReason.guide, 320,
        programme: EpgProgram(
            channelId: 'y',
            title: 'Qualifying',
            start: DateTime.utc(2026, 11, 12, 18),
            stop: DateTime.utc(2026, 11, 12, 19)));
    for (final sibling in [weaker4k, other4k, otherSlot]) {
      expect(
          preferredPlaybackChannel([hd, sibling], SportsChannelFilter.matched)!
              .channel
              .id,
          'hd');
    }
  });
  test('a saved pick is never replaced by a 4K sibling', () {
    final matches = [
      ChannelMatch(named('hd', 'Sky Sports F1 HD'), MatchReason.pick, 1000,
          programme: slot),
      ChannelMatch(named('uhd', 'Sky Sports F1 4K'), MatchReason.guide, 320,
          programme: slot),
    ];
    expect(
        preferredPlaybackChannel(matches, SportsChannelFilter.matched)!
            .channel
            .id,
        'hd');
  });
}
