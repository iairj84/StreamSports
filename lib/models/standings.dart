import 'sports.dart';

/// One club's row in a table: its identity, its published statistics, the
/// position the source published (null when it published none) and the labels
/// for the stat columns.
///
/// These live with the other sports value types rather than in the standings
/// service so the per-league parsers — which are called *by* that service —
/// can describe their output without importing the service that calls them.
class StandingTeam {
  const StandingTeam(this.team, this.stats, this.position,
      {this.statLabels = const {}, this.nameAliases = const {}});
  final SportsTeam team;
  final Map<String, String> stats;
  final int? position;
  final Map<String, String> statLabels;
  final Set<String> nameAliases;
}

class StandingTable {
  const StandingTable(this.name, this.rows);
  final String name;
  final List<StandingTeam> rows;
}

class LeagueStandings {
  const LeagueStandings(
      {this.tables = const [],
      this.season,
      this.previousSeason,
      this.directory = false,
      this.failed = false,
      this.fallbackYear,
      this.fallbackIsPreviousSeason = true,
      this.rankings = false,
      this.rankingTitle,
      this.sourceName,
      this.updatedAt});
  final List<StandingTable> tables;
  final String? season;
  final bool? previousSeason;
  final bool directory, failed;
  final int? fallbackYear;
  final bool fallbackIsPreviousSeason;
  final bool rankings;
  final String? rankingTitle;
  final String? sourceName;
  final DateTime? updatedAt;
  bool get hasRows => tables.any((table) => table.rows.isNotEmpty);

  LeagueStandings withRefreshFailure() => LeagueStandings(
      tables: tables,
      season: season,
      previousSeason: previousSeason,
      directory: directory,
      failed: true,
      fallbackYear: fallbackYear,
      fallbackIsPreviousSeason: fallbackIsPreviousSeason,
      rankings: rankings,
      rankingTitle: rankingTitle,
      sourceName: sourceName,
      updatedAt: updatedAt);
}
