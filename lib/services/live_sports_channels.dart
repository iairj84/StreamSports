import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;

import '../models/channel.dart';
import '../models/sports.dart';
import '../utils/sports_calendar.dart';
import '../utils/sports_channel_filter.dart';
import '../utils/sports_detail_presentation.dart';
import '../utils/sports_fixture_presentation.dart';
import 'epg_service.dart';
import 'multiview_sports.dart';
import 'playlist_manager.dart';
import 'sports_channel_matcher.dart';
import 'sports_follows.dart';
import 'sports_service.dart';
import 'storage_service.dart';

/// Live TV's pinned "Live Sports" category: the channel each live game is on,
/// for the leagues and teams the viewer follows.
///
/// The rows are real channels, never synthetic ones, so every guide action
/// (tune, catch-up, channel options, CH+/−) already works on them. A game is
/// represented by the channel Sports would start for it — the matcher's own
/// ranking, the viewer's saved pick first — so the category and the Sports card
/// agree on where a game is.
///
/// The work is the Multiview picker's live-game load, already bounded to
/// followed leagues and to games with a matched channel. It runs when the
/// category is opened (or its rows have aged out), never at startup: it reads
/// the guide and runs the matcher, which a TV box should not pay for until
/// asked. While the category stays open, [startTicker] rechecks so the score
/// line under each channel is not a snapshot.
class LiveSportsChannels extends ChangeNotifier {
  LiveSportsChannels._();

  static final LiveSportsChannels instance = LiveSportsChannels._();

  /// No live score is drawn inside the guide's blocks, so the rows only need
  /// refreshing often enough to keep the label's score and clock current.
  static const refreshAfter = Duration(minutes: 2);
  static const tick = Duration(seconds: 60);

  List<Channel> _channels = const [];
  final Map<String, _LiveSportsRow> _rows = {};
  String? _leadId;
  bool _loading = false;
  bool _loaded = false;
  Object? _error;
  DateTime? _loadedAt;
  Future<void>? _inFlight;
  (StorageService, PlaylistManager, EpgService)? _sources;
  Timer? _ticker;

  /// Rows in guide order: RedZone on Sundays, followed teams, then kick-off.
  List<Channel> get channels => _channels;

  bool get loading => _loading;

  /// True once a load has finished, even if it found nothing.
  bool get loaded => _loaded;

  /// The last load's failure, cleared by the next success. Rows from the last
  /// good load stay on screen.
  Object? get error => _error;

  bool get isEmpty => _channels.isEmpty;

  bool get stale =>
      _loadedAt == null || DateTime.now().difference(_loadedAt!) >= refreshAfter;

  /// The live game on a row, when the channel has one. Null for the Sunday
  /// lead channel — a channel, not a fixture — and for every other category.
  _LiveSportsRow? _gameRow(String channelId) =>
      channelId == _leadId ? null : _rows[channelId];

  /// The tag beside a row's name in the Timeline Guide: the game's score, or
  /// its clock when the viewer hides scores. Null for anything but a followed
  /// game, whose row keeps its playlist label instead.
  String? labelFor(String channelId,
      {required bool hideScores, required bool hideMyTeams}) {
    final row = _gameRow(channelId);
    if (row == null) return null;
    return scoreLabelFor(row.game,
        hideScores: hideScores, hideMyTeams: hideMyTeams, followed: row.followed);
  }

  /// [gameStatusLine] for a loaded row. Null where the row is a channel, so it
  /// keeps its programme line.
  String? statusLineFor(String channelId,
      {required bool hideScores, required bool hideMyTeams}) {
    final row = _gameRow(channelId);
    if (row == null) return null;
    return gameStatusLine(row.game,
        hideScores: hideScores,
        hideMyTeams: hideMyTeams,
        followed: row.followed);
  }

  /// The game's own title where a row is a live game — "RSM Classic",
  /// "BOS at LAL" — so the category reads as the games it lists instead of as
  /// a wall of channel names. Null where the row is a channel, which keeps its
  /// own name.
  String? titleFor(String channelId) => _gameRow(channelId)?.game.title;

  /// The line under a row's game name, without I/O: the score, then the clock
  /// with who has the ball (football down & distance, baseball count), or — for
  /// a field event, which has no score — the leader or the round. This is the
  /// game's own state, not the channel's EPG programme, which says nothing
  /// about the game the row is for.
  @visibleForTesting
  static String? gameStatusLine(SportsGame game,
      {required bool hideScores,
      required bool hideMyTeams,
      required bool followed}) {
    final hidden = hideScores || (hideMyTeams && followed);
    final score = scoreLabelFor(game,
        hideScores: hideScores, hideMyTeams: hideMyTeams, followed: followed);
    // A hidden score must not become a visible down & distance or leader.
    if (hidden) return score;
    var extra = game.league.isField
        ? sportsFixtureInsight(game, hideScores: false)
        : sportsLiveProgress(game);
    // Without a score yet the score slot already falls back to the status, and
    // the progress line opens with that same status; keep it once.
    if (score != null && extra != null && extra.startsWith('$score · ')) {
      extra = extra.substring(score.length + 3);
    }
    if (extra == null || extra.isEmpty || extra == score) return score;
    return score == null ? extra : '$score · $extra';
  }

  /// [game]'s score line without I/O, in the shape the guide's label slot
  /// takes: the leading side and both scores ("BOS 88–84"), or the provider's
  /// own status ("Q3 4:12") when scores are hidden or absent.
  @visibleForTesting
  static String? scoreLabelFor(SportsGame game,
      {required bool hideScores,
      required bool hideMyTeams,
      required bool followed}) {
    final status = game.statusText.trim();
    if (hideScores || (hideMyTeams && followed)) {
      return status.isEmpty ? null : status;
    }
    final first = game.first, second = game.second;
    final a = first.score?.trim(), b = second.score?.trim();
    if (a == null || b == null || a.isEmpty || b.isEmpty) {
      return status.isEmpty ? null : status;
    }
    final side = first.abbreviation.trim().isEmpty
        ? first.shortName.trim()
        : first.abbreviation.trim();
    return '$side $a–$b';
  }

  /// Loads the category unless it is already fresh, sharing one request across
  /// concurrent callers. [force] rechecks when the viewer opens it.
  Future<void> refresh({
    required StorageService storage,
    required PlaylistManager playlist,
    required EpgService epg,
    bool force = false,
  }) {
    final running = _inFlight;
    if (running != null) return running;
    _sources = (storage, playlist, epg);
    if (!force && _loaded && !stale) return Future<void>.value();
    final completer = Completer<void>();
    _inFlight = completer.future;
    unawaited(_run(storage, playlist, epg).whenComplete(() {
      _inFlight = null;
      if (!completer.isCompleted) completer.complete();
    }));
    return completer.future;
  }

  /// Keeps the open category current: scores move and games end while it is on
  /// screen. Safe to call repeatedly.
  void startTicker() {
    _ticker ??= Timer.periodic(tick, (_) {
      final sources = _sources;
      if (sources == null) return;
      // A backgrounded app must not keep polling the score feed.
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      unawaited(refresh(
          storage: sources.$1,
          playlist: sources.$2,
          epg: sources.$3,
          force: true));
    });
  }

  void stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _run(
      StorageService storage, PlaylistManager playlist, EpgService epg) async {
    _loading = true;
    notifyListeners();
    try {
      final follows = SportsFollows.load(storage);
      final live = await MultiviewSports.liveGames(
          storage: storage, playlist: playlist, epg: epg);
      final lead = _redZoneChannel(storage, playlist);
      final rows = rowsFor(live, involves: follows.involves, lead: lead);
      _rows
        ..clear()
        ..addEntries(live.map((entry) => MapEntry(
            primaryChannel(entry).id,
            _LiveSportsRow(entry.game, follows.involves(entry.game)))));
      _leadId = lead?.id;
      _channels = rows;
      _loaded = true;
      _error = null;
      _loadedAt = DateTime.now();
      debugPrint('IPTV_LIVE_SPORTS games=${live.length} rows=${rows.length}');
    } catch (error) {
      // The last good rows stay: a failed refresh must not empty the guide.
      _error = error;
      debugPrint('IPTV_LIVE_SPORTS failed: ${error.runtimeType}');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// The Sunday hub channel, when the viewer shows the NFL and their playlist
  /// carries one. It is a channel rather than a fixture, so it leads the
  /// category on the day the whole afternoon is on it.
  static Channel? _redZoneChannel(
      StorageService storage, PlaylistManager playlist) {
    if (sportsCalendarDay(DateTime.now()).weekday != DateTime.sunday) {
      return null;
    }
    if (!savedSportsLeagues(storage).any((l) => l.id == 'nfl')) return null;
    final picks = SportsChannelPicks.load(storage);
    return redZoneChannelOf(
        playlist.visibleLiveChannels, picks.redZoneChannelId);
  }

  /// The channel a press on [entry] should start: the matcher's ranked first,
  /// promoted to a 4K sibling copy where one exists, exactly like playback.
  @visibleForTesting
  static Channel primaryChannel(LiveGameChannel entry) =>
      (preferredPlaybackChannel(entry.matches, SportsChannelFilter.all) ??
              entry.matches.first)
          .channel;

  /// The category's rows for [live], without I/O.
  ///
  /// One row per channel: two games on the same feed are one tunable row, and
  /// the earlier (or followed) game keeps it. Ordering is the followed teams
  /// first, then start time, then the game's title so equal kick-offs never
  /// shuffle between refreshes. [lead] (RedZone) heads the list on its day.
  @visibleForTesting
  static List<Channel> rowsFor(Iterable<LiveGameChannel> live,
      {required bool Function(SportsGame game) involves, Channel? lead}) {
    final ordered = [...live]..sort((a, b) {
        final mine =
            (involves(a.game) ? 0 : 1).compareTo(involves(b.game) ? 0 : 1);
        if (mine != 0) return mine;
        final start = a.game.start.compareTo(b.game.start);
        if (start != 0) return start;
        final title = a.game.title.compareTo(b.game.title);
        return title != 0 ? title : a.game.id.compareTo(b.game.id);
      });
    final rows = <Channel>[];
    final seen = <String>{};
    if (lead != null && seen.add(lead.id)) rows.add(lead);
    for (final entry in ordered) {
      final channel = primaryChannel(entry);
      if (seen.add(channel.id)) rows.add(channel);
    }
    return List<Channel>.unmodifiable(rows);
  }
}

class _LiveSportsRow {
  const _LiveSportsRow(this.game, this.followed);
  final SportsGame game;
  final bool followed;
}
