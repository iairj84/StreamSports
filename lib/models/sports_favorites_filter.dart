/// Result scope is independent of the leagues shown in Sports.
enum SportsFavoritesFilter {
  all,
  favorites;

  bool get isFiltered => this != all;

  String get label => switch (this) {
        all => 'All',
        favorites => 'Favorites',
      };

  String get description => switch (this) {
        all => 'All results, whether saved as favorites or not',
        favorites => 'Your favorite teams and athletes',
      };

  String get shortLabel => label;

  String? emptySelectionMessage({required bool hasTeams}) =>
      isFiltered && !hasTeams ? 'No favorite teams or athletes yet' : null;
}
