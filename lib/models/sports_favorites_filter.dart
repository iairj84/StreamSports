/// Result scope is independent of saved favorites and sport/date filters.
enum SportsFavoritesFilter {
  all,
  favorites,
  leagues,
  teams;

  bool get isFiltered => this != all;
  bool get includesLeagues => this == favorites || this == leagues;
  bool get includesTeams => this == favorites || this == teams;

  String get label => switch (this) {
        all => 'All',
        favorites => 'Favorites',
        leagues => 'Favorite leagues',
        teams => 'Favorite teams & athletes',
      };

  String get description => switch (this) {
        all => 'All results, whether saved as favorites or not',
        favorites => 'Your leagues, teams and athletes together',
        leagues => 'All results from your favorite leagues',
        teams => 'Only your favorite teams and athletes, in any league',
      };

  String get shortLabel => switch (this) {
        all => 'All',
        favorites => 'Favorites',
        leagues => 'Leagues',
        teams => 'Teams',
      };

  String? emptySelectionMessage(
      {required bool hasLeagues, required bool hasTeams}) {
    if (!isFiltered ||
        (includesLeagues && hasLeagues) ||
        (includesTeams && hasTeams)) {
      return null;
    }
    return switch (this) {
      leagues => 'No favorite leagues yet',
      teams => 'No favorite teams or athletes yet',
      _ => 'No favorites yet',
    };
  }
}
