import 'package:flutter/material.dart';

import '../models/sports.dart';
import '../utils/interface_colors.dart';
import '../utils/sports_detail_presentation.dart';
import '../utils/sports_odds_presentation.dart';

/// The one line about the focused game worth reading before you switch.
///
/// Deliberately not a box score: the score feed already carries the live
/// situation ("3rd & 4 at KC 32"), the leading player, or both records before
/// kick-off. Duplicating provider stat rows here cost a request and told a
/// viewer nothing they could act on.
class SportsHeroDetails extends StatelessWidget {
  const SportsHeroDetails(
      {super.key,
      required this.game,
      required this.hideScores,
      this.showOdds = true});

  final SportsGame game;
  final bool hideScores;

  /// Sports options: whether the book's line belongs here.
  final bool showOdds;

  @override
  Widget build(BuildContext context) {
    final insight = sportsFixtureInsight(game, hideScores: hideScores);
    final hasInsight = insight != null && insight.isNotEmpty;
    final line = showOdds ? sportsOddsLine(game.odds) : null;
    final moneyLine = showOdds ? sportsOddsMoneyLine(game.odds, game) : null;
    if (!hasInsight && line == null && moneyLine == null) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('sports-preview-details'),
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
          border: Border(
              top: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: .35)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (hasInsight)
          Text(insight,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: interfaceColor(context, const Color(0xFFEAF0F6)))),
        if (line != null || moneyLine != null)
          Padding(
              padding: EdgeInsets.only(top: hasInsight ? 3 : 0),
              child: Text(
                  [
                    if (game.odds?.provider.isNotEmpty == true)
                      game.odds!.provider,
                    if (line != null) line,
                    if (moneyLine != null) 'ML $moneyLine',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10.5,
                      height: 1.3,
                      color: interfaceColor(context, Colors.white54)))),
      ]),
    );
  }
}
