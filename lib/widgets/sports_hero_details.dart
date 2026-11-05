import 'dart:async';

import 'package:flutter/material.dart';

import '../models/sports.dart';
import '../models/sports_details.dart';
import '../services/sports_details_service.dart';
import '../utils/interface_colors.dart';
import '../utils/sports_detail_presentation.dart';

/// What the preview column knows about the focused game.
///
/// The panel Schedule opens already shows this data, one bounded provider
/// request per game. Here the same snapshot is reduced to the lines that fit
/// beside the preview: the fixture insight the score feed already carries, a
/// few key statistics and the leading players. Sports and games the provider
/// does not cover say so instead of leaving the column blank.
class SportsHeroDetails extends StatefulWidget {
  const SportsHeroDetails(
      {super.key, required this.game, required this.hideScores});

  final SportsGame game;
  final bool hideScores;

  @override
  State<SportsHeroDetails> createState() => _SportsHeroDetailsState();
}

class _SportsHeroDetailsState extends State<SportsHeroDetails> {
  SportsDetails? _data;
  String? _key;
  bool _loading = false;
  Timer? _debounce;

  static String _keyFor(SportsGame game) =>
      '${game.source}|${game.league.espnPath}|${game.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(SportsHeroDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_keyFor(oldWidget.game) != _keyFor(widget.game)) _load();
  }

  void _load() {
    final key = _keyFor(widget.game);
    _key = key;
    setState(() => _loading = true);
    // Focus passes over many cards on the way to one; only a game that stays
    // focused asks the provider for anything.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      final data = await SportsDetailsService.instance.game(widget.game);
      if (!mounted || _key != key) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    });
  }

  List<Widget> _rows(BuildContext context, SportsDetails data) {
    if (widget.hideScores) return const [];
    final league = widget.game.league;
    final comparison = data.sections
        .where((s) => s.kind == SportsDetailKind.comparison)
        .firstOrNull;
    final players = data.sections.where(sportsPlayerSection).firstOrNull;
    final rows = <Widget>[];
    Widget line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10.5,
                      color: interfaceColor(context, Colors.white54)))),
          const SizedBox(width: 6),
          Text(value,
              maxLines: 1,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: interfaceColor(context, Colors.white70))),
        ]));
    for (final row in sportsKeyStatistics(league, comparison!).take(3)) {
      final value = row.values.where((v) => v.isNotEmpty).join(' · ');
      if (value.isNotEmpty) rows.add(line(row.label, value));
    }
    for (final row in (players?.rows ?? const <SportsDetailRow>[]).take(2)) {
      final value = row.values.where((v) => v.isNotEmpty).join(' · ');
      if (value.isNotEmpty) rows.add(line(row.label, value));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final insight =
        sportsFixtureInsight(widget.game, hideScores: widget.hideScores);
    final data = _data;
    final rows = data == null ? const <Widget>[] : _rows(context, data);
    final String? note = data == null
        ? (_loading ? 'Loading details…' : null)
        : data.unsupported
            ? (data.message ?? 'Details are not available for this game.')
            : data.failed
                ? (data.message ?? 'Details are unavailable right now.')
                : rows.isEmpty
                    ? 'No extra details for this game.'
                    : null;
    if (insight == null && rows.isEmpty && note == null) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const ValueKey('sports-preview-details'),
      padding: const EdgeInsets.only(top: 9),
      decoration: BoxDecoration(
          border: Border(
              top: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: .35)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (insight != null) ...[
            Text(insight,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: interfaceColor(context, const Color(0xFFEAF0F6)))),
            if (rows.isNotEmpty || note != null) const SizedBox(height: 6),
          ],
          ...rows,
          if (note != null)
            Text(note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5,
                    height: 1.3,
                    color: interfaceColor(context, Colors.white54))),
        ],
      ),
    );
  }
}
