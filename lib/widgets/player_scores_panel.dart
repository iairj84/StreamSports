import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/sports.dart';
import '../models/surface_style.dart';
import '../services/app_preferences.dart';
import '../services/playlist_manager.dart';
import '../services/sports_channel_matcher.dart';
import '../services/sports_service.dart';
import '../services/storage_service.dart';
import '../utils/interface_colors.dart';
import '../utils/time_format.dart';
import 'sports_filter_picker.dart';

/// Scores while watching.
///
/// Loads the day's fixtures the viewer already follows, keeps them in one row
/// of cards — live, then starting soon, then finals — and scopes the row to
/// what is live now by default. Left/Right walks the games, Up/Down changes the
/// scope (Live, All, then each sport), OK hands the game back to the player so
/// it can tune the matched channel.
class PlayerScoresPanel extends StatefulWidget {
  const PlayerScoresPanel(
      {super.key,
      this.focusNode,
      required this.onClose,
      required this.onPlay,
      this.watchingGame});

  /// The player owns this node so it can hand the remote over on open and take
  /// it back on close.
  final FocusNode? focusNode;
  final VoidCallback onClose;
  final ValueChanged<SportsGame> onPlay;

  /// The game currently playing, when the viewer tuned it from this app. The
  /// row opens on that card instead of the first one.
  final SportsGame? watchingGame;

  @override
  State<PlayerScoresPanel> createState() => _PlayerScoresPanelState();
}

/// One choice in the Up/Down cycle: the live-only row, everything, or a sport.
class _Scope {
  const _Scope(this.label, this.sport, {required this.liveOnly});

  final String label;
  final String? sport;
  final bool liveOnly;

  bool accepts(SportsGame game) =>
      (!liveOnly || game.isLive) && (sport == null || _sportOf(game) == sport);

  static String _sportOf(SportsGame game) => game.league.espnPath.split('/').first;
}

class _PlayerScoresPanelState extends State<PlayerScoresPanel> {
  static const _cardExtent = 218.0;
  final _cards = <FocusNode>[];
  final _scroll = ScrollController();
  List<SportsGame> _games = const [];
  int _scope = 1;
  int _index = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final node in _cards) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  /// RedZone's own card on Sundays, when the playlist carries a channel for
  /// it: the channel is the card, so it sits with the live games.
  SportsGame? _redZoneCard(List<SportsLeague> leagues, DateTime now) {
    if (now.weekday != DateTime.sunday) return null;
    if (!leagues.any((l) => l.id == 'nfl')) return null;
    final channel = redZoneChannelOf(
        context.read<PlaylistManager>().visibleLiveChannels,
        SportsChannelPicks.load(context.read<StorageService>())
            .redZoneChannelId);
    return channel == null
        ? null
        : nflRedZoneGame(now, logoUrl: channel.logoUrl);
  }

  Future<void> _load() async {
    final storage = context.read<StorageService>();
    final leagues = [
      for (final id in storage.getSportsLeagues() ?? const <String>[])
        sportsLeagueById(id)
    ].whereType<SportsLeague>().toList();
    if (leagues.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final now = DateTime.now();
      // A conference and its Top 25 poll publish the same scoreboard row: one
      // game, one card, even though the leagues are both selected.
      final games = dedupeSportsEvents(
          await SportsService.instance.gamesForDay(leagues, now));
      if (!mounted) return;
      final redZone = _redZoneCard(leagues, now);
      // Finals stay: they are the end of the running order, not noise.
      final ordered = [
        if (redZone != null) redZone,
        ...games,
      ]
        ..sort((a, b) {
          int bucket(SportsGame g) => g.isLive
              ? 0
              : g.state == GameState.post
                  ? 2
                  : 1;
          final byBucket = bucket(a).compareTo(bucket(b));
          if (byBucket != 0) return byBucket;
          return bucket(a) == 2
              ? b.start.compareTo(a.start)
              : a.start.compareTo(b.start);
        });
      setState(() {
        _games = ordered;
        _loading = false;
        // Land on Live when there is something live to watch, then on the game
        // the viewer is already watching.
        _scope = ordered.any((g) => g.isLive) ? 0 : 1;
        _index = 0;
        _landOnWatched();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusCard(_index, _visible);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Scores could not be loaded.';
        });
      }
    }
  }

  List<_Scope> get _scopes {    final seen = <String>{};
    for (final game in _games) {
      seen.add(_Scope._sportOf(game));
    }
    final sports = seen.toList()
      ..sort((a, b) => sportLabel(a).compareTo(sportLabel(b)));
    return [
      const _Scope('LIVE', null, liveOnly: true),
      const _Scope('All', null, liveOnly: false),
      for (final sport in sports)
        _Scope(shortSportLabel(sport), sport, liveOnly: false),
    ];
  }

  _Scope get _current {
    final scopes = _scopes;
    return scopes[_scope.clamp(0, scopes.length - 1)];
  }

  /// Opening while watching a game should land on that game's card: the viewer
  /// already picked it, so walking the row back to it is noise. A class stands
  /// for a league, so a season-level stand-in can still find the same fixture.
  void _landOnWatched() {
    final watched = widget.watchingGame;
    if (watched == null) return;
    bool isWatched(SportsGame game) =>
        game.id == watched.id &&
        game.league.espnPath == watched.league.espnPath;
    if (!_games.any(isWatched)) return;
    final scope =
        _scopes.indexWhere((s) => _games.any((g) => isWatched(g) && s.accepts(g)));
    if (scope < 0) return;
    _scope = scope;
    final index = _visible.indexWhere(isWatched);
    if (index >= 0) _index = index;
  }

  List<SportsGame> get _visible {
    final scope = _current;
    return _games.where(scope.accepts).toList();
  }

  void _focusCard(int index, List<SportsGame> games) {
    if (games.isEmpty) return;
    final next = index.clamp(0, games.length - 1);
    setState(() => _index = next);
    while (_cards.length <= next) {
      _cards.add(FocusNode(debugLabel: 'scores-card-${_cards.length}'));
    }
    _cards[next].requestFocus();
    if (_scroll.hasClients) {
      final target = (next * _cardExtent) - 40;
      _scroll.animateTo(target.clamp(0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 140), curve: Curves.easeOut);
    }
  }

  void _changeScope(int delta) {
    final count = _scopes.length;
    var next = _scope;
    for (var step = 0; step < count; step++) {
      next = (next + delta) % count;
      if (next < 0) next += count;
      final scope = _scopes[next];
      if (_games.any(scope.accepts)) break;
    }
    setState(() {
      _scope = next;
      _index = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusCard(0, _visible);
    });
  }

  KeyEventResult _keys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final games = _visible;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _focusCard(_index + 1, games);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _focusCard(_index - 1, games);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (_scopes.length < 2) return KeyEventResult.ignored;
      _changeScope(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
      return KeyEventResult.handled;
    }
    if ([LogicalKeyboardKey.select, LogicalKeyboardKey.enter].contains(key)) {
      if (_index < games.length) widget.onPlay(games[_index]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _status(SportsGame game) {
    if (game.isLive) {
      return game.statusText.isEmpty ? 'LIVE' : game.statusText;
    }
    if (game.state == GameState.post) {
      return game.statusText.isEmpty ? 'Final' : game.statusText;
    }
    return TimeFormat.hm.format(game.start.toLocal());
  }

  Widget _teamRow(SportsGame game, SportsTeam side) {
    final label =
        side.abbreviation.isEmpty ? side.shortName : side.abbreviation;
    final rank = side.rankLabel;
    // Before kick-off a 0-0 is noise: the records are the useful line.
    final trailing = game.state == GameState.pre
        ? (side.record ?? '')
        : (side.score ?? '');
    return Row(children: [
      Expanded(
          child: Text(rank.isEmpty ? label : '$rank $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: interfaceColor(context, Colors.white)))),
      const SizedBox(width: 4),
      Text(trailing,
          style: TextStyle(
              fontSize: game.state == GameState.pre ? 10.5 : 12.5,
              fontWeight: game.state == GameState.pre
                  ? FontWeight.w400
                  : FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: interfaceColor(
                  context, game.state == GameState.pre ? Colors.white54 : Colors.white70))),
    ]);
  }

  Widget _card(SportsGame game, int index) {
    final muted = interfaceColor(context, Colors.white54);
    final tokens = SurfaceTokens.forStyle(
        context.watch<AppPreferences?>()?.surfaceStyle ??
            SurfaceStyle.classic);
    final focused = index < _cards.length && _cards[index].hasFocus;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        focusNode: _cards[index],
        borderRadius: BorderRadius.circular(
            tokens.isModern ? tokens.blockRadius : 4),
        onTap: () => widget.onPlay(game),
        onFocusChange: (hasFocus) {
          if (hasFocus) setState(() => _index = index);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: interfaceColor(context, Colors.white).withValues(alpha: .06),
            borderRadius: BorderRadius.circular(
                tokens.isModern ? tokens.blockRadius : 4),
            border: Border.all(
                color: focused
                    ? Theme.of(context).colorScheme.primary
                    : interfaceColor(context, Colors.white10)),
            boxShadow: focused && tokens.focusGlowBlur > 0
                ? [
                    BoxShadow(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: tokens.focusGlowAlpha),
                        blurRadius: tokens.focusGlowBlur)
                  ]
                : const [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(children: [
                // Football and basketball share league names (SEC, Big Ten), so
                // the sport icon is what tells two concurrent rows apart.
                Icon(sportIcon(_Scope._sportOf(game)), size: 11, color: muted),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(game.league.shortName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 9, letterSpacing: .6, color: muted))),
                Text(_status(game),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: game.isLive
                            ? interfaceColor(context, Colors.redAccent)
                            : muted)),
              ]),
              const SizedBox(height: 4),
              for (final side in [game.first, game.second]) _teamRow(game, side),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scopeChip(_Scope scope, int index, Color muted) {
    final selected = index == _scope;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: .22)
                : Colors.transparent),
        child: Text(scope.label,
            style: TextStyle(
                fontSize: 10.5, color: selected ? Colors.white : muted)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = interfaceColor(context, Colors.white54);
    final tokens = SurfaceTokens.forStyle(
        context.watch<AppPreferences?>()?.surfaceStyle ??
            SurfaceStyle.classic);
    final games = _visible;
    final scopes = _scopes;
    final emptyMessage = _current.liveOnly
        ? 'Nothing live right now · Down for all today’s games.'
        : 'No games on now or next.';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onClose();
      },
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.focusNode == null,
        onKeyEvent: _keys,
        child: Container(
          key: const ValueKey('player-scores-panel'),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .82),
            borderRadius: BorderRadius.circular(
                tokens.isModern ? tokens.rowRadius : 6),
            border: Border.all(
                color: interfaceColor(context, Colors.white24), width: 1),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Text('SCORES',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: muted)),
              const SizedBox(width: 12),
              for (var i = 0; i < scopes.length; i++)
                _scopeChip(scopes[i], i, muted),
              const Spacer(),
              Text(_loading ? 'Loading…' : '${games.length}',
                  style: TextStyle(fontSize: 10.5, color: muted)),
              const SizedBox(width: 10),
              Text('Back closes',
                  style: TextStyle(
                      fontSize: 10, color: muted.withValues(alpha: .8))),
            ]),
            const SizedBox(height: 8),
            if (games.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(_error ?? (_loading ? '' : emptyMessage),
                    style: TextStyle(fontSize: 11.5, color: muted)),
              )
            else
              SizedBox(
                height: 76,
                child: ListView.builder(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  itemExtent: _cardExtent,
                  itemCount: games.length,
                  itemBuilder: (context, index) {
                    while (_cards.length <= index) {
                      _cards.add(
                          FocusNode(debugLabel: 'scores-card-$index'));
                    }
                    return _card(games[index], index);
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
