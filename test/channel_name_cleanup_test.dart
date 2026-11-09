import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/services/channel_name_cleanup.dart';
import 'package:nox_iptv/services/channel_names.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/utils/constants.dart';

Channel _channel(String id, String name) => Channel(
    id: 'fixture::$id',
    rawId: id,
    playlistId: 'fixture',
    name: name,
    group: 'Sports',
    url: 'https://example.invalid/never-play');

Future<StorageService> _storage(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final storage = StorageService();
  await storage.init();
  return storage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('region tags, quality markers and slot numbers come off', () {
    expect(
        ChannelNameCleanup.clean(
            'US: 001 | ESPN HD', ChannelNameCleanup.defaults),
        'ESPN');
    expect(
        ChannelNameCleanup.clean(
            'Sky Sports F1 | UK', ChannelNameCleanup.defaults),
        'Sky Sports F1');
    expect(
        ChannelNameCleanup.clean(
            '[US] BT Sport 1 UHD', ChannelNameCleanup.defaults),
        'BT Sport 1');
  });

  test('only the selected rules run', () {
    expect(
        ChannelNameCleanup.clean('US: ESPN HD', {ChannelCleanupRule.quality}),
        'US: ESPN');
    expect(ChannelNameCleanup.clean('US: ESPN HD', {ChannelCleanupRule.region}),
        'ESPN HD');
    expect(
        ChannelNameCleanup.clean('US: ESPN HD', const <ChannelCleanupRule>{}),
        'US: ESPN HD');
  });

  test('type labels come off only where a separator marks them', () {
    expect(
        ChannelNameCleanup.clean(
            'US | NEWS | CNN', ChannelNameCleanup.defaults),
        'CNN');
    expect(ChannelNameCleanup.clean('SPT: ESPN', ChannelNameCleanup.defaults),
        'ESPN');
    expect(
        ChannelNameCleanup.clean('ESPN | SPT | 2', ChannelNameCleanup.defaults),
        'ESPN | 2');
    // A brand word keeps its channel.
    expect(
        ChannelNameCleanup.clean('Sky Sports F1', ChannelNameCleanup.defaults),
        'Sky Sports F1');
    expect(ChannelNameCleanup.clean('Fox News', ChannelNameCleanup.defaults),
        'Fox News');
  });

  test('the viewer can add words the built-in rules miss', () {
    expect(
        ChannelNameCleanup.clean('ESPN SPT', ChannelNameCleanup.defaults,
            words: ['spt']),
        'ESPN');
    expect(
        ChannelNameCleanup.clean(
            'US: MOVIE: The Thing', ChannelNameCleanup.defaults,
            words: ['movie']),
        'The Thing');
    // Whole words only: a custom "spt" cannot eat SPORTS.
    expect(
        ChannelNameCleanup.clean('Fox Sports 1', ChannelNameCleanup.defaults,
            words: ['spt']),
        'Fox Sports 1');
    expect(ChannelNameCleanup.parseWords('SPT, movie , , x'), ['spt', 'movie']);
  });

  test('names that are already clean are left alone', () {
    expect(ChannelNameCleanup.clean('ESPN2', ChannelNameCleanup.defaults),
        'ESPN2');
    // A whole word only: HDTV is a name, not a quality marker.
    expect(
        ChannelNameCleanup.clean('HDTV', {ChannelCleanupRule.quality}), 'HDTV');
  });

  test('the plan skips channels named by hand', () async {
    final storage = await _storage({
      AppConstants.keyPlaylists:
          '[{"id":"fixture","name":"Fixture","mode":"m3u","m3uUrl":"https://example.invalid/list.m3u"}]',
      '${AppConstants.keyChannelNames}_fixture': '{"one":"My ESPN"}',
    });
    ChannelRenames.bind(storage);
    final renamed = _channel('one', 'My ESPN');
    final plain = _channel('two', 'US: 002 | ESPN HD');

    final plan =
        ChannelNameCleanup.plan([renamed, plain], ChannelNameCleanup.defaults);

    expect(plan.examined, 2);
    expect(plan.skippedRenamed, 1);
    expect(plan.rows.map((row) => row.channel.rawId), ['two']);
    expect(plan.rows.single.after, 'ESPN');
    expect(plan.rows.single.before, 'US: 002 | ESPN HD');
  });

  test('clearing the overrides puts the provider names back', () async {
    final storage = await _storage({
      AppConstants.keyPlaylists:
          '[{"id":"fixture","name":"Fixture","mode":"m3u","m3uUrl":"https://example.invalid/list.m3u"}]',
    });
    ChannelRenames.bind(storage);
    final channel = _channel('one', 'US: 001 | ESPN HD');

    await ChannelRenames.renameMany(storage, [(channel, 'ESPN')]);
    expect(channel.name, 'ESPN');
    expect(channel.originalName, 'US: 001 | ESPN HD');

    await ChannelRenames.renameMany(storage, [(channel, '')]);
    expect(channel.name, 'US: 001 | ESPN HD');
    expect(channel.originalName, isNull);
    expect(storage.getChannelNames('fixture'), isEmpty);
  });
}
