import 'package:flutter/foundation.dart';

import '../models/epg_program.dart';
import '../models/sports.dart';
import '../utils/epg_timeline.dart';
import 'epg_service.dart' show normalizeEpgId;
import 'sports_channel_matcher.dart';

/// One confident channel-to-fixture binding the guide may display.
class SportsGuideBinding {
  const SportsGuideBinding(this.epgId, this.game);
  final String epgId;
  final SportsGame game;
}

/// Fixture titles for sports event channels whose provider guide has nothing.
///
/// This is *display only*: it holds programmes in memory for the Live TV guide
/// and never writes rows to [EpgDatabase] or [EpgService]. Matching reads its
/// evidence from the real guide, so a title shown here can never come back as
/// evidence for the binding that produced it — a wrong channel stays a wrong
/// channel instead of confirming itself on the next refresh.
///
/// [publishMatches] is fed the same [ChannelMatch] results the Sports screen
/// already computed; only confident, non-manual event evidence is published.
/// Listings are bounded to [horizon] ahead and [retention] behind, so a stale
/// card from a channel the provider deleted quietly disappears.
class SportsGuideOverlay extends ChangeNotifier {
  SportsGuideOverlay({
    this.horizon = const Duration(hours: 24),
    this.retention = const Duration(hours: 6),
  });

  static final SportsGuideOverlay instance = SportsGuideOverlay();

  /// How far ahead of now a published fixture may still appear.
  final Duration horizon;

  /// How long after a programme ends its row may still be shown.
  final Duration retention;

  /// Safety cap on channels carrying synthetic listings in one publish.
  static const maxChannels = 512;

  /// A fixture with no scheduled end gets this slot instead.
  static const _defaultDuration = Duration(hours: 3);

  /// Long tournaments (golf, racing) are clamped to a normal programme block.
  static const _maxDuration = Duration(hours: 6);

  static const _maxPerChannel = 12;

  final Map<String, List<EpgProgram>> _byChannel = {};
  Object? _scope;
  int _revision = 0;

  /// Bumped whenever the visible listings change, so guide rows can rebuild.
  int get revision => _revision;

  bool get isEmpty => _byChannel.isEmpty;

  /// Listings for [epgId], or null when the overlay has nothing for it.
  ///
  /// Normalizes the id the same way every other guide lookup does, and drops
  /// programmes that ended longer than [retention] ago.
  List<EpgProgram>? programmesFor(String epgId) {
    final rows = _byChannel[normalizeEpgId(epgId)];
    if (rows == null || rows.isEmpty) return null;
    final cutoff = DateTime.now().subtract(retention);
    final kept = [
      for (final programme in rows)
        if (programme.stop.isAfter(cutoff)) programme
    ];
    return kept.isEmpty ? null : kept;
  }

  EpgProgram? currentProgram(String epgId, DateTime now) =>
      programmeAt(programmesFor(epgId) ?? const [], now);

  EpgProgram? nextProgram(String epgId, DateTime now) =>
      nextProgrammeAfter(programmesFor(epgId) ?? const [], now);

  /// Publishes the confident channel bindings among [matches].
  ///
  /// [scope] identifies the playlist/catalogue the matches were computed for;
  /// passing a different scope drops the previous scope's listings rather than
  /// leaving one provider's channels titled with another's fixtures.
  void publishMatches(
    Iterable<SportsGame> games,
    Map<String, List<ChannelMatch>> matches, {
    required String Function(SportsGame game) key,
    Object? scope,
    DateTime? now,
  }) {
    final gameByKey = {for (final game in games) key(game): game};
    final bindings = <SportsGuideBinding>[];
    for (final entry in matches.entries) {
      final game = gameByKey[entry.key];
      if (game == null) continue;
      for (final match in entry.value) {
        // A manual pick is the viewer's instruction, not fixture evidence; it
        // keeps its own channel card and must not retitle that channel's guide.
        if (!match.isConfident || match.reason == MatchReason.pick) continue;
        bindings.add(SportsGuideBinding(match.channel.epgId, game));
      }
    }
    publish(bindings, scope: scope, now: now);
  }

  void publish(
    Iterable<SportsGuideBinding> bindings, {
    Object? scope,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    var changed = false;
    if (scope != null && scope != _scope) {
      _scope = scope;
      changed = _byChannel.isNotEmpty;
      _byChannel.clear();
    }

    final from = at.subtract(retention);
    final until = at.add(horizon);
    final next = <String, List<EpgProgram>>{};
    for (final binding in bindings) {
      final id = normalizeEpgId(binding.epgId);
      if (id.isEmpty) continue;
      final game = binding.game;
      if (game.start.isAfter(until)) continue;
      final stop = _stopOf(game);
      if (!stop.isAfter(from) || !stop.isAfter(game.start)) continue;
      final title = _titleOf(game);
      final rows = next[id] ??= <EpgProgram>[];
      if (rows.any((row) => row.start == game.start && row.title == title)) {
        continue;
      }
      rows.add(EpgProgram(
        channelId: id,
        title: title,
        description: game.league.name,
        isLive: game.isLive,
        start: game.start,
        stop: stop,
      ));
    }

    for (final rows in next.values) {
      rows.sort((a, b) => a.start.compareTo(b.start));
      if (rows.length > _maxPerChannel) {
        rows.removeRange(_maxPerChannel, rows.length);
      }
    }
    if (next.length > maxChannels) {
      final keep = next.keys.take(maxChannels).toSet();
      next.removeWhere((id, _) => !keep.contains(id));
    }

    if (!changed && _sameAs(next)) return;
    _byChannel
      ..clear()
      ..addAll(next);
    _revision++;
    notifyListeners();
  }

  void clear() {
    if (_byChannel.isEmpty && _scope == null) return;
    _byChannel.clear();
    _scope = null;
    _revision++;
    notifyListeners();
  }

  DateTime _stopOf(SportsGame game) {
    final end = game.end;
    if (end == null || !end.isAfter(game.start)) {
      return game.start.add(_defaultDuration);
    }
    final limit = game.start.add(_maxDuration);
    return end.isAfter(limit) ? limit : end;
  }

  String _titleOf(SportsGame game) {
    final title = game.title.trim();
    return title.isEmpty ? '${game.away.name} vs ${game.home.name}' : title;
  }

  bool _sameAs(Map<String, List<EpgProgram>> next) {
    if (next.length != _byChannel.length) return false;
    for (final entry in next.entries) {
      final rows = _byChannel[entry.key];
      if (rows == null || rows.length != entry.value.length) return false;
      for (var i = 0; i < rows.length; i++) {
        final before = rows[i], after = entry.value[i];
        if (before.channelId != after.channelId ||
            before.title != after.title ||
            before.description != after.description ||
            before.isLive != after.isLive ||
            before.start != after.start ||
            before.stop != after.stop) {
          return false;
        }
      }
    }
    return true;
  }
}
