import 'dart:convert';
import '../models/epg_program.dart';
import '../models/sports.dart';
import '../utils/formula_one.dart';

/// The next fixture/listing transition that requires a new coverage check.
DateTime? sportsMatchBoundary(SportsGame game, DateTime checkedAt) {
  DateTime? next;
  void consider(DateTime? value) {
    if (value != null &&
        value.isAfter(checkedAt) &&
        (next == null || value.isBefore(next!))) {
      next = value;
    }
  }

  consider(game.start);
  consider(game.end);
  if (isFormulaOne(game)) consider(game.start.subtract(f1BuildUpLead(game)));
  for (final listing in game.onlineBroadcasts) {
    consider(listing.expiresAt);
    consider(listing.programme?.start);
    consider(listing.programme?.stop);
  }
  return next;
}

/// How long this fixture's matched channels stay usable from disk.
///
/// A match is expensive to derive (a whole-day programme scan) and rarely
/// changes, so it is remembered past the handful of minutes the live board
/// rechecks: five minutes for a game on air or about to start, half an hour for
/// one later today, six hours once it is over. The next known transition —
/// kick-off, programme start or stop, listing expiry — still ends it early,
/// because that is when the evidence itself moves.
DateTime sportsMatchMemoryUntil(SportsGame game, DateTime now) {
  final horizon = switch (game.state) {
    GameState.live => const Duration(minutes: 5),
    GameState.post => const Duration(hours: 6),
    GameState.pre => game.start.difference(now) <= const Duration(minutes: 45)
        ? const Duration(minutes: 5)
        : const Duration(minutes: 30),
  };
  final cap = now.add(horizon);
  var until = cap;
  void boundary(DateTime? at) {
    if (at != null && at.isAfter(now) && at.isBefore(until)) until = at;
  }

  boundary(sportsMatchBoundary(game, now));
  // The shared boundary helper tracks the fixture and its listings; the rows
  // this game was matched through move too, so they end the memory as well.
  for (final programme in game.guideProgrammes) {
    boundary(programme.start);
    boundary(programme.stop);
  }
  return until;
}

/// Read-only inputs for matching. The scorer can run without preferences,
/// platform plugins, network clients or the widget tree.
abstract interface class SportsMatchGuide {
  int get changeRevision;
  DateTime? get lastUpdated;
  EpgProgram? getCurrentProgram(String channelId);
  EpgProgram? getNextProgram(String channelId);
  Future<List<EpgProgram>> findProgrammesByTitle(
      DateTime from, DateTime to, List<String> terms);
  Future<List<EpgProgram>> findSportsProgrammesForChannels(
      List<String> ids, DateTime from, DateTime to);
}

abstract interface class SportsMatchPicks {
  String? channelIdFor(SportsGame game);
}

/// Optional decisions, separate from trying or preferring a stream.
abstract interface class SportsMatchRejections {
  int get decisionsRevision;
  Set<String> rejectedKeysFor(SportsGame game);
}

String sportsRejectionKey(String channelId, EpgProgram? programme) =>
    jsonEncode([
      channelId,
      if (programme != null) ...[
        programme.start.millisecondsSinceEpoch,
        programme.stop.millisecondsSinceEpoch,
        programme.title,
      ]
    ]);

bool sportsChannelRejected(
    Set<String> keys, String channelId, EpgProgram? programme) {
  if (keys.isEmpty) return false;
  final channel = sportsRejectionKey(channelId, null);
  if (keys.contains(channel)) return true;
  if (programme != null) {
    return keys.contains(sportsRejectionKey(channelId, programme));
  }
  // A pinned preference may omit guide evidence. It must not resurrect a
  // rejected suggestion while that event's programme is being rechecked.
  final prefix = '${channel.substring(0, channel.length - 1)},';
  return keys.any((key) => key.startsWith(prefix));
}
