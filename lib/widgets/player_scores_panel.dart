import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/sports.dart';
import '../services/sports_service.dart';
import '../services/storage_service.dart';
import '../utils/interface_colors.dart';
import '../utils/time_format.dart';
import 'sports_filter_picker.dart';

/// Scores while watching.
///
/// Loads the day's fixtures the viewer already follows, keeps what is live or
/// about to start, and shows them as one row of cards. Left/Right walks the
/// games, Up/Down changes sport, OK hands the game back to the player so it can
/// tune the matched channel.
class PlayerScoresPanel extends StatefulWidget {
  const PlayerScoresPanel(
      {super.key, required this.onClose, required this.onPlay});

  final VoidCallback onClose;
  final ValueChanged<SportsGame> onPlay;

  @override
  State<PlayerScoresPanel> createState() => _PlayerScoresPanelState();
}

class _PlayerScoresPanelState extends State<PlayerScoresPanel> {
  final _cards = <FocusNode>[];
  final _scroll = ScrollController();
  List<SportsGame> _games = const [];
  String? _sport;
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
      final games =
          await SportsService.instance.gamesForDay(leagues, DateTime.now());
      if (!mounted) return;
      final tonight = games.where((g) => g.state != GameState.post).toList()
        ..sort((a, b) => a.isLive == b.isLive
            ? a.start.compareTo(b.start)
            : (a.isLive ? -1 : 1));
      setState(() {
        _games = tonight;
        _loading = false;
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

  List<String> get _sports {
    final seen = <String>{};
    for (final game in _games) {
      seen.add(game.league.espnPath.split('/').first);
    }
    return seen.toList();
  }

  List<SportsGame> get _visible => _sport == null
      ? _games
      : _games
          .where((g) => g.league.espnPath.split('/').first == _sport)
          .toList();

  void _focusCard(int index, List<SportsGame> games) {
    if (games.isEmpty) return;
    final next = index.clamp(0, games.length - 1);
    setState(() => _index = next);
    if (_cards.length <= next) {
      _cards.add(FocusNode(debugLabel: 'scores-card-$next'));
    }
    _cards[next].requestFocus();
    if (_scroll.hasClients) {
      final target = (next * 212.0) - 40;
      _scroll.animateTo(target.clamp(0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 140), curve: Curves.easeOut);
    }
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
      final sports = _sports;
      if (sports.length < 2) return KeyEventResult.ignored;
      final current = _sport == null ? -1 : sports.indexOf(_sport!);
      final next = key == LogicalKeyboardKey.arrowDown
          ? (current + 2) % (sports.length + 1) - 1
          : (current < 0 ? sports.length - 1 : current - 1);
      setState(() {
        _sport = next < 0 ? null : sports[next];
        _index = 0;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusCard(0, _visible);
      });
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
    return TimeFormat.hm.format(game.start.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final muted = interfaceColor(context, Colors.white54);
    final games = _visible;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onClose();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _keys,
        child: Container(
          key: const ValueKey('player-scores-panel'),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .82),
            borderRadius: BorderRadius.circular(6),
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
              for (final sport in [null, ..._sports])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: _sport == sport
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: .22)
                            : Colors.transparent),
                    child: Text(sport == null ? 'All' : sportLabel(sport),
                        style: TextStyle(
                            fontSize: 10.5,
                            color: _sport == sport ? Colors.white : muted)),
                  ),
                ),
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
                child: Text(
                    _error ?? (_loading ? '' : 'No games on now or next.'),
                    style: TextStyle(fontSize: 11.5, color: muted)),
              )
            else
              SizedBox(
                height: 74,
                child: ListView.builder(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  itemExtent: 212,
                  itemCount: games.length,
                  itemBuilder: (context, index) {
                    final game = games[index];
                    while (_cards.length <= index) {
                      _cards.add(FocusNode(debugLabel: 'scores-card-$index'));
                    }
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        focusNode: _cards[index],
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => widget.onPlay(game),
                        onFocusChange: (focused) {
                          if (focused) setState(() => _index = index);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 6),
                          decoration: BoxDecoration(
                            color: interfaceColor(context, Colors.white)
                                .withValues(alpha: .06),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: _index == index && _cards[index].hasFocus
                                    ? Theme.of(context).colorScheme.primary
                                    : interfaceColor(context, Colors.white10)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(children: [
                                Expanded(
                                    child: Text(
                                        game.league.shortName.toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 9,
                                            letterSpacing: .6,
                                            color: muted))),
                                Text(_status(game),
                                    style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: game.isLive
                                            ? interfaceColor(
                                                context, Colors.redAccent)
                                            : muted)),
                              ]),
                              const SizedBox(height: 4),
                              for (final side in [game.first, game.second])
                                Row(children: [
                                  Expanded(
                                      child: Text(
                                          side.abbreviation.isEmpty
                                              ? side.shortName
                                              : side.abbreviation,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: interfaceColor(
                                                  context, Colors.white)))),
                                  Text(side.score ?? '',
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: interfaceColor(
                                              context, Colors.white70))),
                                ]),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
