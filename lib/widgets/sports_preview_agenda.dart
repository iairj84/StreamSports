import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../models/sports.dart';
import '../utils/interface_colors.dart';
import '../utils/time_format.dart';

/// One game in the preview column's running order.
class SportsAgendaEntry {
  const SportsAgendaEntry({required this.game, this.channel});

  final SportsGame game;

  /// The channel this build would play, if one is matched.
  final Channel? channel;

  bool get live => game.isLive;
}

/// The chronological answer the per-sport rows cannot give: what is on now and
/// what starts next, and whether it is on a channel this playlist carries.
///
/// It fills the preview column without adding another request: every value is
/// already in the loaded fixtures and their channel matches.
class SportsPreviewAgenda extends StatelessWidget {
  const SportsPreviewAgenda(
      {super.key, required this.entries, required this.now});

  final List<SportsAgendaEntry> entries;
  final DateTime now;

  String _time(SportsAgendaEntry entry) {
    if (entry.live) return 'LIVE';
    final start = entry.game.start.toLocal();
    final sameDay = start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
    return sameDay
        ? TimeFormat.hm.format(start)
        : '${start.day}/${start.month}';
  }

  String _matchup(SportsGame game) {
    String side(SportsTeam team) =>
        team.abbreviation.isEmpty ? team.shortName : team.abbreviation;
    return '${side(game.first)} @ ${side(game.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = interfaceColor(context, Colors.white54);
    return Column(
      key: const ValueKey('sports-preview-agenda'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Text('NEXT UP',
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: muted)),
          const Spacer(),
          Text('${entries.length}',
              style: TextStyle(fontSize: 10, color: muted)),
        ]),
        const SizedBox(height: 5),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              SizedBox(
                  width: 34,
                  child: Text(_time(entry),
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              entry.live ? FontWeight.w800 : FontWeight.w500,
                          color: entry.live
                              ? interfaceColor(context, Colors.redAccent)
                              : muted))),
              Expanded(
                  child: Text(_matchup(entry.game),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: interfaceColor(context, Colors.white70)))),
              const SizedBox(width: 6),
              ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 96),
                  child: Text(entry.channel?.name ?? 'No channel',
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10,
                          color: entry.channel == null
                              ? interfaceColor(context, Colors.white38)
                              : colors.primary))),
            ]),
          ),
      ],
    );
  }
}
