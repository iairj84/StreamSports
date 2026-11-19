import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nox_iptv/models/playlist_profile.dart';
import 'package:nox_iptv/services/catalog_database.dart';
import 'package:nox_iptv/services/epg_service.dart';
import 'package:nox_iptv/services/playlist_session.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/services/xtream_api_service.dart';
import 'package:nox_iptv/utils/fetch_error_text.dart';

/// AUD-003: a provider failure must never publish the login that an IPTV URL
/// carries in its query or userinfo. These strings reach Settings, the home
/// screen, logcat and screenshots, so the leak is asserted at the sanitizer and
/// at the two fetch paths that used to assign `e.toString()` verbatim.
const _secret = 'supersecret';

class _MemoryStorage extends StorageService {
  @override
  Future<void> writeCacheFile(String name, String content) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('safeFetchError', () {
    test('reduces an Xtream guide URL to its origin', () {
      final text = safeFetchError(
        http.ClientException(
          'Connection refused',
          Uri.parse(
              'http://panel.example.test:8080/xmltv.php?username=demo&password=$_secret'),
        ),
      );
      expect(text, contains('panel.example.test:8080'));
      expect(text, isNot(contains(_secret)));
      expect(text.toLowerCase(), isNot(contains('password=')));
      expect(text, isNot(contains('xmltv.php')));
    });

    test('leaves an unclassified failure readable with only the origin', () {
      final text = safeFetchError(
        http.ClientException(
          'Connection reset by peer',
          Uri.parse(
              'http://panel.example.test:8080/xmltv.php?username=demo&password=$_secret'),
        ),
      );
      expect(text, contains('http://panel.example.test:8080'));
      expect(text, contains('Connection reset by peer'));
      expect(text, isNot(contains(_secret)));
      expect(text, isNot(contains('xmltv.php')));
    });

    test('drops userinfo from an address', () {
      final text = safeFetchError(
          'SocketException: failed for http://demo:$_secret@panel.test/x.m3u');
      expect(text, contains('http://panel.test'));
      expect(text, isNot(contains(_secret)));
    });

    test('redacts credential pairs that arrive outside a URL', () {
      final text = safeFetchError(
          'Handshake failed for panel.test:8080/get.php?username=demo&password=$_secret');
      expect(text, isNot(contains(_secret)));
      expect(text.toLowerCase(), isNot(contains('password=')));
      expect(text.toLowerCase(), isNot(contains('username=demo')));
      expect(text, contains('panel.test'));
    });

    test('keeps provider messages that carry no address', () {
      const message = 'Invalid Xtream username/password';
      expect(safeFetchError(const XtreamException(message)), message);
    });

    test('names the host for a bare timeout', () {
      final text = safeFetchError(TimeoutException('timed out'),
          url: 'https://panel.test:2096/get.php?username=demo&password=$_secret');
      expect(text, contains('panel.test'));
      expect(text.toLowerCase(), contains('did not respond'));
      expect(text, isNot(contains(_secret)));
    });

    test('never returns an empty string', () {
      expect(safeFetchError(''), isNotEmpty);
      expect(safeFetchError(StateError('')), isNotEmpty);
    });
  });

  test('a failing Xtream guide refresh keeps the password out of epg.error',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('epg-redaction-');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathChannel, (_) async => dir.path);
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final epg = EpgService(storage);
    addTearDown(() async {
      epg.dispose();
      messenger.setMockMethodCallHandler(pathChannel, null);
      await databaseFactory.deleteDatabase('${dir.path}/vesper_epg.db');
      await dir.delete(recursive: true);
    });
    const url =
        'http://panel.example.test:8080/xmltv.php?username=demo&password=$_secret';
    await http.runWithClient(() async {
      await epg.refresh(url, knownChannelIds: const {'solo'});
      final error = epg.error;
      expect(error, isNotNull);
      expect(error, contains('panel.example.test'));
      expect(error, isNot(contains(_secret)));
      expect(error!.toLowerCase(), isNot(contains('password=')));
    }, () => MockClient((request) async {
      throw http.ClientException('Connection refused', request.url);
    }));
  });

  test('a failing M3U playlist load keeps the password out of session.error',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = _MemoryStorage();
    await storage.init();
    final profile = PlaylistProfile(
      id: 'redaction',
      name: 'Redaction',
      mode: 'm3u',
      m3uUrl: 'http://panel.example.test:8080/get.php',
      sortOrder: 0,
      createdAt: DateTime(2026),
    );
    final session = PlaylistSession(
      profile: profile,
      storage: storage,
      catalogDb: CatalogDatabase(),
      favoriteIds: () => const {},
      favoriteSeriesIds: () => const {},
      onNotify: () {},
    );
    addTearDown(() => session.catalogApi?.dispose());
    const url =
        'http://panel.example.test:8080/get.php?username=demo&password=$_secret';
    await http.runWithClient(() async {
      await session.loadFromUrl(url);
      final error = session.error;
      expect(error, isNotNull);
      expect(error, contains('panel.example.test'));
      expect(error, isNot(contains(_secret)));
      expect(error!.toLowerCase(), isNot(contains('password=')));
    }, () => MockClient((request) async {
      throw http.ClientException('Connection refused', request.url);
    }));
  });
}
