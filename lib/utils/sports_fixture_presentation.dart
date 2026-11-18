import '../models/sports.dart';

final _unknownTime =
    RegExp(r'\b(TBD|TBA)\b|to be (determined|announced)', caseSensitive: false);
final _changedFixture =
    RegExp(r'postpon|cancel|suspend|delay', caseSensitive: false);

bool sportsFixtureHasUnknownTime(SportsGame game) =>
    _unknownTime.hasMatch(game.statusText);

/// Ordinary pregame provider strings often contain a foreign timezone. Views
/// render the local kickoff separately while retaining meaningful exceptions.
String sportsFixtureStatus(SportsGame game) =>
    game.state != GameState.pre || _changedFixture.hasMatch(game.statusText)
        ? game.statusText
        : sportsFixtureHasUnknownTime(game)
            ? 'Time to be confirmed'
            : 'Scheduled';

/// Live line combining the clock with who has the ball and the spot:
/// football down & distance ("2nd & 7 at NE 32"), baseball count/outs.
String sportsLiveProgress(SportsGame game) {
  final base = sportsFixtureStatus(game);
  final sit = game.situation?.text;
  if (sit == null || sit.isEmpty || base.contains(sit)) return base;
  if (base.isEmpty) return sit;
  return '$base · $sit';
}

/// A delayed or cancelled fixture is not a completed result.
bool sportsFixtureCompleted(SportsGame game) =>
    game.state == GameState.post && !_changedFixture.hasMatch(game.statusText);

/// One spoiler gate for every score view: hide everything, or hide only games
/// involving a followed team. `involves` is the viewer's follows check, so
/// callers with no follows pass `(game) => false`.
bool sportsShouldHideScore(
  SportsGame? game, {
  required bool hideAll,
  required bool hideMyTeams,
  required bool Function(SportsGame) involves,
}) {
  if (hideAll) return true;
  if (!hideMyTeams || game == null) return false;
  return involves(game);
}
