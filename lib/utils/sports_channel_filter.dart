import '../models/channel.dart';
import '../models/epg_program.dart';
import '../services/sports_channel_matcher.dart';
import 'sports_channel_variants.dart';
import 'sports_programme_identity.dart';

/// Confidence is independent of loading state. Pending/failed checks must never
/// admit possible matches into the confirmed-channel view.
enum SportsChannelFilter {
  matched,
  possible,
  all;

  String get label => switch (this) {
        matched => 'With channel',
        possible => 'Possible channels',
        all => 'All events',
      };
  String get description => switch (this) {
        matched => 'Event-specific evidence or your saved choice',
        possible => 'Possible coverage and events still being checked',
        all => 'Include events with no channel found',
      };
  ChannelMatch? preferred(Iterable<ChannelMatch> matches) =>
      (this == matched ? matches.where((m) => m.isConfident) : matches)
          .firstOrNull;
  bool accepts(List<ChannelMatch> matches, {required bool pending}) =>
      switch (this) {
        matched => matches.any((m) => m.isConfident),
        possible => matches.isNotEmpty || pending,
        all => true,
      };
}

/// The channel a press starts when the viewer has not chosen one. Equal
/// evidence orders sibling copies of one provider feed in provider order, which
/// is also the picker's order; playback alone may promote a 4K copy, so the
/// list, its labels and any saved choice stay exactly as ranked.
ChannelMatch? preferredPlaybackChannel(
    Iterable<ChannelMatch> ranked, SportsChannelFilter filter) {
  final matches = ranked.toList(growable: false);
  final best = filter.preferred(matches);
  if (best == null || best.reason == MatchReason.pick) return best;
  if (sportsChannelIs4K(best.channel.name)) return best;
  final family = sportsChannelNameWithoutQuality(best.channel.name);
  if (family.isEmpty) return best;
  for (final candidate in matches) {
    if (identical(candidate, best) ||
        candidate.reason != best.reason ||
        candidate.score != best.score ||
        candidate.channel.playlistId != best.channel.playlistId ||
        sportsChannelNameWithoutQuality(candidate.channel.name) != family ||
        !sportsChannelIs4K(candidate.channel.name) ||
        !_sameProgrammeSlot(best.programme, candidate.programme)) {
      continue;
    }
    return candidate;
  }
  return best;
}

bool _sameProgrammeSlot(EpgProgram? a, EpgProgram? b) =>
    a == null || b == null ? a == b : sameSportsProgramme(a, b);

/// Display playback identity without changing matching confidence or filter
/// admission. Guide refreshes must not label an already playing tile with a
/// different recommendation while its new saved choice is being checked.
ChannelMatch? displayedSportsChannel(
    List<ChannelMatch> matches, SportsChannelFilter filter,
    {Channel? playing, String? savedId}) {
  if (playing == null) return filter.preferred(matches);
  final evidence = matches.where((m) => m.channel.id == playing.id).firstOrNull;
  if (savedId == playing.id) {
    return ChannelMatch(playing, MatchReason.pick, 1000,
        programme: evidence?.programme);
  }
  return evidence ??
      ChannelMatch(playing, MatchReason.sport, 0,
          detail: 'Playing channel · current match unverified');
}
