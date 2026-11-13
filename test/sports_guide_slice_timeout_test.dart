import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nox_iptv/models/channel.dart';
import 'package:nox_iptv/models/epg_program.dart';
import 'package:nox_iptv/services/epg_service.dart';
import 'package:nox_iptv/services/sports_channel_matcher.dart';
import 'package:nox_iptv/services/storage_service.dart';

/// The store stays readable while a heavy refresh holds it with programme
/// inserts. The hub must match on memory after a bounded wait instead of
/// stalling behind the refresh.
class _HangingGuide extends EpgService {
  _HangingGuide(super.storage);

  @override
  Future<Map<String, List<EpgProgram>>> sportsGuideSlice(
          Iterable<String> channelIds) =>
      Completer<Map<String, List<EpgProgram>>>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a busy guide store falls back to memory instead of stalling sports',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final guide = _HangingGuide(storage);
    addTearDown(guide.dispose);
    final worker = SportsChannelMatcher.background(guide,
        clock: () => DateTime.utc(2026, 10, 21, 12, 30));
    addTearDown(worker.dispose);
    await worker.prepare([
      Channel(
          id: 'p::1',
          rawId: '1',
          playlistId: 'p',
          name: 'ESPN',
          group: 'TV',
          url: 'https://example.invalid/1'),
    ]);
    // Ten seconds of slice wait, then memory matching — never forever.
    await worker.primeGuide().timeout(const Duration(seconds: 60));
  });
}
