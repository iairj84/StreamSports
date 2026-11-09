import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nox_iptv/services/backup_service.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/utils/constants.dart';

Future<StorageService> _storage([Map<String, Object> extra = const {}]) async {
  SharedPreferences.setMockInitialValues({
    AppConstants.keyPlaylists:
        '[{"id":"source","name":"Source","mode":"m3u","m3uUrl":"https://example.invalid/list.m3u"}]',
    ...extra,
  });
  final storage = StorageService();
  await storage.init();
  return storage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('streamsports-portable-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('a backup handed to a phone comes back as a restorable copy', () async {
    final source = await _storage({
      '${AppConstants.keyChannelNames}_source': '{"espn":"ESPN2"}',
    });
    final saved = await BackupService.create(source, directory: temp);
    final bytes = await BackupService.read(saved);
    expect(bytes, isNotEmpty);

    // What a phone does: keep the bytes, then hand them to another device.
    final other = await _storage();
    final imported = await BackupService.importBytes(bytes, directory: temp);
    expect(imported.bytes, bytes.length);
    expect(File(imported.path).existsSync(), isTrue);

    await BackupService.restore(other, imported);
    expect(other.getChannelNames('source'), {'espn': 'ESPN2'});
    expect(other.getPlaylists(), isNotEmpty);
  });

  test('a file that is not a backup is refused and not listed', () async {
    await _storage();
    await expectLater(
        BackupService.importBytes(utf8.encode('not a backup'), directory: temp),
        throwsA(isA<StateError>()));
    expect(await BackupService.list(directory: temp), isEmpty);
  });

  test('a missing backup cannot be read for the phone', () async {
    final storage = await _storage();
    final saved = await BackupService.create(storage, directory: temp);
    await BackupService.delete(saved);
    expect(File(saved.path).existsSync(), isFalse);
    expect(() => BackupService.read(saved), throwsA(isA<FileSystemException>()));
  });
}
