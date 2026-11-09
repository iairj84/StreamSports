import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nox_iptv/services/backup_service.dart';
import 'package:nox_iptv/services/settings_bundle.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/utils/constants.dart';

const String _renameKey = '${AppConstants.keyChannelNames}_source';

Future<StorageService> _seededStorage() async {
  SharedPreferences.setMockInitialValues({
    AppConstants.keyPlaylists: '[{"id":"source"}]',
    _renameKey: '{"espn":"ESPN2"}',
    AppConstants.keyFavorites: ['espn'],
    AppConstants.keyPaletteId: 'classic_tv',
    // Device-only state: a backup must neither carry it nor clear it.
    AppConstants.keyLastChannelId: 'channel-9',
    // Skip the one-time coverage migration so the picks stay as seeded.
    'sports_coverage_v92': true,
  });
  final storage = StorageService();
  await storage.init();
  return storage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('streamsports-backup-test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('what a backup carries', () {
    test('channel names travel with the lists, not the settings', () {
      expect(transferSectionOf(_renameKey), TransferSection.lists);
      expect(
          transferSectionOf(
              '${AppConstants.keyChannelNames}_source'
              '${AppConstants.viewerKeySuffix}kid'),
          TransferSection.lists);
      expect(transferSectionOf(AppConstants.keyChannelNames),
          TransferSection.lists);
    });

    test('device state still never travels', () {
      expect(transferSectionOf(AppConstants.keyLastChannelId), isNull);
    });
  });

  group('backup files', () {
    test('a backup writes a file the list finds', () async {
      final storage = await _seededStorage();
      final backup = await BackupService.create(storage, directory: temp);

      expect(File(backup.path).existsSync(), isTrue);
      expect(backup.bytes, greaterThan(0));
      final listed = await BackupService.list(directory: temp);
      expect(listed.length, 1);
      expect(listed.single.path, backup.path);
      expect(listed.single.bytes, backup.bytes);
      // The stamp in the name round-trips to the moment it was taken.
      expect(listed.single.createdAt.year, backup.createdAt.year);
      expect(listed.single.createdAt.month, backup.createdAt.month);
      expect(listed.single.createdAt.day, backup.createdAt.day);
    });

    test('restoring puts the saved settings and names back', () async {
      final storage = await _seededStorage();
      final backup = await BackupService.create(storage, directory: temp);

      await storage.replaceRawPreferences({
        AppConstants.keyPlaylists: '[{"id":"destination"}]',
        _renameKey: '{}',
      }, remove: [
        AppConstants.keyFavorites,
      ]);
      expect(storage.getChannelNames('source'), isEmpty);

      final report = await BackupService.restore(storage, backup);

      expect(storage.getChannelNames('source'), {'espn': 'ESPN2'});
      expect(storage.rawPreferences()[AppConstants.keyPlaylists],
          '[{"id":"source"}]');
      expect(storage.rawPreferences()[AppConstants.keyFavorites], ['espn']);
      expect(report.sections, contains(TransferSection.lists));
      // Belongs to this device, so a restore leaves it alone.
      expect(storage.rawPreferences()[AppConstants.keyLastChannelId],
          'channel-9');
    });

    test('only the newest backups are kept', () async {
      final storage = await _seededStorage();
      for (var i = 0; i < BackupService.keep + 2; i++) {
        await BackupService.create(storage, directory: temp);
        // Distinct milliseconds, so the files do not overwrite each other.
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final listed = await BackupService.list(directory: temp);
      expect(listed.length, BackupService.keep);
      // Newest first.
      for (var i = 1; i < listed.length; i++) {
        expect(listed[i - 1].createdAt.isAfter(listed[i].createdAt), isTrue,
            reason: 'backup $i is out of order');
      }
    });

    test('a file that is not one of ours is refused and left alone', () async {
      final storage = await _seededStorage();
      final junk = File('${temp.path}${Platform.pathSeparator}'
          '${BackupService.prefix}not-really${BackupService.suffix}');
      await junk.writeAsString('{not json');

      expect(await BackupService.list(directory: temp), isEmpty);
      await expectLater(
        BackupService.restore(
            storage,
            BackupFile(
                path: junk.path, createdAt: DateTime(2026), bytes: 10)),
        throwsA(isA<StateError>()),
      );
      expect(storage.getChannelNames('source'), {'espn': 'ESPN2'});
    });

    test('a deleted backup cannot be restored', () async {
      final storage = await _seededStorage();
      final backup = await BackupService.create(storage, directory: temp);
      await BackupService.delete(backup);

      expect(await BackupService.list(directory: temp), isEmpty);
      await expectLater(BackupService.restore(storage, backup),
          throwsA(isA<StateError>()));
    });
  });
}
