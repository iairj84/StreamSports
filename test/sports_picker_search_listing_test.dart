import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/models/epg_program.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/services/app_preferences.dart';
import 'package:nox_iptv/services/epg_service.dart';
import 'package:nox_iptv/services/sports_channel_matcher.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/utils/live_guide_search.dart';
import 'package:nox_iptv/utils/tv_theme.dart';
import 'package:nox_iptv/widgets/sports_channel_picker.dart';

/// A provider usually names the network in the listing's synopsis, not in the
/// channel name: the card says the game is on CBSSN, the playlist calls the
/// channel "CBS Sports HD", and the only "CBSSN" the app can see is in the
/// guide text. The live guide search has always read title and description
/// together, so it found the channel; the picker read titles only and answered
/// zero. These tests pin the picker to the same evidence.
class _Guide extends EpgService {
  _Guide(super.storage, this.rows);
  final Map<String, EpgProgram> rows;
  @override
  EpgProgram? getCurrentProgram(String id) => rows[normalizeEpgId(id)];
  @override
  EpgProgram? getNextProgram(String id) => null;
  @override
  Future<List<EpgProgram>> findProgrammesByTitle(
          DateTime from, DateTime to, List<String> terms,
          {List<String>? channelIds}) async =>
      rows.values
          .where((p) => terms.any((t) => p.title.toLowerCase().contains(t)))
          .toList();
  @override
  Future<List<EpgProgram>> findSportsProgrammesForChannels(
          List<String> ids, DateTime from, DateTime to) async =>
      const [];
}

Channel _channel(String id, String name, {String? epgId}) => Channel(
      id: 'test::$id',
      rawId: id,
      playlistId: 'test',
      name: name,
      group: 'Sports',
      url: 'https://example.invalid/$id',
      epgIdOverride: epgId,
    );

EpgProgram _nowAiring(String channelId, String title,
    {String? description}) {
  final start = DateTime.now().subtract(const Duration(minutes: 20));
  return EpgProgram(
      channelId: channelId,
      title: title,
      description: description,
      start: start,
      stop: start.add(const Duration(hours: 2)));
}

SportsGame _game({List<String> broadcasts = const ['CBSSN']}) => SportsGame(
      id: 'espn:1',
      league: sportsLeagueById('basketball.mens-college-basketball')!,
      start: DateTime.now(),
      state: GameState.pre,
      statusText: 'Scheduled',
      home: const SportsTeam(
          id: 'duke',
          name: 'Duke Blue Devils',
          shortName: 'Duke',
          abbreviation: 'DUKE'),
      away: const SportsTeam(
          id: 'unc',
          name: 'North Carolina Tar Heels',
          shortName: 'UNC',
          abbreviation: 'UNC'),
      broadcasts: broadcasts,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a network named only in the synopsis is found, as the guide finds it',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final guide = _Guide(storage, {
      'cbs': _nowAiring('cbs', 'College Basketball',
          description: 'Duke at North Carolina (CBSSN)'),
    });
    final matcher = SportsChannelMatcher(guide);
    addTearDown(matcher.dispose);
    await matcher.prepare([
      _channel('cbs', 'US: CBS Sports HD', epgId: 'cbs'),
      _channel('other', 'Get TV'),
    ]);

    final live = await searchLiveGuide([matcher.channelById('test::cbs')!],
        'CBSSN', guide.getCurrentProgram);
    expect(live, isNotEmpty, reason: 'the live guide reaches the synopsis');

    final picked = await matcher.searchWithGuide('CBSSN');
    expect(picked.map((r) => r.channel.rawId), ['cbs']);
    // The match is reported as a listing hit, because the synopsis carried it.
    expect(picked.single.programmeSearchHit, isTrue);
  });

  for (final background in [false, true]) {
    test('every spelling of the service is searchable ($background)', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final guide = _Guide(storage, const {});
      final matcher = background
          ? SportsChannelMatcher.background(guide)
          : SportsChannelMatcher(guide);
      addTearDown(matcher.dispose);
      await matcher.prepare([
        _channel('a', 'US: CBS Sports Network HD'),
        _channel('b', 'US: CBSSN HD'),
        _channel('c', 'Get TV'),
      ]);
      for (final query in ['CBSSN', 'cbs sn', 'CBS Sports Network']) {
        final results = await matcher.searchWithGuide(query);
        expect(results.map((r) => r.channel.rawId), containsAll(['a', 'b']),
            reason: query);
        expect(results.map((r) => r.channel.rawId), isNot(contains('c')),
            reason: query);
      }
    });
  }

  test('an unrelated listing stays out of a network query', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final guide = _Guide(storage, {
      'tv': _nowAiring('tv', 'Mr. Monk and the Big Game',
          description: 'Monk coaches a basketball team.'),
    });
    final matcher = SportsChannelMatcher(guide);
    addTearDown(matcher.dispose);
    await matcher.prepare([
      _channel('tv', 'Get TV', epgId: 'tv'),
    ]);
    expect(await matcher.searchWithGuide('CBSSN'), isEmpty);
    // The same listing is a legitimate hit for its own words.
    expect(await matcher.searchWithGuide('basketball'), hasLength(1));
  });

  for (final background in [false, true]) {
    test('the broadcast name matches the channel carrying it ($background)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final guide = _Guide(storage, const {});
      final matcher = background
          ? SportsChannelMatcher.background(guide)
          : SportsChannelMatcher(guide);
      addTearDown(matcher.dispose);
      await matcher.prepare([
        _channel('a', 'US: CBS Sports Network HD'),
      ]);
      final matches =
          await matcher.matchDay([_game()], SportsChannelPicks.load(storage));
      expect(
          matches.values.single
              .where((m) => m.isConfident)
              .map((m) => m.channel.rawId),
          ['a'],
          reason: 'ESPN lists CBSSN and the playlist carries the service');
    });
  }

  testWidgets('the picker finds the channel the card names', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final prefs = AppPreferences(storage);
    await prefs.init();
    final guide = _Guide(storage, {
      'cbs': _nowAiring('cbs', 'College Basketball',
          description: 'Duke at North Carolina (CBSSN)'),
      'tv': _nowAiring('tv', 'Mr. Monk and the Big Game',
          description: 'Monk coaches a basketball team.'),
    });
    final matcher = SportsChannelMatcher(guide);
    addTearDown(matcher.dispose);
    final channels = [
      _channel('cbs', 'US: CBS Sports HD', epgId: 'cbs'),
      _channel('tv', 'Get TV', epgId: 'tv'),
    ];
    await tester.runAsync(() => matcher.prepare(channels));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: prefs),
        ChangeNotifierProvider<EpgService>.value(value: guide),
      ],
      child: MaterialApp(
        theme: buildAppTheme(prefs.palette),
        home: Scaffold(
          body: SportsChannelPickerDialog(
              game: _game(),
              matcher: matcher,
              // "No Channel – Choose": the card got nothing, so the search
              // runs against the whole catalogue.
              matches: const [],
              onDecision: (row, rejected) async {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Find another channel'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.text('Find a channel'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('sports-channel-search')), 'CBSSN');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    final rows =
        tester.widget<SportsChannelList>(find.byType(SportsChannelList)).rows;
    // The channel the card named comes first. The card's own weak guide
    // evidence (a phone-in programme about a basketball team) is still listed,
    // because it is a channel the app already believes carries the event, but
    // it must not outrank the row the viewer actually asked for.
    expect(rows.map((r) => r.channel.rawId), ['cbs', 'tv']);
    expect(rows.first.programmeSearchHit, isTrue);
    expect(rows.last.programmeSearchHit, isFalse);
    expect(tester.takeException(), isNull);
  });
}
