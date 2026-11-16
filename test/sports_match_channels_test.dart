import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/services/catalog_database.dart';
import 'package:nox_iptv/services/playlist_manager.dart';
import 'package:nox_iptv/services/sports_channel_matcher.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Channel _channel(String playlistId, String id, String name) => Channel(
      id: '$playlistId::$id',
      rawId: id,
      playlistId: playlistId,
      name: name,
      group: 'Sports',
      url: 'https://example.invalid/never-opened',
    );

class _Playlists extends PlaylistManager {
  _Playlists(StorageService storage) : super(storage, CatalogDatabase());

  // The same channel object appears in both lists, as in the app where a
  // channel id is stable across playlists.
  static final shared = _channel('browsed', 'shared', 'Shared Sports');
  final preferred = [
    _channel('preferred', 'espn', 'ESPN'),
    shared,
  ];
  final live = [
    shared,
    _channel('browsed', 'btn', 'BTN'),
    _channel('browsed', 'fs1', 'FS1'),
  ];

  @override
  List<Channel> get visibleLiveChannels => live;

  @override
  List<Channel> visibleChannels(
          {String? playlistId, String? groupTitle, required String category}) =>
      playlistId == 'preferred' ? preferred : const <Channel>[];
}

void main() {
  late _Playlists playlist;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    playlist = _Playlists(storage);
  });

  List<String> ids(List<Channel> channels) =>
      [for (final c in channels) c.id];

  test('preferred playlist channels come first without duplicates', () {
    final channels = SportsChannelMatcher.matchChannels(playlist,
        preferredId: 'preferred');
    expect(ids(channels), orderedEquals([
      'preferred::espn',
      'browsed::shared',
      'browsed::btn',
      'browsed::fs1',
    ]));
  });

  test('identical inputs give identical order on every call', () {
    final first = ids(SportsChannelMatcher.matchChannels(playlist,
        preferredId: 'preferred'));
    final second = ids(SportsChannelMatcher.matchChannels(playlist,
        preferredId: 'preferred'));
    final browsed = ids(SportsChannelMatcher.matchChannels(playlist));
    expect(second, orderedEquals(first));
    expect(browsed,
        orderedEquals(['browsed::shared', 'browsed::btn', 'browsed::fs1']));
  });

  test('no preferred playlist returns the live list as-is', () {
    expect(
        ids(SportsChannelMatcher.matchChannels(playlist)),
        orderedEquals(
            ['browsed::shared', 'browsed::btn', 'browsed::fs1']));
  });

  test('empty preferred playlist falls back to the live list', () {
    expect(
        ids(SportsChannelMatcher.matchChannels(playlist,
            preferredId: 'missing')),
        orderedEquals(
            ['browsed::shared', 'browsed::btn', 'browsed::fs1']));
  });
}
