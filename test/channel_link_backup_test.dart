import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/screens/settings/channel_linking_screen.dart';
import 'package:nox_iptv/services/app_preferences.dart';
import 'package:nox_iptv/services/catalog_database.dart';
import 'package:nox_iptv/services/playlist_manager.dart';
import 'package:nox_iptv/services/storage_service.dart';

/// A provider whose backup feed sits in the same playlist, as M3U providers
/// commonly name it ("ESPN *" beside "ESPN"). Only the surface the linking
/// screen reads is overridden.
class _Playlist extends PlaylistManager {
  _Playlist(super.storage, super.db);

  final catalogue = <Channel>[
    _channel('espn', 'ESPN'),
    _channel('espn_star', 'ESPN *'),
    _channel('espn2', 'ESPN2'),
  ];
  final links = <String, ChannelLink>{};

  @override
  List<Channel> visibleChannels(
          {String? playlistId, String? groupTitle, required String category}) =>
      playlistId == null
          ? catalogue
          : catalogue.where((c) => c.playlistId == playlistId).toList();

  @override
  ChannelLink? channelLinkFor(Channel channel) => links[channel.rawId];

  @override
  Channel? resolveChannelLink(ChannelLink link) => catalogue
      .where((c) => c.playlistId == link.playlistId && c.rawId == link.rawId)
      .firstOrNull;

  @override
  String playlistNameFor(String playlistId) =>
      playlistId == 'fixture' ? 'Provider' : playlistId;

  @override
  Future<void> setChannelLink(Channel channel, ChannelLink? link) async {
    if (link == null) {
      links.remove(channel.rawId);
    } else {
      links[channel.rawId] = link;
    }
  }
}

Channel _channel(String rawId, String name, {String playlistId = 'fixture'}) =>
    Channel(
        id: '$playlistId::$rawId',
        rawId: rawId,
        playlistId: playlistId,
        name: name,
        group: 'Sports',
        url: 'https://example.invalid/never-opened');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Playlist playlist;
  late StorageService storage;
  late AppPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    prefs = AppPreferences(storage);
    await prefs.init();
    playlist = _Playlist(storage, CatalogDatabase());
  });
  tearDown(() {
    prefs.dispose();
    playlist.dispose();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storage),
          ChangeNotifierProvider<AppPreferences>.value(value: prefs),
          ChangeNotifierProvider<PlaylistManager>.value(value: playlist),
        ],
        child: const MaterialApp(home: ChannelLinkingScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets('one playlist is enough to link a channel to its backup',
      (tester) async {
    await open(tester);
    // The old screen refused to link anything without a second playlist.
    expect(find.textContaining('second playlist'), findsNothing);
    expect(find.text('ESPN'), findsOneWidget);
    expect(find.text('ESPN *'), findsOneWidget);
  });

  testWidgets('the backup in the same playlist can be chosen as the target',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('ESPN'));
    await tester.pumpAndSettle();

    // The picker opens on the source's own playlist, so its backup is listed
    // without touching another source.
    expect(find.text('Link "ESPN"'), findsOneWidget);
    expect(find.text('ESPN *'), findsOneWidget);
    // The channel being linked is never its own target.
    expect(find.text('ESPN'), findsNothing);

    await tester.tap(find.text('ESPN *'));
    await tester.pumpAndSettle();

    expect(playlist.links['espn'],
        (playlistId: 'fixture', rawId: 'espn_star'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a linked backup is shown as the failover target',
      (tester) async {
    playlist.links['espn'] = (playlistId: 'fixture', rawId: 'espn_star');
    await open(tester);
    expect(find.text('Provider — Linked to Provider: ESPN *'), findsOneWidget);
  });

  group('auto-pair', () {
    Map<String, ChannelLink> plan(
            List<Channel> channels, {
            Set<String> alreadyLinked = const {},
            List<Map<String, List<Channel>>> otherPlaylistsByKey = const [],
          }) =>
        planAutoPairLinks(
            channels: channels,
            alreadyLinked: alreadyLinked,
            otherPlaylistsByKey: otherPlaylistsByKey);

    test('pairs a channel with its own playlist backup copy', () {
      final links = plan([
        _channel('espn', 'ESPN'),
        _channel('espn_star', 'ESPN *'),
        _channel('espn2', 'ESPN2'),
      ]);

      expect(links['espn'], (playlistId: 'fixture', rawId: 'espn_star'));
      expect(links['espn_star'], (playlistId: 'fixture', rawId: 'espn'));
      expect(links.containsKey('espn2'), isFalse);
    });

    test('a quality variant is never taken for a backup', () {
      final links = plan([
        _channel('espn', 'ESPN'),
        _channel('espn_hd', 'ESPN HD'),
        _channel('espn2', 'ESPN2'),
      ]);

      expect(links, isEmpty);
    });

    test('two backup copies leave the primary for the picker', () {
      final links = plan([
        _channel('espn', 'ESPN'),
        _channel('espn_star', 'ESPN *'),
        _channel('espn_star2', 'ESPN *'),
      ]);

      // Either backup could be the target, so the primary is not guessed;
      // each copy still knows the one feed it can fall back to.
      expect(links.containsKey('espn'), isFalse);
      expect(links['espn_star'], (playlistId: 'fixture', rawId: 'espn'));
      expect(links['espn_star2'], (playlistId: 'fixture', rawId: 'espn'));
    });

    test('a match in another playlist still takes priority', () {
      final links = plan(
        [_channel('espn', 'ESPN'), _channel('espn_star', 'ESPN *')],
        otherPlaylistsByKey: [
          {
            'ESPN': [_channel('espn', 'ESPN', playlistId: 'other')],
          }
        ],
      );

      expect(links['espn'], (playlistId: 'other', rawId: 'espn'));
      expect(links['espn_star'], (playlistId: 'other', rawId: 'espn'));
    });

    test('a channel that already has a link is left alone', () {
      final links = plan(
        [_channel('espn', 'ESPN'), _channel('espn_star', 'ESPN *')],
        alreadyLinked: {'espn'},
      );

      expect(links.containsKey('espn'), isFalse);
    });
  });
}
