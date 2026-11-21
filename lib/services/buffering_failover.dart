import '../models/channel.dart';
import 'playback_health.dart';

/// Counts real buffering stalls on the live channel being watched and says
/// when it has struggled enough that the linked backup is better than the
/// spinner.
///
/// A stall only counts once it has lasted [minimumStall] — a momentary refill
/// is normal on a live edge — and only stalls inside [window] add up together.
/// Pure bookkeeping with an injected `now`, so the rule is testable without a
/// player or a clock.
class BufferingFailoverWatcher {
  BufferingFailoverWatcher({
    this.window = const Duration(minutes: 10),
    this.threshold = 2,
    this.minimumStall = const Duration(seconds: 3),
  });

  final Duration window;
  final int threshold;
  final Duration minimumStall;

  String? _channelId;
  bool _inStall = false;
  final List<DateTime> _stalls = [];

  String? get channelId => _channelId;

  /// Start counting for [channelId]. A different channel starts over, so a
  /// count never carries across a zap.
  void watch(String channelId) {
    if (_channelId == channelId) return;
    _channelId = channelId;
    _stalls.clear();
    _inStall = false;
  }

  /// Feed every health update. True exactly once, on the update that reaches
  /// [threshold]; [reset] must run before counting towards another switch.
  bool observe({
    required StreamPhase phase,
    required int seconds,
    required DateTime now,
  }) {
    if (phase != StreamPhase.buffering) {
      _inStall = false;
      return false;
    }
    // One stall is one count, however many updates it spans.
    if (_inStall) return false;
    if (seconds < minimumStall.inSeconds) return false;
    _inStall = true;
    _stalls.add(now);
    _stalls.removeWhere((at) => now.difference(at) > window);
    return _stalls.length >= threshold;
  }

  void reset() {
    _stalls.clear();
    _inStall = false;
  }
}

/// The backup [channel] should fall over to right now: [backup], unless it
/// does not resolve to a different channel or either side switched within
/// [cooldown] (switching again that soon would just bounce between the same
/// two feeds).
Channel? autoFailoverTarget(
  Channel channel, {
  required Channel? backup,
  required Map<String, DateTime> recentSwitches,
  required DateTime now,
  Duration cooldown = const Duration(minutes: 30),
}) {
  if (backup == null || backup.id == channel.id) return null;
  bool cooling(String id) {
    final at = recentSwitches[id];
    return at != null && now.difference(at) <= cooldown;
  }

  if (cooling(channel.id) || cooling(backup.id)) return null;
  return backup;
}
