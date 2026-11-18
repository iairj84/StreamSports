import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sports.dart';
import '../services/storage_service.dart';
import '../services/app_preferences.dart';
import '../services/sports_follows.dart';
import '../services/sports_service.dart';
import '../services/sports_standings_service.dart';
import '../utils/guarded_dialog.dart';
import '../utils/tv_theme.dart';
import '../utils/sports_presentation.dart';
import '../widgets/settings_scaffold.dart';
import '../widgets/shown_mark.dart';
import '../widgets/sports_panel.dart';
import '../widgets/sports_team_picker.dart';
import '../widgets/sports_widgets.dart';
import '../widgets/sports_header_controls.dart';
import '../widgets/sports_filter_picker.dart'
    show sportLabel, sportIcon, sportsManageLeaguesLabel;
import '../widgets/compact_choice_list.dart';
import '../widgets/tv_text_field_gate.dart';

/// Both decisions about what Sports shows, in one place: which leagues appear
/// (grouped under a sport that opens in place) and which teams are followed.
/// Tapping a league flips it. Nothing here is a favorite.
class SportsLeagueManagerScreen extends StatefulWidget {
  const SportsLeagueManagerScreen(
      {super.key, this.embedded = false, this.standings, this.follows});
  final bool embedded;
  final SportsStandingsService? standings;
  final SportsFollows? follows;
  @override
  State<SportsLeagueManagerScreen> createState() =>
      _SportsLeagueManagerScreenState();
}

class _SportsLeagueManagerScreenState extends State<SportsLeagueManagerScreen> {
  late final StorageService _storage = context.read<StorageService>();
  late final _standings = widget.standings ?? SportsStandingsService.instance;
  late final SportsFollows _follows = widget.follows ?? SportsFollows.load(_storage);
  late Set<String> _shown;
  late String? _opening = _storage.getSportsFavoriteLeague();
  late Set<String> _savedShown;
  String? _savedOpening;
  bool _changed = false, _saving = false;
  Future<void>? _pendingSave;
  bool _closing = false;
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'leagues-search');
  final _closeFocus = FocusNode(debugLabel: 'leagues-close');
  final _allFocus = FocusNode(debugLabel: 'leagues-show-all');
  final _addTeamFocus = FocusNode(debugLabel: 'teams-add');
  final _scroll = ScrollController();
  String _query = '';
  String _tab = 'leagues';
  /// Sports whose leagues are listed. A sport opens in place, so a viewer only
  /// scrolls through the sports they care about.
  final _expanded = <String>{};
  List<SportsLeague> _visibleLeagues = const [];
  late final _searchText = {
    for (final l in _leagues)
      l.id:
          '${l.name} ${l.shortName} ${leagueDescription(l)} ${l.region ?? ''} ${_groupOf(l)}'
              .toLowerCase()
  };
  static final _availableIds = {
    for (final l in [...kSportsLeagues, ...kSportsLeagueBank]) l.id
  };
  late final Map<String, SportsLeague> _byId = {
    for (final l in [...kSportsLeagues, ...kSportsLeagueBank]) l.id: l
  };
  // A conference or poll pick is covered by showing its full list.
  bool get _allShown => _availableIds.every((id) {
        if (_shown.contains(id)) return true;
        final parent = _byId[id]?.parentLeagueId;
        return parent != null && _shown.contains(parent);
      });

  void _filter() {
    final terms =
        _query.toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    _visibleLeagues = _leagues
        .where((l) => terms.every(_searchText[l.id]!.contains))
        .toList();
  }

  void _changeQuery(String query) {
    setState(() {
      _query = query;
      _filter();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void initState() {
    super.initState();
    _shown = savedSportsLeagues(_storage).map((l) => l.id).toSet();
    _savedShown = Set.of(_shown);
    _savedOpening = _opening;
    // Sports you already show start open; everything else stays closed.
    for (final id in _shown) {
      if (_byId[id] case final league?) _expanded.add(_sportOf(league));
    }
    _filter();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _closeFocus.dispose();
    _allFocus.dispose();
    _addTeamFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _sportOf(SportsLeague league) => league.espnPath.split('/').first;
  String _groupOf(SportsLeague league) => sportLabel(_sportOf(league));

  int _sportRank(String a, String b) {
    final rank = sportDisplayPriority(a).compareTo(sportDisplayPriority(b));
    return rank != 0 ? rank : sportLabel(a).compareTo(sportLabel(b));
  }

  /// Picks that narrow [league]: its conferences and poll views.
  List<SportsLeague> _picksOf(SportsLeague league) =>
      [for (final l in _leagues) if (l.parentLeagueId == league.id) l];

  /// One rule, in one place: a full competition and the picks that narrow it
  /// are never shown together. Turning a pick on hides its full list; turning
  /// the full list on already covers every pick, so the picks go.
  Set<String> _settle(Set<String> shown, {String? favour}) {
    final next = Set<String>.of(shown);
    for (final league in _leagues) {
      final parentId = league.parentLeagueId;
      if (parentId == null || !next.contains(league.id)) continue;
      if (!next.contains(parentId)) continue;
      if (favour == league.id) {
        next.remove(parentId);
      } else {
        next.remove(league.id);
      }
    }
    return next;
  }

  String _subtitleOf(SportsLeague league) {
    final shown = _shown.contains(league.id);
    final parentId = league.parentLeagueId;
    final parts = <String>[];
    if (parentId != null) {
      final parent = _byId[parentId];
      if (_shown.contains(parentId)) {
        parts.add('Included in ${parent?.name ?? 'the full list'}');
      } else if (shown) {
        parts.add(league.rankedOnly
            ? 'Only games with a ranked team'
            : 'Only ${league.shortName} games');
      } else {
        parts.add('Hidden');
      }
    } else {
      final picks = [
        for (final p in _picksOf(league))
          if (_shown.contains(p.id)) p
      ];
      if (!shown) {
        parts.add(picks.isEmpty
            ? 'Hidden'
            : 'Off — showing ${picks.length == 1 ? picks.single.name : '${picks.length} picks'}');
      }
    }
    if (_opening == league.id) parts.add('Opening league');
    if (league.region != null) parts.add(league.region!);
    if (league.source == 'Channel guide') parts.add('TV guide');
    return parts.join(' · ');
  }

  late final List<SportsLeague> _leagues = _orderedLeagues();
  late final Map<String, List<SportsLeague>> _bySport = () {
    final map = <String, List<SportsLeague>>{};
    for (final league in _leagues) {
      (map[_sportOf(league)] ??= []).add(league);
    }
    return map;
  }();
  late final List<String> _sports = [..._bySport.keys]..sort(_sportRank);

  List<SportsLeague> _orderedLeagues() {
    final leagues = {
      for (final l in [...kSportsLeagues, ...kSportsLeagueBank]) l.id: l
    }.values.toList();
    final order = {for (final (i, league) in leagues.indexed) league.id: i};
    final groups = <String, List<SportsLeague>>{};
    for (final league in leagues) {
      (groups[_sportOf(league)] ??= []).add(league);
    }
    for (final group in groups.values) {
      group.sort((a, b) {
        final priority =
            leagueDisplayPriority(a).compareTo(leagueDisplayPriority(b));
        return priority != 0 ? priority : order[a.id]!.compareTo(order[b.id]!);
      });
    }
    final ordered = [
      for (final sport in groups.keys.toList()..sort(_sportRank))
        ...groups[sport]!
    ];
    final picks = <String, List<SportsLeague>>{};
    for (final league in ordered) {
      final parent = league.parentLeagueId;
      if (parent != null) (picks[parent] ??= []).add(league);
    }
    if (picks.isEmpty) return ordered;
    // Every pick sits directly under the list it narrows.
    return [
      for (final league in ordered)
        if (league.parentLeagueId == null) ...[
          league,
          ...?picks[league.id],
        ],
    ];
  }

  /// Leagues the bulk buttons act on: the search results, or every league of
  /// the sports currently open.
  List<SportsLeague> get _listedLeagues => _query.isNotEmpty
      ? _visibleLeagues
      : [for (final sport in _expanded) ...?_bySport[sport]];

  Future<void> _persist(Set<String> shown, String? opening) async {
    await _storage.setSportsLeagues(shown.toList());
    await _storage.setHiddenGuideLeagues([
      for (final l in kAutomaticSportsLeagues)
        if (!shown.contains(l.id)) l.id,
    ]);
    await _storage.setSportsFavoriteLeague(opening);
    await _storage.setSportsAllLeagues(_availableIds.every(shown.contains));
  }

  Future<void> _apply(Set<String> shown, String? opening) async {
    if (_saving || _closing) return;
    final unchanged = shown.length == _shown.length &&
        shown.containsAll(_shown) &&
        opening == _opening;
    if (unchanged) return;
    if (shown.isEmpty) {
      // Empty is an editing step, never a persisted selection: the loader
      // treats an empty saved set as the default catalogue.
      setState(() {
        _shown = shown;
        _opening = opening;
        _filter();
      });
      return;
    }
    final previous = Set<String>.of(_shown), previousOpening = _opening;
    setState(() {
      _saving = true;
      _shown = shown;
      _opening = opening;
      _filter();
    });
    final complete = Completer<void>();
    _pendingSave = complete.future;
    try {
      await _persist(shown, opening);
      _savedShown = Set.of(shown);
      _savedOpening = opening;
      _changed = true;
    } catch (_) {
      // Restore both the local view and any preference writes completed before failure.
      try {
        await _persist(_savedShown, _savedOpening);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _shown = previous;
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

  void _toggle(SportsLeague league) {
    final next = Set<String>.of(_shown);
    final showing = !next.remove(league.id);
    if (showing) next.add(league.id);
    final settled = _settle(next, favour: showing ? league.id : null);
    _apply(settled, settled.contains(_opening) ? _opening : null);
  }

  void _bulk(bool show) {
    final ids = _listedLeagues.map((l) => l.id).toSet();
    final next = _settle(show ? {..._shown, ...ids} : _shown.difference(ids));
    _apply(next, next.contains(_opening) ? _opening : null);
  }

  void _restoreSelection() => setState(() {
        _shown = Set.of(_savedShown);
        _opening = _savedOpening;
        _filter();
      });

  void _clearFilters() {
    _search.clear();
    _changeQuery('');
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

  Future<void> _openMenu(SportsLeague league) async {
    final opening = _opening == league.id;
    final action = await showSportsChoices<String>(context,
        title: league.name,
        selected: '',
        showSelection: false,
        choices: [
          SportsChoice(
              'opening',
              opening ? 'Clear opening league' : 'Set as opening league',
              opening
                  ? ''
                  : 'Preferred starting league for Standings and Schedule. Events keeps its own filters.',
              icon: Icons.push_pin_outlined),
        ]);
    if (!mounted || action == null) return;
    await _apply({..._shown, league.id}, opening ? null : league.id);
  }

  Future<void> _removeTeam(FollowedTeam entry) async {
    final name = _follows.nameOf(entry) ?? entry.teamId;
    final logo = _follows.logoOf(entry);
    try {
      await _follows.unfollow(entry.leagueId, entry.teamId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save that team. Please try again.')));
      }
      return;
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Removed $name'),
      action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(_follows
                .follow(entry.leagueId, entry.teamId, name: name, logoUrl: logo)
                .then((_) {
              if (mounted) setState(() {});
            }));
          }),
    ));
  }

  /// Sport, then league, then every team that league lists.
  Future<void> _addTeam() async {
    final sports = sportsStandingsLeagues.map(_sportOf).toSet().toList()
      ..sort(_sportRank);
    final sport = await showSportsChoices<String>(context,
        title: 'Add a team',
        description: 'Choose a sport, then the league the team plays in.',
        selected: '',
        showSelection: false,
        choices: [
          for (final sport in sports)
            SportsChoice(
                sport,
                sportLabel(sport),
                '${sportsStandingsLeagues.where((l) => _sportOf(l) == sport).length} leagues',
                icon: sportIcon(sport),
                key: ValueKey('add-team-sport-$sport')),
        ]);
    if (!mounted || sport == null) return;
    final leagues = sportsStandingsLeagues
        .where((l) => _sportOf(l) == sport)
        .toList()
      ..sort((a, b) {
        final priority =
            leagueDisplayPriority(a).compareTo(leagueDisplayPriority(b));
        return priority != 0 ? priority : a.name.compareTo(b.name);
      });
    final leagueId = await showSportsChoices<String>(context,
        title: sportLabel(sport),
        selected: '',
        showSelection: false,
        choices: [
          for (final league in leagues)
            SportsChoice(league.id, league.name, leagueDescription(league),
                icon: sportIcon(sport),
                key: ValueKey('add-team-league-${league.id}')),
        ]);
    if (!mounted || leagueId == null) return;
    final league = sportsLeagueById(leagueId);
    if (league == null) return;
    await showSportsPanel<void>(
        context: context,
        besidePreview: true,
        builder: (_) => SportsTeamPicker(
            league: league, follows: _follows, standings: _standings));
    if (mounted) setState(() {});
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
    return LayoutBuilder(builder: (context, constraints) {
      // Scaffold may consume keyboard insets before they reach this panel.
      final compact = typing || constraints.maxHeight < 300;
      return Padding(
          padding: EdgeInsets.fromLTRB(
              widget.embedded ? 10 : 16, 4, widget.embedded ? 10 : 16, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(compact, colors, scaler),
            if (!compact) _tabs(),
            const SizedBox(height: 6),
            if (_tab == 'leagues')
              ..._leagueBody(
                  context,
                  compact: compact,
                  television: television,
                  bulkStyle: bulkStyle,
                  searchHeight: searchHeight)
            else
              Expanded(child: _teamsBody(context, bulkStyle: bulkStyle)),
          ]));
    });
  }

  Widget _header(bool compact, ColorScheme colors, TextScaler scaler) =>
      SizedBox(
          height: compact
              ? 40
              : (scaler.scale(15) * 1.2 + scaler.scale(10) * 1.2 + 8)
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
                    Text(
                        _tab == 'leagues'
                            ? 'Pick a sport, then its leagues'
                            : 'Follow the teams you care about',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10, color: colors.onSurfaceVariant)),
                ])),
            if (compact) ...[_tabs(iconOnly: true), const SizedBox(width: 6)],
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
          ]));

  Widget _tabs({bool iconOnly = false}) => Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<String>(
        key: const ValueKey('follow-tabs'),
        showSelectedIcon: false,
        style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10)),
            textStyle: WidgetStatePropertyAll(
                TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
        segments: [
          ButtonSegment(
              value: 'leagues',
              tooltip: 'Leagues',
              label: iconOnly ? null : const Text('Leagues'),
              icon: const Icon(Icons.checklist_rounded, size: 16)),
          ButtonSegment(
              value: 'teams',
              tooltip: 'Teams',
              label: iconOnly ? null : const Text('Teams'),
              icon: const Icon(Icons.star_outline_rounded, size: 16)),
        ],
        selected: {_tab},
        onSelectionChanged: (values) => setState(() => _tab = values.first),
      ));

  List<Widget> _leagueBody(BuildContext context,
      {required bool compact,
      required bool television,
      required ButtonStyle bulkStyle,
      required double searchHeight}) {
    final colors = Theme.of(context).colorScheme;
    final choices = _leagueChoices();
    final listed = _listedLeagues;
    final listedShown = listed.where((l) => _shown.contains(l.id)).length;
    return [
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
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.clear, size: 17),
                            onPressed: () {
                              _search.clear();
                              _changeQuery('');
                              _searchFocus.requestFocus();
                            })),
                onChanged: _changeQuery,
              )),
      if (!compact)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Wrap(spacing: 6, runSpacing: 2, children: [
              OutlinedButton(
                  key: const ValueKey('show-visible-leagues'),
                  style: bulkStyle,
                  onPressed: _saving || listed.isEmpty || listedShown == listed.length
                      ? null
                      : () => _bulk(true),
                  child: const Text('Show listed')),
              OutlinedButton(
                  key: const ValueKey('hide-visible-leagues'),
                  style: bulkStyle,
                  onPressed: _saving || listedShown == 0
                      ? null
                      : () => _bulk(false),
                  child: const Text('Hide listed')),
              OutlinedButton(
                  key: ValueKey(_shown.isEmpty
                      ? 'restore-league-selection'
                      : 'show-all-leagues'),
                  focusNode: _allFocus,
                  style: bulkStyle,
                  onPressed: _shown.isEmpty
                      ? _restoreSelection
                      : _saving || _allShown
                          ? null
                          : () => _apply({..._shown, ..._availableIds}, _opening),
                  child: Text(_shown.isEmpty
                      ? 'Restore selection'
                      : _allShown
                          ? 'All leagues shown'
                          : 'Show all leagues')),
            ])),
      Container(
          padding: const EdgeInsets.fromLTRB(2, 5, 2, 6),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: .4)))),
          child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '${_leagues.length}',
                    style: TextStyle(
                        color: colors.onSurface, fontWeight: FontWeight.w600)),
                const TextSpan(text: ' leagues · '),
                TextSpan(
                    text: '${_shown.length} shown',
                    style: TextStyle(
                        color: colors.onSurface, fontWeight: FontWeight.w500)),
                TextSpan(
                    text:
                        ' · ${_shown.isEmpty ? 'Choose leagues to finish' : _saving ? 'Saving…' : 'Saved automatically'}'),
              ]),
              style:
                  TextStyle(fontSize: 10, color: colors.onSurfaceVariant))),
      Expanded(
          child: choices.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                      child:
                          Column(mainAxisSize: MainAxisSize.min, children: [
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
                  resetScrollKey: _query,
                  onExitUp: _searchFocus.requestFocus,
                )),
      if (!compact)
        Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                _shown.isEmpty
                    ? 'Your previous selection stays saved until you show a league.'
                    : television
                        ? 'OK: open a sport or turn a league on or off · Hold OK: options'
                        : 'Tap a sport to open it · tap a league to show or hide it',
                style:
                    TextStyle(fontSize: 10, color: colors.onSurfaceVariant))),
    ];
  }

  List<CompactChoice> _leagueChoices() {
    final rows = <CompactChoice>[];
    if (_query.isNotEmpty) {
      // A search looks across every sport; the tree would hide the answer.
      for (final league in _visibleLeagues) {
        rows.add(_leagueChoice(league, group: _groupOf(league)));
      }
      return rows;
    }
    for (final sport in _sports) {
      final leagues = _bySport[sport] ?? const <SportsLeague>[];
      final open = _expanded.contains(sport);
      final shown = leagues.where((l) => _shown.contains(l.id)).length;
      rows.add(CompactChoice(
        id: 'sport:$sport',
        title: sportLabel(sport),
        subtitle: '$shown of ${leagues.length} shown',
        leading: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Icon(sportIcon(sport), size: 20)),
        trailing:
            Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 18),
        onTap: () => setState(() {
          if (!_expanded.remove(sport)) _expanded.add(sport);
        }),
      ));
      if (!open) continue;
      for (final league in leagues) {
        rows.add(_leagueChoice(league, indent: 22));
      }
    }
    return rows;
  }

  CompactChoice _leagueChoice(SportsLeague league,
          {String? group, double indent = 0}) =>
      CompactChoice(
        id: league.id,
        title: league.name,
        group: group,
        subtitle: _subtitleOf(league),
        leading: Padding(
            padding: EdgeInsets.only(left: indent),
            child: SportsLogo(
                url: league.logoUrl,
                size: 24,
                fallback: league.shortName,
                animate: false)),
        trailing: ShownMark(shown: _shown.contains(league.id)),
        onTap: () => _toggle(league),
        onHold: () => _openMenu(league),
      );

  Widget _teamsBody(BuildContext context, {required ButtonStyle bulkStyle}) {
    final colors = Theme.of(context).colorScheme;
    final teams = _follows.teams;
    final choices = [
      for (final entry in teams)
        CompactChoice(
          id: 'followed:${entry.key}',
          title: _follows.nameOf(entry) ?? entry.teamId,
          subtitle: sportsLeagueById(entry.leagueId)?.name ?? entry.leagueId,
          leading: SportsLogo(
              url: _follows.logoOf(entry),
              size: 24,
              fallback: _follows.nameOf(entry) ?? entry.teamId,
              animate: false),
          trailing: const ShownMark(
              shown: true, shownLabel: 'Following', hiddenLabel: 'Not following'),
          onTap: () => _removeTeam(entry),
        )
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        OutlinedButton.icon(
            key: const ValueKey('add-team'),
            focusNode: _addTeamFocus,
            style: bulkStyle,
            onPressed: _addTeam,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add team')),
        const SizedBox(width: 8),
        Expanded(
            child: Text('${teams.length} followed',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 10, color: colors.onSurfaceVariant))),
      ]),
      const SizedBox(height: 6),
      Expanded(
          child: choices.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                      child:
                          Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('No teams followed yet',
                        style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 2),
                    Text('Add team lists a league, then its teams.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 10, color: colors.onSurfaceVariant)),
                  ])))
              : CompactChoiceList(
                  controller: _scroll,
                  choices: choices,
                  polished: true,
                  striped: true,
                  rowHeight: 48,
                  resetScrollKey: _tab,
                  onExitUp: _addTeamFocus.requestFocus,
                )),
      Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              teams.isEmpty
                  ? 'Followed teams feed My Teams and the Favorites filter.'
                  : 'Tap a team to stop following it',
              style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant))),
    ]);
  }
}
