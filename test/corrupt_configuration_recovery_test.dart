import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nox_iptv/services/backup_service.dart';
import 'package:nox_iptv/services/settings_bundle.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/utils/constants.dart';

/// AUD-004: restore, device transfer and a plain storage fault all write the
/// playlist preference, and startup has no recovery path of its own — a single
/// unreadable value used to make every launch fail and Retry repeat the same
/// parse. The app must always come up, with whatever it can still read.
const _validProfile =
    '[{"id":"source","name":"Source","mode":"m3u","m3uUrl":"https://example.test/list.m3u"}]';

Future<BackupFile> _writeBackup(
    Directory dir, Map<String, Object?> values) async {
  final file = File('${dir.path}${Platform.pathSeparator}'
      '${BackupService.prefix}2026-01-01T00-00-00-000${BackupService.suffix}');
  await file.writeAsString(jsonEncode({'format': 1, 'values': values}));
  return BackupFile(path: file.path, createdAt: DateTime(2026), bytes: 1);
}

Future<StorageService> _storage(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final storage = StorageService();
  await storage.init();
  return storage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('streamsports-corrupt-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('reading playlists', () {
    test('a value that is not JSON does not throw', () async {
      final storage =
          await _storage({AppConstants.keyPlaylists: '{not json'});
      expect(storage.getPlaylists(), isEmpty);
    });

    test('a value that is not a list does not throw', () async {
      final storage = await _storage({
        AppConstants.keyPlaylists: '{"id":"source","name":"S","mode":"m3u"}',
      });
      expect(storage.getPlaylists(), isEmpty);
    });

    test('unreadable entries are skipped, readable ones still load', () async {
      final storage = await _storage({
        AppConstants.keyPlaylists: '['
            '{"id":"one","name":"One","mode":"m3u"},'
            '{"name":"missing id","mode":"m3u"},'
            '42,'
            'null,'
            '{"id":"two","name":"Two","mode":"xtream"}'
            ']',
      });
      expect(storage.getPlaylists().map((p) => p.id), ['one', 'two']);
    });
  });

  group('applying a payload', () {
    test('a restore whose playlist section is unreadable is refused', () async {
      final storage = await _storage({
        AppConstants.keyPlaylists: _validProfile,
        AppConstants.keyPaletteId: 'classic_tv',
      });
      final backup = await _writeBackup(temp, {
        AppConstants.keyPlaylists: '{"id":"broken"}',
        AppConstants.keyPaletteId: 'light',
      });

      await expectLater(
        BackupService.restore(storage, backup),
        throwsA(isA<StateError>()),
      );
      // Refused before anything was written: the working configuration is
      // exactly as it was.
      expect(storage.rawPreferences()[AppConstants.keyPlaylists], _validProfile);
      expect(storage.rawPreferences()[AppConstants.keyPaletteId], 'classic_tv');
    });

    test('an unreadable playlist entry never survives a restore', () async {
      final storage = await _storage({
        AppConstants.keyPlaylists: _validProfile,
      });
      final bundle = SettingsBundle.fromJson({
        'format': 1,
        'values': {
          AppConstants.keyPlaylists: '[{"id":"x"}]',
        },
      });
      expect(bundle, isNull);
      expect(storage.getPlaylists().single.id, 'source');
    });

    test('a readable payload still replaces the configuration', () async {
      final storage = await _storage({
        AppConstants.keyPlaylists: _validProfile,
        AppConstants.keyPaletteId: 'classic_tv',
      });
      final replacement = jsonEncode([
        {
          'id': 'new',
          'name': 'New',
          'mode': 'm3u',
          'm3uUrl': 'https://example.test/b.m3u',
        }
      ]);
      final backup = await _writeBackup(temp, {
        AppConstants.keyPlaylists: replacement,
        AppConstants.keyPaletteId: 'light',
      });

      await BackupService.restore(storage, backup);
      expect(storage.getPlaylists().single.id, 'new');
      expect(storage.rawPreferences()[AppConstants.keyPaletteId], 'light');
      // The replacement is a real profile, not just a blob.
      expect(storage.getPlaylists().single.name, 'New');
    });
  });
}
