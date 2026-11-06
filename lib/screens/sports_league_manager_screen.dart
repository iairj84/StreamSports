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

/// One list, one state per league: shown in Sports, or hidden. Tapping a row
/// flips it. Nothing here is a favorite.
class SportsLeagueManagerScreen extends StatefulWidget {
  const SportsLeagueManagerScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<SportsLeagueManagerScreen> createState() =>
      _SportsLeagueManagerScreenState();
}

class _SportsLeagueManagerScreenState extends State<SportsLeagueManagerScreen> {
  late final StorageService _storage = context.read<StorageService>();
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
    _shown = savedSportsLeagues(_storage).map((l) => l.id).toSet();
    _savedShown = Set.of(_shown);
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
    final ordered = groups.values.expand((group) => group).toList();
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
    final ids = _visibleLeagues.map((l) => l.id).toSet();
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
    final shownCount =
        _visibleLeagues.where((l) => _shown.contains(l.id)).length;
    final choices = [
      for (final l in _visibleLeagues)
        CompactChoice(
          id: l.id,
          title: l.name,
          group: _groupOf(l),
          subtitle: _subtitleOf(l),
          leading: SportsLogo(
              url: l.logoUrl, size: 24, fallback: l.shortName, animate: false),
          trailing: _ShownMark(shown: _shown.contains(l.id)),
          onTap: () => _toggle(l),
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
                          Text('Tap to show or hide · a pick replaces its full list',
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
                        key: const ValueKey('show-visible-leagues'),
                        style: bulkStyle,
                        onPressed: _saving || shownCount == choices.length
                            ? null
                            : () => _bulk(true),
                        child: const Text('Show listed')),
                    OutlinedButton(
                        key: const ValueKey('hide-visible-leagues'),
                        style: bulkStyle,
                        onPressed: _saving || shownCount == 0
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
                                : () =>
                                    _apply({..._shown, ..._availableIds}, _opening),
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
                          text: '${_shown.length} shown',
                          style: TextStyle(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w500)),
                      TextSpan(
                          text:
                              ' · ${_shown.isEmpty ? 'Choose leagues to finish' : _saving ? 'Saving…' : 'Saved automatically'}'),
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
                      _shown.isEmpty
                          ? 'Your previous selection stays saved until you show a league.'
                          : context.read<AppPreferences>().isTelevision
                              ? 'OK: show or hide · Hold OK: options'
                              : 'Tap to show or hide · Hold for options',
                      style: TextStyle(
                          fontSize: 10, color: colors.onSurfaceVariant))),
          ]));
    });
  }
}

/// Touch-free state marker: a shown league is checked, a hidden one is empty.
class _ShownMark extends StatelessWidget {
  const _ShownMark({required this.shown});
  final bool shown;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: shown ? 'Shown in Sports' : 'Hidden from Sports',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Icon(
            shown ? Icons.check_circle : Icons.circle_outlined,
            size: 18,
            color: shown ? colors.primary : colors.onSurfaceVariant),
      ),
    );
  }
}
