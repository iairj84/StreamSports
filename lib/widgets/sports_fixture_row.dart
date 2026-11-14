import 'package:flutter/material.dart';
import '../models/sports.dart';
import '../utils/sports_detail_presentation.dart';
import '../utils/sports_fixture_presentation.dart';
import '../utils/sports_odds_presentation.dart';
import 'sports_widgets.dart';
import 'sports_filter_picker.dart' show sportLabel, shortSportLabel;

/// Uses only the fixture snapshot; browsing never requests match details.
class SportsFixtureRow extends StatelessWidget {
  const SportsFixtureRow(
      {super.key,
      required this.game,
      required this.time,
      required this.hideScores,
      required this.use24h,
      this.favorite = false,
      this.showLeague = false,
      this.showSport = false,
      this.channelName,
      this.possibleChannel = false,
      this.showOdds = true,
      this.onDetails});
  final SportsGame game;
  final String time;
  final bool hideScores, use24h, showLeague, showSport;
  final bool favorite;
  final String? channelName;
  final bool possibleChannel;

  /// Sports options: the book's line, drawn between the matchup and the
  /// channel so it never moves those two apart.
  final bool showOdds;
  final VoidCallback? onDetails;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final showScore = !hideScores && game.state != GameState.pre;
    final insight = sportsFixtureInsight(game, hideScores: hideScores);
    final possessionId =
        game.isLive ? game.situation?.possessionTeamId : null;
    Widget team(SportsTeam side) => Row(children: [
          ExcludeSemantics(
              child: SportsLogo(
                  url: side.logoUrl,
                  size: 18,
                  fallback: side.abbreviation.isEmpty
                      ? side.shortName
                      : side.abbreviation,
                  color: side.color,
                  animate: false)),
          const SizedBox(width: 6),
          Expanded(
              child: Text(
                  side.rankLabel.isEmpty
                      ? (side.name.isEmpty ? side.shortName : side.name)
                      : '${side.rankLabel} '
                          '${side.name.isEmpty ? side.shortName : side.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.25))),
          if (showScore &&
              possessionId != null &&
              possessionId == side.id)
            ExcludeSemantics(
                child: Tooltip(
                    message: 'Possession',
                    child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(Icons.circle,
                            size: 7, color: colors.primary)))),
          const SizedBox(width: 8),
          Text(
              showScore
                  ? side.score ?? '–'
                  : hideScores
                      ? ''
                      : side.record ?? '',
              style: TextStyle(
                  fontSize: showScore ? 13 : 10,
                  fontWeight: showScore ? FontWeight.w600 : FontWeight.w400,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color:
                      showScore ? colors.onSurface : colors.onSurfaceVariant)),
        ]);
    final oddsLine = showOdds ? sportsOddsLine(game.odds) : null;
    final status = game.isLive ? 'LIVE' : sportsFixtureStatus(game);
    // Live cards show who has the ball and the spot: football down &
    // distance ("2nd & 7 at NE 32"), baseball count/outs/runners.
    // Gated by hideScores so spoiler mode stays clean.
    final progress =
        game.isLive && !hideScores ? sportsLiveProgress(game) : null;
    final sport = showSport ? game.league.espnPath.split('/').first : null;
    return Row(children: [
      SizedBox(
          width: (showSport
                  ? 64.0
                  : use24h
                      ? 42.0
                      : 62.0) *
              MediaQuery.textScalerOf(context).scale(11) /
              11,
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(time,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.15,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: colors.onSurface)),
                if (sport != null)
                  Tooltip(
                      message: sportLabel(sport),
                      child: Text(shortSportLabel(sport),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 9,
                              height: 1.15,
                              color: colors.onSurfaceVariant))),
                if (showLeague)
                  Tooltip(
                      message: game.league.name,
                      child: Text(game.league.shortName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 9,
                              height: 1.15,
                              color: colors.onSurfaceVariant))),
                if (status != 'Scheduled')
                  Text(status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 9,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                          color: game.isLive
                              ? colors.primary
                              : colors.onSurfaceVariant)),
                if (!showLeague &&
                    progress != null &&
                    progress.isNotEmpty &&
                    progress.toUpperCase() != 'LIVE')
                  Text(progress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 9,
                          height: 1.15,
                          color: colors.onSurfaceVariant)),
              ])),
      Container(
          width: 1,
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          color: colors.outlineVariant.withValues(alpha: .45)),
      Expanded(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            if (!game.league.isField) ...[
              team(game.first),
              const SizedBox(height: 2),
              team(game.second)
            ] else ...[
              Text(game.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, height: 1.2)),
              if (insight != null)
                Text(insight,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10.5,
                        height: 1.2,
                        color: colors.onSurfaceVariant)),
            ],
            if (oddsLine != null)
              Text(oddsLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant)),
            if (channelName != null)
              Tooltip(
                  message: '${possibleChannel ? 'Possible channel' : 'Watch'}: '
                      '$channelName · Select to watch, hold for game details',
                  child: Row(children: [
                    Icon(Icons.play_arrow,
                        size: 12,
                        color: possibleChannel
                            ? colors.onSurfaceVariant
                            : colors.primary),
                    const SizedBox(width: 3),
                    Expanded(
                        child: Text(
                            '${possibleChannel ? 'Possible · ' : ''}$channelName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10,
                                height: 1.2,
                                color: possibleChannel
                                    ? colors.onSurfaceVariant
                                    : colors.primary))),
                  ])),
          ])),
      const SizedBox(width: 6),
      if (favorite)
        Tooltip(
            message: 'Favorite team',
            child: Icon(Icons.star, size: 15, color: colors.primary)),
      if (onDetails != null)
        ExcludeFocus(
            child: IconButton(
                key: ValueKey('fixture-details-${game.league.id}:${game.id}'),
                tooltip: 'Game details · hold to open',
                onPressed: onDetails,
                style: IconButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(28, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                icon: Icon(Icons.info_outline,
                    size: 17, color: colors.onSurfaceVariant)))
      else if (!favorite)
        Icon(Icons.chevron_right, size: 15, color: colors.onSurfaceVariant),
    ]);
  }
}
