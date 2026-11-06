import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sports.dart';
import '../services/storage_service.dart';
import '../services/app_preferences.dart';
import '../services/sports_service.dart';
import '../utils/guarded_dialog.dart';
import '../utils/tv_theme.dart';
import '../utils/sports_presentation.dart';
import '../widgets/settings_scaffold.dart';
import '../widgets/sports_widgets.dart';
import '../widgets/sports_header_controls.dart';
import '../widgets/sports_filter_picker.dart'
    show sportLabel, sportIcon, sportsManageLeaguesLabel;
import '../widgets/compact_choice_list.dart';
import '../widgets/tv_text_field_gate.dart';

/// One list with two explicit states: tapping a league includes or excludes it
/// from Sports, and the star saves it for the Favorites filter. A league can be
/// in Sports without being starred; a star always stays inside Sports.
class SportsLeagueManagerScreen extends StatefulWidget {
  const SportsLeagueManagerScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<SportsLeagueManagerScreen> createState() =>
      _SportsLeagueManagerScreenState();
}

class _SportsLeagueManagerScreenState extends State<SportsLeagueManagerScreen> {
  late final StorageService _storage = context.read<StorageService>();
  late Set<String> _included;
  late Set<String> _favorites;
  late String? _opening = _storage.getSportsFavoriteLeague();
  late Set<String> _savedIncluded;
  late Set<String> _savedFavorites;
  String? _savedOpening;
  bool _changed = false, _saving = false;
  Future<void>? _pendingSave;
  bool _closing = false;
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'leagues-search');
  final _closeFocus = FocusNode(debugLabel: 'leagues-close');
  final _allFocus = FocusNode(debugLabel: 'leagues-enable-all');
  final _scroll = ScrollController();
  String _query = '';
  String? _sport;
  late List<SportsLeague> _visibleLeagues;
  late final _searchText = {
    for (final l in _leagues)
      l.id:
          '${l.name} ${l.shortName} ${leagueDescription(l)} ${l.region ?? ''} ${_groupOf(l)}'
              .toLowerCase()
  };
  static final _availableIds = {
    for (final l in [...kSportsLeagues, ...kSportsLeagueBank]) l.id
  };
  bool get _allIncluded => _availableIds.every(_included.contains);

  void _filter() {
    final terms =
        _query.toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    _visibleLeagues = _leagues
        .where((l) =>
            (_sport == null || _sportOf(l) == _sport) &&
            terms.every(_searchText[l.id]!.contains))
        .toList();
  }

  void _changeFilter(VoidCallback change) {
    setState(() {
      change();
      _filter();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void initState() {
    super.initState();
    _included = savedSportsLeagues(_storage).map((l) => l.id).toSet();
    _favorites = savedSportsFavoriteLeagueIds(_storage)
      ..retainWhere(_included.contains);
    _savedIncluded = Set.of(_included);
    _savedFavorites = Set.of(_favorites);
    _savedOpening = _opening;
    _filter();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _closeFocus.dispose();
    _allFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _sportOf(SportsLeague league) => league.espnPath.split('/').first;
  String _groupOf(SportsLeague league) => sportLabel(_sportOf(league));

  late final List<SportsLeague> _leagues = _orderedLeagues();

  List<SportsLeague> _orderedLeagues() {
    final groups = <String, List<SportsLeague>>{};
    final leagues = {
      for (final l in [...kSportsLeagues, ...kSportsLeagueBank]) l.id: l
    }.values.toList();
    final order = {for (final (i, league) in leagues.indexed) league.id: i};
    for (final league in leagues) {
      (groups[_groupOf(league)] ??= []).add(league);
    }
    for (final group in groups.values) {
      group.sort((a, b) {
        final priority =
            leagueDisplayPriority(a).compareTo(leagueDisplayPriority(b));
        return priority != 0 ? priority : order[a.id]!.compareTo(order[b.id]!);
      });
    }
    return groups.values.expand((group) => group).toList();
  }

  Future<void> _persist(
      Set<String> included, Set<String> favorites, String? opening) async {
    await _storage.setSportsLeagues(included.toList());
    await _storage.setHiddenGuideLeagues([
      for (final l in kAutomaticSportsLeagues)
        if (!included.contains(l.id)) l.id,
    ]);
    await _storage.setSportsFavoriteLeagues([
      for (final l in _leagues)
        if (favorites.contains(l.id)) l.id,
    ]);
    await _storage.setSportsFavoriteLeague(opening);
    await _storage.setSportsAllLeagues(_availableIds.every(included.contains));
  }

  Future<void> _apply(
      Set<String> included, Set<String> favorites, String? opening) async {
    // A star outside Sports would leave the Favorites filter with nothing to
    // show, so excluding a league clears its star with it.
    favorites = {...favorites}..retainWhere(included.contains);
    if (_saving || _closing) return;
    final unchanged = included.length == _included.length &&
        included.containsAll(_included) &&
        favorites.length == _favorites.length &&
        favorites.containsAll(_favorites) &&
        opening == _opening;
    if (unchanged) return;
    if (included.isEmpty) {
      // Empty is an editing step, never a persisted selection: the loader
      // treats an empty saved set as the default catalogue.
      setState(() {
        _included = included;
        _favorites = favorites;
        _opening = opening;
        _filter();
      });
      return;
    }
    final previous = Set<String>.of(_included),
        previousFavorites = Set<String>.of(_favorites),
        previousOpening = _opening;
    setState(() {
      _saving = true;
      _included = included;
      _favorites = favorites;
      _opening = opening;
      _filter();
    });
    final complete = Completer<void>();
    _pendingSave = complete.future;
    try {
      await _persist(included, favorites, opening);
      _savedIncluded = Set.of(included);
      _savedFavorites = Set.of(favorites);
      _savedOpening = opening;
      _changed = true;
    } catch (_) {
      // Restore both the local view and any preference writes completed before failure.
      try {
        await _persist(_savedIncluded, _savedFavorites, _savedOpening);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _included = previous;
          _favorites = previousFavorites;
          _opening = previousOpening;
          _filter();
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save leagues. Please try again.')));
      }
    } finally {
      _pendingSave = null;
      if (mounted) setState(() => _saving = false);
      complete.complete();
    }
  }

  void _toggleInclude(SportsLeague league) {
    final next = Set<String>.of(_included);
    if (!next.remove(league.id)) next.add(league.id);
    _apply(next, _favorites, next.contains(_opening) ? _opening : null);
  }

  void _toggleFavorite(SportsLeague league) {
    final favorites = Set<String>.of(_favorites);
    final included = Set<String>.of(_included);
    if (!favorites.remove(league.id)) {
      // Starring a league the viewer had excluded puts it back in Sports.
      favorites.add(league.id);
      included.add(league.id);
    }
    _apply(included, favorites, _opening);
  }

  void _bulkInclude(bool include) {
    final ids = _visibleLeagues.map((l) => l.id).toSet();
    final next = include ? {..._included, ...ids} : _included.difference(ids);
    _apply(next, _favorites, next.contains(_opening) ? _opening : null);
  }

  void _restoreSelection() => setState(() {
        _included = Set.of(_savedIncluded);
        _favorites = Set.of(_savedFavorites);
        _opening = _savedOpening;
        _filter();
      });

  void _clearFilters() {
    _search.clear();
    _changeFilter(() {
      _query = '';
      _sport = null;
    });
    _searchFocus.requestFocus();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      await _pendingSave;
    } catch (_) {}
    // Allow rollback/finalisation to complete before returning to Sports.
    if (mounted) popRouteIfCurrent(context, _changed);
  }

  Future<void> _chooseSport() async {
    final sports = _leagues.map(_sportOf).toSet().toList()
      ..sort((a, b) => sportLabel(a).compareTo(sportLabel(b)));
    final result = await showSportsChoices<String>(context,
        title: 'Filter by sport',
        selected: _sport ?? '',
        choices: [
          const SportsChoice('', 'All sports', '', icon: Icons.public),
          for (final sport in sports)
            SportsChoice(sport, sportLabel(sport),
                '${_leagues.where((l) => _sportOf(l) == sport).length} leagues',
                icon: sportIcon(sport)),
        ]);
    if (mounted && result != null) {
      _changeFilter(() => _sport = result.isEmpty ? null : result);
    }
  }

  /// The star is a touch target inside the row, so the remote needs the same
  /// two actions here: starring for Favorites, and the opening league.
  Future<void> _openMenu(SportsLeague league) async {
    final starred = _favorites.contains(league.id);
    final opening = _opening == league.id;
    final action = await showSportsChoices<String>(context,
        title: league.name,
        selected: '',
        showSelection: false,
        choices: [
          SportsChoice(
              'favorite',
              starred ? 'Remove from favorites' : 'Add to favorites',
              starred
                  ? ''
                  : 'Keeps the whole league in the Favorites filter.',
              icon: starred ? Icons.star_border_rounded : Icons.star_rounded),
          SportsChoice(
              'opening',
              opening ? 'Clear opening league' : 'Set as opening league',
              opening
                  ? ''
                  : 'Preferred starting league for Standings and Schedule. Events keeps its own filters.',
              icon: Icons.push_pin_outlined),
        ]);
    if (!mounted || action == null) return;
    if (action == 'favorite') {
      _toggleFavorite(league);
    } else if (action == 'opening') {
      await _apply(
          {..._included, league.id}, _favorites, opening ? null : league.id);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: widget.embedded
            ? withTvThemeIfNeeded(context, _content)
            : SportsScreenFrame(
                child: withTvThemeIfNeeded(
                    context,
                    (context) => Stack(children: [
                          const Positioned.fill(
                              child: SettingsGradientBackground()),
                          Scaffold(
                              backgroundColor: Colors.transparent,
                              body: SafeArea(child: _content(context))),
                        ]))),
      );

  Widget _content(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final television = context.read<AppPreferences>().isTelevision;
    final scaler = MediaQuery.textScalerOf(context);
    final searchHeight =
        (scaler.scale(12) * 1.3 + 14).clamp(34.0, double.infinity);
    final bulkStyle = sportsPopupButtonStyle(context).copyWith(
        minimumSize: television
            ? WidgetStatePropertyAll(Size(
                0, (scaler.scale(11) * 1.3 + 10).clamp(28.0, double.infinity)))
            : null,
        padding: television
            ? const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8))
            : null,
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w500)));
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final includedCount =
        _visibleLeagues.where((l) => _included.contains(l.id)).length;
    final choices = [
      for (final l in _visibleLeagues)
        CompactChoice(
          id: l.id,
          title: l.name,
          group: _groupOf(l),
          subtitle: [
            if (!_included.contains(l.id)) 'Not in Sports',
            if (_opening == l.id) 'Opening league',
            if (l.region != null) l.region!,
            if (l.source == 'Channel guide') 'TV guide'
          ].join(' · '),
          leading: SportsLogo(
              url: l.logoUrl, size: 24, fallback: l.shortName, animate: false),
          trailing: _FavoriteStar(
              starred: _favorites.contains(l.id),
              onTap: () => _toggleFavorite(l)),
          onTap: () => _toggleInclude(l),
          onHold: () => _openMenu(l),
        )
    ];
    return LayoutBuilder(builder: (context, constraints) {
      // Scaffold may consume keyboard insets before they reach this panel.
      final compact = typing || constraints.maxHeight < 300;
      return Padding(
          padding: EdgeInsets.fromLTRB(
              widget.embedded ? 10 : 16, 4, widget.embedded ? 10 : 16, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
                height: compact
                    ? 40
                    : (MediaQuery.textScalerOf(context).scale(15) * 1.2 +
                            MediaQuery.textScalerOf(context).scale(10) * 1.2 +
                            8)
                        .clamp(40, double.infinity),
                child: Row(children: [
                  Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Text(sportsManageLeaguesLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        if (!compact)
                          Text('Included leagues appear in Sports · stars feed '
                              'the Favorites filter',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: colors.onSurfaceVariant)),
                      ])),
                  IconButton(
                      key: const ValueKey('close-leagues'),
                      focusNode: _closeFocus,
                      tooltip: 'Close',
                      style: IconButton.styleFrom(
                          minimumSize: const Size(34, 34),
                          maximumSize: const Size(34, 34),
                          padding: EdgeInsets.zero),
                      onPressed: _close,
                      icon: const Icon(Icons.close, size: 20)),
                ])),
            TvTextFieldGate(
                key: const ValueKey('league-search-slot'),
                focusNode: _searchFocus,
                builder: (context, readOnly) => TextField(
                      key: const ValueKey('league-manager-search'),
                      controller: _search,
                      focusNode: _searchFocus,
                      readOnly: readOnly,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                          isDense: true,
                          constraints: television
                              ? BoxConstraints.tightFor(height: searchHeight)
                              : null,
                          prefixIconConstraints: television
                              ? BoxConstraints.tightFor(
                                  width: 34, height: searchHeight)
                              : null,
                          suffixIconConstraints: television
                              ? BoxConstraints.tightFor(
                                  width: 34, height: searchHeight)
                              : null,
                          hintText: 'Search leagues or countries',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.clear, size: 17),
                                  onPressed: () {
                                    _search.clear();
                                    _changeFilter(() => _query = '');
                                    _searchFocus.requestFocus();
                                  })),
                      onChanged: (query) => _changeFilter(() => _query = query),
                    )),
            const SizedBox(height: 6),
            if (!compact)
              Row(children: [
                Expanded(
                    child: SportsFilterButton(
                        key: const ValueKey('league-manager-sport'),
                        caption: 'Sport',
                        value:
                            _sport == null ? 'All sports' : sportLabel(_sport!),
                        onTap: _chooseSport)),
              ]),
            if (!compact)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Wrap(spacing: 6, runSpacing: 2, children: [
                    OutlinedButton(
                        key: const ValueKey('enable-visible-leagues'),
                        style: bulkStyle,
                        onPressed: _saving || includedCount == choices.length
                            ? null
                            : () => _bulkInclude(true),
                        child: const Text('Include shown')),
                    OutlinedButton(
                        key: const ValueKey('disable-visible-leagues'),
                        style: bulkStyle,
                        onPressed: _saving || includedCount == 0
                            ? null
                            : () => _bulkInclude(false),
                        child: const Text('Exclude shown')),
                    OutlinedButton(
                        key: ValueKey(_included.isEmpty
                            ? 'restore-league-selection'
                            : 'enable-all-leagues'),
                        focusNode: _allFocus,
                        style: bulkStyle,
                        onPressed: _included.isEmpty
                            ? _restoreSelection
                            : _saving || _allIncluded
                                ? null
                                : () => _apply({..._included, ..._availableIds},
                                    _favorites, _opening),
                        child: Text(_included.isEmpty
                            ? 'Restore selection'
                            : _allIncluded
                                ? 'All leagues included'
                                : 'Include all leagues')),
                  ])),
            Container(
                padding: const EdgeInsets.fromLTRB(2, 5, 2, 6),
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color:
                                colors.outlineVariant.withValues(alpha: .4)))),
                child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: '${choices.length}',
                          style: TextStyle(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w600)),
                      const TextSpan(text: ' leagues · '),
                      TextSpan(
                          text: '${_included.length} in Sports',
                          style: TextStyle(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w500)),
                      const TextSpan(text: ' · '),
                      TextSpan(
                          text: '${_favorites.length} starred',
                          style: TextStyle(
                              color: colors.primary,
                              fontWeight: FontWeight.w500)),
                      TextSpan(
                          text:
                              ' · ${_included.isEmpty ? 'Choose leagues to finish' : _saving ? 'Saving…' : 'Saved automatically'}'),
                    ]),
                    style: TextStyle(
                        fontSize: 10, color: colors.onSurfaceVariant))),
            Expanded(
                child: choices.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                            const Text('No matching leagues',
                                style: TextStyle(fontSize: 12)),
                            TextButton(
                                key: const ValueKey('clear-league-filters'),
                                onPressed: _clearFilters,
                                child: const Text('Clear filters')),
                          ])))
                    : CompactChoiceList(
                        controller: _scroll,
                        autofocus: !_searchFocus.hasFocus,
                        choices: choices,
                        polished: true,
                        striped: true,
                        showNavigation: true,
                        rowHeight: (television ? 44 : 48) *
                            (MediaQuery.textScalerOf(context).scale(12) / 12)
                                .clamp(1.0, 2.5),
                        resetScrollKey: (_sport, _query),
                        onExitUp: _searchFocus.requestFocus,
                      )),
            if (!compact)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      _included.isEmpty
                          ? 'Your previous selection stays saved until you include a league.'
                          : context.read<AppPreferences>().isTelevision
                              ? 'OK: include · Star: favorites · Hold OK: more'
                              : 'Tap to include · Tap the star to favorite · Hold for more',
                      style: TextStyle(
                          fontSize: 10, color: colors.onSurfaceVariant))),
          ]));
    });
  }
}

/// Touch target for the per-row star. It never takes focus, so remote
/// traversal still walks search → sport → bulk actions → list.
class _FavoriteStar extends StatelessWidget {
  const _FavoriteStar({required this.starred, required this.onTap});
  final bool starred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: starred ? 'Remove from favorites' : 'Add to favorites',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Icon(
              starred ? Icons.star_rounded : Icons.star_border_rounded,
              size: 18,
              color: starred ? colors.primary : colors.onSurfaceVariant),
        ),
      ),
    );
  }
}
