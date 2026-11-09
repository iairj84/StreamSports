import '../models/sports.dart';

/// The line as it is read aloud: "BUF -3.5 · O/U 45.5".
///
/// [SportsOdds.details] is the book's own wording, so a sport whose handicap
/// is goals or runs still reads correctly; the total is added only when the
/// book published one.
String? sportsOddsLine(SportsOdds? odds) {
  if (odds == null) return null;
  final total = odds.overUnder;
  final parts = <String>[
    if (odds.details.isNotEmpty) odds.details,
    if (total != null) 'O/U ${sportsOddsNumber(total)}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// "BUF -175 · MIN +150" (with "Draw +450" where the book prices one), in
/// the order the sides appear on screen.
String? sportsOddsMoneyLine(SportsOdds? odds, SportsGame game) {
  if (odds == null) return null;
  String side(SportsTeam team, String line) {
    final name = team.abbreviation.isNotEmpty
        ? team.abbreviation
        : (team.shortName.isNotEmpty ? team.shortName : team.name);
    return '$name $line';
  }

  final parts = <String>[
    if (odds.homeMoneyLine case final line?) side(game.home, line),
    if (odds.awayMoneyLine case final line?) side(game.away, line),
    if (odds.drawMoneyLine case final line?) 'Draw $line',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Whole numbers read without a trailing ".0" (45, not 45.0).
String sportsOddsNumber(double value) =>
    value == value.roundToDouble() ? value.round().toString() : '$value';
