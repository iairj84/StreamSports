import 'package:flutter/widgets.dart';
import '../models/sports.dart';
import 'sports_match_inputs.dart';
import 'sports_match_session.dart';
import 'sports_channel_matcher.dart';

/// Small, in-memory presentation cache shared by the hub and multiview picker.
/// Scores still come from their normal feed caches and refresh on every visit.
/// No widgets, focus nodes, players or full channel indexes are retained here.
class SportsBrowseCache with WidgetsBindingObserver {
  SportsBrowseCache();
  static final shared = SportsBrowseCache().._observe();
  void _observe() => WidgetsBinding.instance.addObserver(this);

  /// How long a completed board is reused by later visits. The read key
  /// fingerprints the guide, catalogue and day, so changed evidence still
  /// misses; inside this window each event's own boundary and age decide what
  /// is rechecked, instead of the whole board being matched again on arrival.
  static const retention = Duration(minutes: 60);

  final _entries = <Object, SportsBrowseSnapshot>{};
  SportsBrowseSnapshot? read(Object key, DateTime now) {
    _entries.removeWhere((_, value) =>
        now.isBefore(value.savedAt) || !now.isBefore(value.expiresAt));
    return _entries[key];
  }

  void save(Object key, SportsMatchSession session, List<SportsGame> guideGames,
      Object? signature, DateTime now,
      {required Iterable<SportsGame> games,
      Object? guideDiscovery,
      DateTime? guideDiscoveryUntil}) {
    // Bound memory independently of the number of enabled leagues/days.
    if (session.identities.length > 2000) return;
    final until = now.add(retention);
    final boundaries = <String, DateTime>{};
    for (final game in games) {
      final eventBoundary = sportsMatchBoundary(game, now);
      if (eventBoundary != null) {
        boundaries[SportsChannelPicks.eventKey(game)] = eventBoundary;
      }
    }
    _entries.remove(key);
    _entries[key] = SportsBrowseSnapshot(session.copy(),
        List.unmodifiable(guideGames), signature, now, until, boundaries,
        guideDiscovery: guideDiscovery,
        guideDiscoveryUntil: guideDiscoveryUntil);
    while (_entries.length > 2) {
      _entries.remove(_entries.keys.first);
    }
  }

  @override
  void didHaveMemoryPressure() => _entries.clear();
}

class SportsBrowseSnapshot {
  SportsBrowseSnapshot(this._session, this.guideGames, this.signature,
      this.savedAt, this.expiresAt, this._boundaries,
      {this.guideDiscovery, this.guideDiscoveryUntil});
  final SportsMatchSession _session;
  final List<SportsGame> guideGames;
  final Object? signature;
  final Map<String, DateTime> _boundaries;
  final DateTime savedAt, expiresAt;

  /// The completed guide discovery this board came from, so a later visit does
  /// not rescan the whole day for the event list it already has.
  final Object? guideDiscovery;
  final DateTime? guideDiscoveryUntil;

  /// Every route owns its mutable state. Restoring never extends evidence age.
  SportsMatchSession restoreSession({DateTime? at}) {
    final restored = _session.copy();
    final now = at ?? DateTime.now();
    restored.expireEvents({
      for (final e in _boundaries.entries)
        if (!now.isBefore(e.value)) e.key,
    });
    return restored;
  }
}
