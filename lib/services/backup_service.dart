import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'settings_bundle.dart';
import 'storage_service.dart';

/// One saved snapshot of this device's configuration.
class BackupFile {
  const BackupFile({
    required this.path,
    required this.createdAt,
    required this.bytes,
  });

  final String path;
  final DateTime createdAt;
  final int bytes;
}

/// Snapshots of everything a device transfer carries, written beside the app's
/// own data and restored in place.
///
/// A backup is the undo a device cannot otherwise offer: playlists, settings,
/// sports picks, favorites, channel links and channel names are replaced by a
/// transfer or a restore, and there is no per-item undo for a playlist deleted
/// by mistake. The files stay in the app's private documents folder rather than
/// shared storage, because the playlist section holds provider logins; moving
/// a configuration to another device is what `Transfer to another device` is
/// for, and it encrypts the payload.
class BackupService {
  BackupService._();

  static const String folderName = 'backups';
  static const String prefix = 'streamsports-backup-';
  static const String suffix = '.json';

  /// Older snapshots beyond this are removed when a new one is written, so a
  /// box with little storage cannot fill up with backups.
  static const int keep = 5;

  static Future<Directory> directory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$folderName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Capture every transferable section into a new file. [directory] is for
  /// tests; the app uses the private backups folder.
  static Future<BackupFile> create(StorageService storage,
      {Directory? directory}) async {
    final dir = directory ?? await BackupService.directory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final bundle = SettingsBundle.capture(storage,
        sections: TransferSection.values.toSet());
    final text = bundle.encode();
    final file = File(
        '${dir.path}${Platform.pathSeparator}$prefix${_stamp(bundle.createdAt)}$suffix');
    // Written beside the target and renamed, so an interrupted write never
    // leaves a half file that looks like a backup.
    final partial = File('${file.path}.part');
    await partial.writeAsString(text, flush: true);
    await partial.rename(file.path);
    final saved = BackupFile(
      path: file.path,
      createdAt: bundle.createdAt,
      bytes: await file.length(),
    );
    await _prune(dir);
    return saved;
  }

  /// Newest first. Anything that is not a backup file is ignored rather than
  /// failing the whole list.
  static Future<List<BackupFile>> list({Directory? directory}) async {
    final dir = directory ?? await BackupService.directory();
    if (!await dir.exists()) return const [];
    final files = <BackupFile>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (!name.startsWith(prefix) || !name.endsWith(suffix)) continue;
      // A name without a stamp is not one we wrote, so it is left alone rather
      // than offered as a backup that cannot be restored.
      final createdAt = _stampTime(name);
      if (createdAt == null) continue;
      files.add(BackupFile(
        path: entity.path,
        createdAt: createdAt,
        bytes: await entity.length(),
      ));
    }
    files.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return files;
  }

  /// Replace this device's transferred sections with the snapshot in [backup].
  /// Device-only state (resume positions, caches, update checks) is untouched.
  static Future<TransferReport> restore(
      StorageService storage, BackupFile backup) async {
    final file = File(backup.path);
    if (!await file.exists()) {
      throw StateError('That backup is no longer on this device.');
    }
    if (await file.length() > SettingsBundle.maxBytes) {
      throw StateError('That file is too large to be one of ours.');
    }
    Object? json;
    try {
      json = jsonDecode(await file.readAsString());
    } catch (_) {
      json = null;
    }
    final bundle = SettingsBundle.fromJson(json);
    if (bundle == null) {
      throw StateError('That file is not a backup this version can read.');
    }
    return bundle.applyTo(storage);
  }

  /// A backup's bytes, for handing the file to a phone on the LAN.
  static Future<List<int>> read(BackupFile backup) =>
      File(backup.path).readAsBytes();

  /// Saves a backup a phone sent us as a new backup file, so it joins the list
  /// and can be deleted or restored like any other. The bytes are validated
  /// before a file is written, so a stray file never appears as a backup.
  static Future<BackupFile> importBytes(List<int> bytes,
      {Directory? directory}) async {
    if (bytes.length > SettingsBundle.maxBytes) {
      throw StateError('That file is too large to be one of ours.');
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      json = null;
    }
    if (SettingsBundle.fromJson(json) == null) {
      throw StateError('That file is not a backup this version can read.');
    }
    final dir = directory ?? await BackupService.directory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}'
        '$prefix${_stamp(DateTime.now())}$suffix');
    final partial = File('${file.path}.part');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
    final saved = BackupFile(
      path: file.path,
      createdAt: _stampTime(file.path.split(Platform.pathSeparator).last) ??
          DateTime.now(),
      bytes: bytes.length,
    );
    await _prune(dir);
    return saved;
  }

  static Future<void> delete(BackupFile backup) async {
    final file = File(backup.path);
    if (await file.exists()) await file.delete();
  }

  static Future<void> _prune(Directory dir) async {
    final files = await list(directory: dir);
    for (final old in files.skip(keep)) {
      try {
        await delete(old);
      } catch (_) {
        // A file that cannot be removed must not fail the backup that saved
        // correctly; the next run tries again.
      }
    }
  }

  /// `streamsports-backup-20261109-073512-482.json`
  static String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}'
        '-${two(time.hour)}${two(time.minute)}${two(time.second)}'
        '-${time.millisecond.toString().padLeft(3, '0')}';
  }

  static final RegExp _stampPattern =
      RegExp(r'(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})-(\d{3})');

  /// Null when the name carries no stamp, so the caller can fall back to the
  /// file's own modification time.
  static DateTime? _stampTime(String name) {
    final match = _stampPattern.firstMatch(name);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
      int.parse(match.group(7)!),
    );
  }
}
