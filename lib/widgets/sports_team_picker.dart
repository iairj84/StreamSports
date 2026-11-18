import 'dart:async';
import 'package:flutter/material.dart';
import '../models/sports.dart';
import '../services/sports_follows.dart';
import '../services/sports_standings_service.dart';
import '../utils/guarded_dialog.dart';
import '../widgets/compact_choice_list.dart';
import '../widgets/shown_mark.dart';
import '../widgets/sports_widgets.dart';

/// Every team a league's table or directory knows about, so a team can be
/// followed without first finding it in a Standings table.
class SportsTeamPicker extends StatefulWidget {
  const SportsTeamPicker(
      {super.key,
      required this.league,
      required this.follows,
      this.standings});
  final SportsLeague league;
  final SportsFollows follows;
  final SportsStandingsService? standings;
  @override
  State<SportsTeamPicker> createState() => _SportsTeamPickerState();
}

class _SportsTeamPickerState extends State<SportsTeamPicker> {
  late final _service = widget.standings ?? SportsStandingsService.instance;
  final _closeFocus = FocusNode(debugLabel: 'team-picker-close');
  List<SportsTeam>? _teams;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _closeFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<SportsTeam> teams = const [];
    try {
      var data =
          await _service.load(widget.league, rememberSelection: false);
      // Knockouts and international fixtures publish no league table; their
      // team directory still lists every selectable team.
      if (!data.hasRows) {
        final directory = await _service.teamDirectory(widget.league);
        if (directory.hasRows) data = directory;
      }
      teams = {
        for (final table in data.tables)
          for (final row in table.rows) row.team.id: row.team
      }.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (_) {
      teams = const [];
    }
    if (!mounted) return;
    setState(() {
      _teams = teams;
      _loading = false;
    });
  }

  Future<void> _toggle(SportsTeam team) async {
    if (_saving) return;
    _saving = true;
    final following = widget.follows.isFollowed(widget.league.id, team.id);
    try {
      if (following) {
        await widget.follows.unfollow(widget.league.id, team.id);
      } else {
        await widget.follows.follow(widget.league.id, team.id,
            name: team.name, logoUrl: team.logoUrl);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save that team.')));
      }
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final teams = _teams;
    final choices = [
      for (final team in teams ?? const <SportsTeam>[])
        CompactChoice(
          id: team.id,
          title: team.name,
          subtitle: team.shortName == team.name ? null : team.shortName,
          leading: SportsLogo(
              url: team.logoUrl,
              size: 24,
              fallback: team.name,
              animate: false),
          trailing: ShownMark(
              shown: widget.follows.isFollowed(widget.league.id, team.id),
              shownLabel: 'Following',
              hiddenLabel: 'Not following'),
          onTap: () => _toggle(team),
        )
    ];
    return Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
              height: 40,
              child: Row(children: [
                Expanded(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(widget.league.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(
                          teams == null
                              ? 'Loading teams…'
                              : '${teams.length} teams · tap to follow or unfollow',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10, color: colors.onSurfaceVariant)),
                    ])),
                IconButton(
                    key: const ValueKey('close-team-picker'),
                    focusNode: _closeFocus,
                    tooltip: 'Close',
                    style: IconButton.styleFrom(
                        minimumSize: const Size(34, 34),
                        maximumSize: const Size(34, 34),
                        padding: EdgeInsets.zero),
                    onPressed: () => popRouteIfCurrent(context, null),
                    icon: const Icon(Icons.close, size: 20)),
              ])),
          const SizedBox(height: 6),
          Expanded(
              child: choices.isEmpty
                  ? Center(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                              _loading
                                  ? 'Loading teams…'
                                  : 'No teams listed for this league.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12))))
                  : CompactChoiceList(
                      choices: choices,
                      polished: true,
                      striped: true,
                      rowHeight: 44,
                      onExitUp: _closeFocus.requestFocus,
                    )),
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('OK: follow or unfollow',
                  style: TextStyle(
                      fontSize: 10, color: colors.onSurfaceVariant))),
        ]));
  }
}
